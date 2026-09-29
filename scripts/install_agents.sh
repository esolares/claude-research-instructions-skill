#!/usr/bin/env bash
# Install or update the bundled instruction files for coding agents other than Claude Code.
#
# Usage:
#   install_agents.sh --agent codex|gemini|opencode|all [--check] [--exclude FILE]...
#   install_agents.sh --agent file --file PATH [--check] [--exclude FILE]...   any tool that reads a markdown rules file
#   install_agents.sh --agent print [--exclude FILE]...                         print the block to stdout (paste into a UI)
#
# What each agent gets (paths verified against the agents' documentation, 2026-09-11):
#   codex     ~/.codex/AGENTS.md          managed block with the instructions INLINED (Codex has no import syntax;
#                                         combined AGENTS.md size is capped by project_doc_max_bytes, 32 KiB default)
#   gemini    ~/.gemini/GEMINI.md         managed block that @imports the installed files (absolute paths)
#   opencode  ~/.config/opencode/AGENTS.md  managed block, inlined
#   file      PATH                        managed block, inlined
#   all       every agent above whose config directory already exists
# In every case the files themselves are installed to $AGENTS_HOME/instructions/ (default ~/.agents/instructions),
# next to the user-level skills directory ~/.agents/skills that Codex scans.
#
# Env overrides: AGENTS_HOME, CODEX_HOME (~/.codex), GEMINI_HOME (~/.gemini), XDG_CONFIG_HOME (opencode).
# Exit codes: 0 ok, 1 usage error, 2 missing source, 3 write failure.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SKILL_DIR/instructions"
VERSION="$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unversioned)"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
DST="$AGENTS_HOME/instructions"
BEGIN_MARK='<!-- BEGIN global-instructions (managed by the install-update-instructions skill; do not edit inside this block) -->'
END_MARK='<!-- END global-instructions -->'

AGENT=""; FILE=""; CHECK=0; EXCLUDE=()
while (( $# )); do
  case "$1" in
    --agent) [[ $# -ge 2 ]] || { echo "ERROR: --agent needs a name" >&2; exit 1; }; AGENT="$2"; shift ;;
    --file)  [[ $# -ge 2 ]] || { echo "ERROR: --file needs a path" >&2; exit 1; }; FILE="$2"; shift ;;
    --check) CHECK=1 ;;
    --exclude) [[ $# -ge 2 ]] || { echo "ERROR: --exclude needs a file name" >&2; exit 1; }; EXCLUDE+=("$2"); shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done
[[ -n "$AGENT" ]] || { echo "ERROR: --agent is required (codex|gemini|opencode|file|print|all)" >&2; exit 1; }
[[ -d "$SRC" ]] || { echo "ERROR: bundle directory not found: $SRC" >&2; exit 2; }

# Files: every *.md in the bundle, instructions.md first, minus --exclude.
FILES=()
[[ -r "$SRC/instructions.md" ]] && FILES+=(instructions.md)
while IFS= read -r f; do [[ "$f" == "instructions.md" ]] || FILES+=("$f"); done < <(cd "$SRC" && ls -1 *.md 2>/dev/null | sort)
if (( ${#EXCLUDE[@]} )); then
  kept=(); for f in "${FILES[@]}"; do s=0; for x in "${EXCLUDE[@]}"; do [[ "$f" == "$x" ]] && s=1; done; (( s )) || kept+=("$f"); done; FILES=("${kept[@]}")
fi
(( ${#FILES[@]} )) || { echo "ERROR: no instruction files to install" >&2; exit 2; }

heading_for() {
  case "$1" in
    instructions.md)          echo "Engineering instructions (project-agnostic, always apply)" ;;
    instructions_personal.md) echo "Domain instructions (always apply)" ;;
    *)                        echo "Additional instructions: $1 (always apply)" ;;
  esac
}
preamble() {
  cat <<EOF
# Global Instructions

The instructions below are mandatory in every session, in every project, and for every agent (main agent, forks, and subagents). They override default behavior. Read them fully before doing any work.

When launching a subagent, its briefing MUST state that it is bound by these instructions and MUST include the requirements from \`instructions.md\` §3 (task-status reporting), §4 (no destructive operations without approval), and §6 (verify against current documentation, never memory).

Installed by the \`install-update-instructions\` skill (bundle $VERSION). Do not edit inside this block; re-run the skill's installer to update, and only when the user asks.
EOF
}
# build_block MODE  (inline: file contents embedded; import: @path lines)
build_block() {
  local mode="$1"
  printf '%s\n' "$BEGIN_MARK"; preamble
  for f in "${FILES[@]}"; do
    printf '\n## %s\n' "$(heading_for "$f")"
    if [[ "$mode" == "import" ]]; then printf '@%s\n' "$DST/$f"
    else printf '\n'; cat "$SRC/$f"; fi
  done
  printf '%s\n' "$END_MARK"
}

# install_files: bundle -> $DST (unless print mode)
install_files() {
  local installed=0 updated=0 unchanged=0 f
  (( CHECK )) || mkdir -p "$DST" || { echo "ERROR: cannot create $DST" >&2; exit 3; }
  for f in "${FILES[@]}"; do
    if [[ ! -e "$DST/$f" ]]; then echo "== INSTALL $f -> $DST"; (( CHECK )) || { cp "$SRC/$f" "$DST/$f"; chmod 600 "$DST/$f"; }; installed=$((installed+1))
    elif ! cmp -s "$SRC/$f" "$DST/$f"; then echo "== UPDATE $f  (local -> bundle)"; diff -u "$DST/$f" "$SRC/$f" || true; (( CHECK )) || { cp "$SRC/$f" "$DST/$f"; chmod 600 "$DST/$f"; }; updated=$((updated+1))
    else echo "== unchanged $f"; unchanged=$((unchanged+1)); fi
  done
  echo "   files: installed=$installed updated=$updated unchanged=$unchanged"
}

# write_loader LOADER_PATH MODE LABEL: create or replace the managed block, preserving other content.
write_loader() {
  local loader="$1" mode="$2" label="$3" block candidate rest action
  block="$(build_block "$mode")"
  if [[ "$mode" == "inline" ]]; then
    local bytes; bytes=$(printf '%s\n' "$block" | wc -c)
    if [[ "$label" == "codex" ]] && (( bytes > 32768 )); then
      echo "   WARNING: inlined block is $bytes bytes; Codex caps combined AGENTS.md content at project_doc_max_bytes (32768 default)."
      echo "            Set  project_doc_max_bytes = 65536  in ~/.codex/config.toml, or use --exclude to drop a file."
    fi
  fi
  if [[ ! -e "$loader" ]]; then
    action=create; echo "== CREATE $loader ($label, $mode)"
    (( CHECK )) || { mkdir -p "$(dirname "$loader")"; printf '%s\n' "$block" > "$loader" || { echo "ERROR: cannot write $loader" >&2; exit 3; }; }
  else
    rest="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '$0==b{i=1;next} i&&$0==e{i=0;next} i{next} {print}' "$loader" | cat -s)"
    if [[ -n "$rest" ]]; then candidate="$(printf '%s\n\n%s\n' "$rest" "$block")"; else candidate="$(printf '%s\n' "$block")"; fi
    if [[ "$(cat "$loader")" == "$candidate" ]]; then action=unchanged; echo "== loader OK: $loader already has the current block"
    elif grep -qF "$BEGIN_MARK" "$loader"; then action=replace; echo "== REPLACE managed block in $loader ($label, $mode; other content preserved)"
    else action=append; echo "== APPEND managed block to $loader ($label, $mode; existing content preserved)"; fi
    if [[ "$action" != unchanged ]] && (( ! CHECK )); then printf '%s\n' "$candidate" > "$loader" || { echo "ERROR: cannot write $loader" >&2; exit 3; }; fi
  fi
  echo "   loader=$action"
}

run_agent() {
  case "$1" in
    codex)    write_loader "${CODEX_HOME:-$HOME/.codex}/AGENTS.md" inline codex ;;
    gemini)   write_loader "${GEMINI_HOME:-$HOME/.gemini}/GEMINI.md" import gemini ;;
    opencode) write_loader "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md" inline opencode ;;
    file)     [[ -n "$FILE" ]] || { echo "ERROR: --agent file needs --file PATH" >&2; exit 1; }; write_loader "$FILE" inline file ;;
    *) echo "ERROR: unknown agent: $1" >&2; exit 1 ;;
  esac
}

echo "Bundle:  $SRC  (version: $VERSION)" >&2
echo "Files:   ${FILES[*]}" >&2
case "$AGENT" in
  print) build_block inline; exit 0 ;;
  all)
    echo "Target:  $DST"; install_files
    found=0
    [[ -d "${CODEX_HOME:-$HOME/.codex}" ]] && { run_agent codex; found=1; }
    [[ -d "${GEMINI_HOME:-$HOME/.gemini}" ]] && { run_agent gemini; found=1; }
    [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ]] && { run_agent opencode; found=1; }
    (( found )) || echo "== no agent config directories found (~/.codex, ~/.gemini, ~/.config/opencode); files installed only"
    ;;
  codex|gemini|opencode|file)
    echo "Target:  $DST"; install_files; run_agent "$AGENT" ;;
  *) echo "ERROR: unknown agent: $AGENT (codex|gemini|opencode|file|print|all)" >&2; exit 1 ;;
esac
echo
(( CHECK )) && echo "DRY RUN (--check): nothing was written."
echo "Changes take effect in the agent's next new session."
