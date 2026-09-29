#!/usr/bin/env bash
# Install or update the global Claude Code instruction files bundled with this skill.
#
# Usage:
#   install_update.sh                 install missing files, update changed ones (shows diffs)
#   install_update.sh --check         dry run: report what would change, write nothing
#   install_update.sh --exclude FILE  skip a bundled file (repeatable), e.g. --exclude instructions_personal.md
#   install_update.sh --source DIR    take the files from DIR instead of the bundle (advanced)
#   install_update.sh --version       print the bundle version and exit
#
# Bundle (source):  <skill>/instructions/*.md
# Local copies:     $CLAUDE_CONFIG_DIR/instructions/   (default ~/.claude/instructions)
# Loader:           $CLAUDE_CONFIG_DIR/CLAUDE.md       a marked block that @imports each installed file
#
# Exit codes: 0 ok, 1 usage/argument error, 2 missing source, 3 write failure.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SKILL_DIR/instructions"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DST="$CLAUDE_HOME/instructions"
CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"
BEGIN_MARK='<!-- BEGIN global-instructions (managed by the install-update-instructions skill; do not edit inside this block) -->'
END_MARK='<!-- END global-instructions -->'

CHECK=0
EXCLUDE=()
while (( $# )); do
  case "$1" in
    --check) CHECK=1 ;;
    --exclude) [[ $# -ge 2 ]] || { echo "ERROR: --exclude needs a file name" >&2; exit 1; }; EXCLUDE+=("$2"); shift ;;
    --source) [[ $# -ge 2 ]] || { echo "ERROR: --source needs a directory" >&2; exit 1; }; SRC="$2"; shift ;;
    --version) cat "$SKILL_DIR/VERSION" 2>/dev/null || echo "unversioned"; exit 0 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

[[ -d "$SRC" ]] || { echo "ERROR: source directory not found: $SRC" >&2; exit 2; }

# Files to install: every *.md in the bundle, instructions.md first, minus --exclude.
FILES=()
[[ -r "$SRC/instructions.md" ]] && FILES+=(instructions.md)
while IFS= read -r f; do
  [[ "$f" == "instructions.md" ]] && continue
  FILES+=("$f")
done < <(cd "$SRC" && ls -1 *.md 2>/dev/null | sort)
if (( ${#EXCLUDE[@]} )); then
  kept=()
  for f in "${FILES[@]}"; do
    skip=0; for x in "${EXCLUDE[@]}"; do [[ "$f" == "$x" ]] && skip=1; done
    (( skip )) && echo "== skipping $f (--exclude)" || kept+=("$f")
  done
  FILES=("${kept[@]}")
fi
(( ${#FILES[@]} )) || { echo "ERROR: no instruction files to install in $SRC" >&2; exit 2; }

echo "Bundle:  $SRC  (version: $(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unversioned))"
echo "Target:  $DST"
echo "Loader:  $CLAUDE_MD"
echo

# --- 1. copy instruction files -------------------------------------------------
installed=0; updated=0; unchanged=0
if (( ! CHECK )); then mkdir -p "$DST" || { echo "ERROR: cannot create $DST" >&2; exit 3; }; fi
for f in "${FILES[@]}"; do
  if [[ ! -e "$DST/$f" ]]; then
    echo "== INSTALL $f (no local copy yet)"
    if (( ! CHECK )); then cp "$SRC/$f" "$DST/$f" && chmod 600 "$DST/$f"; fi
    installed=$((installed+1))
  elif ! cmp -s "$SRC/$f" "$DST/$f"; then
    echo "== UPDATE $f  (local -> bundle)"
    diff -u "$DST/$f" "$SRC/$f" || true
    if (( ! CHECK )); then cp "$SRC/$f" "$DST/$f" && chmod 600 "$DST/$f"; fi
    updated=$((updated+1))
  else
    echo "== unchanged $f"
    unchanged=$((unchanged+1))
  fi
done

# --- 2. loader block in CLAUDE.md -----------------------------------------------
heading_for() {
  case "$1" in
    instructions.md)          echo "Engineering instructions (project-agnostic, always apply)" ;;
    instructions_personal.md) echo "Domain instructions (always apply)" ;;
    *)                        echo "Additional instructions: $1 (always apply)" ;;
  esac
}
build_block() {
  printf '%s\n' "$BEGIN_MARK"
  cat <<'EOF'
# Global Instructions

The files imported below are mandatory in every session, in every project, and for every agent (main agent, forks, and subagents). They override default behavior. Read them fully before doing any work.

When launching a subagent, its briefing MUST state that it is bound by these instructions and MUST include the requirements from `instructions.md` §3 (task-status reporting), §4 (no destructive operations without approval), and §6 (verify against current documentation, never memory).

These are local copies installed by the `install-update-instructions` skill. Do not edit them by hand, and do not re-run the installer on your own initiative; run it only when the user asks to install or update the instructions, then report what changed.
EOF
  for f in "${FILES[@]}"; do
    printf '\n## %s\n@instructions/%s\n' "$(heading_for "$f")" "$f"
  done
  printf '%s\n' "$END_MARK"
}
NEW_BLOCK="$(build_block)"

# The legacy unmarked block written by the first version of this installer ran from a
# "# Global Instructions — <owner>" heading to the "@instructions/instructions_personal.md" line.
# Drop exactly that range and keep everything else in the file byte-for-byte.
strip_legacy() {
  awk '
    /^# Global Instructions — / && !legacy { legacy = 1 }
    legacy {
      if ($0 ~ /^@instructions\/instructions_personal\.md$/) { legacy = 0 }
      next
    }
    { print }
  ' "$1"
}

loader_action="none"
if [[ ! -e "$CLAUDE_MD" ]]; then
  loader_action="create"
  echo "== CREATE $CLAUDE_MD with the loader block"
  if (( ! CHECK )); then
    mkdir -p "$CLAUDE_HOME"
    printf '%s\n' "$NEW_BLOCK" > "$CLAUDE_MD" && chmod 600 "$CLAUDE_MD" || { echo "ERROR: cannot write $CLAUDE_MD" >&2; exit 3; }
  fi
else
  tmp="$(mktemp)"
  if grep -qF "$BEGIN_MARK" "$CLAUDE_MD"; then
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0 == b {inblk=1; next} inblk && $0 == e {inblk=0; next} inblk {next} {print}' "$CLAUDE_MD" > "$tmp"
    had="managed"
  elif grep -q '^# Global Instructions — ' "$CLAUDE_MD" && grep -q '^@instructions/instructions_personal\.md$' "$CLAUDE_MD"; then
    strip_legacy "$CLAUDE_MD" > "$tmp"
    had="legacy"
  else
    cp "$CLAUDE_MD" "$tmp"
    had="none"
  fi
  # Squeeze blank-line runs left by a removed block, trim trailing blank lines, then append the block.
  rest="$(cat -s "$tmp")"
  if [[ -n "$rest" ]]; then candidate="$(printf '%s\n\n%s\n' "$rest" "$NEW_BLOCK")"; else candidate="$(printf '%s\n' "$NEW_BLOCK")"; fi
  rm -f "$tmp"
  if [[ "$(cat "$CLAUDE_MD")" == "$candidate" ]]; then
    loader_action="unchanged"
    echo "== loader OK: $CLAUDE_MD already has the current block"
  else
    case "$had" in
      managed) loader_action="replace"; echo "== REPLACE managed block in $CLAUDE_MD (other content preserved)" ;;
      legacy)  loader_action="migrate"; echo "== MIGRATE legacy loader block in $CLAUDE_MD to the managed block (other content preserved)" ;;
      none)    loader_action="append";  echo "== APPEND loader block to existing $CLAUDE_MD (existing content preserved)" ;;
    esac
    if (( ! CHECK )); then
      printf '%s\n' "$candidate" > "$CLAUDE_MD" || { echo "ERROR: cannot write $CLAUDE_MD" >&2; exit 3; }
    fi
  fi
fi

echo
(( CHECK )) && echo "DRY RUN (--check): nothing was written."
echo "Summary: installed=$installed updated=$updated unchanged=$unchanged loader=$loader_action"
echo "Installed files: ${FILES[*]}"
echo "Changes take effect in the next new Claude Code session."
