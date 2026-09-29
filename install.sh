#!/usr/bin/env bash
# One-step bootstrap: install this skill into the Claude Code config dir and run it once.
#
#   ./install.sh [installer options]      e.g. ./install.sh --check   or   ./install.sh --exclude instructions_personal.md
#
# What it does:
#   1. copies this directory to $CLAUDE_CONFIG_DIR/skills/install-update-instructions (default ~/.claude/skills/...),
#      moving any previous copy of the skill to $CLAUDE_CONFIG_DIR/skills_backup/<name>.<timestamp>/
#   2. runs the installed skill's scripts/install_update.sh with the options given here
# Works from an extracted tarball or straight from a shared/cloned directory. Requires bash, awk, diff, cmp.
#
# Other agents:  ./install.sh --agent codex|gemini|opencode|all|file|print [options]
#   installs the skill to $AGENTS_HOME/skills/install-update-instructions (default ~/.agents/skills, the user-level
#   skills directory Codex scans) and runs scripts/install_agents.sh, which writes each agent's global rules file.
#   Without --agent (or with --agent claude) this is the Claude Code install described above.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="install-update-instructions"
CHECK=0; AGENT=claude; PASS=()
while (( $# )); do
  case "$1" in
    --agent) [[ $# -ge 2 ]] || { echo "ERROR: --agent needs a name" >&2; exit 1; }; AGENT="$2"; shift ;;
    --check) CHECK=1; PASS+=("$1") ;;
    *) PASS+=("$1") ;;
  esac
  shift
done
if [[ "$AGENT" == "claude" ]]; then
  CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  SKILLS="$CLAUDE_HOME/skills"
  INSTALLER=scripts/install_update.sh
else
  CLAUDE_HOME="${AGENTS_HOME:-$HOME/.agents}"      # backup dir lives next to the skills dir
  SKILLS="$CLAUDE_HOME/skills"
  INSTALLER=scripts/install_agents.sh
  PASS=(--agent "$AGENT" "${PASS[@]}")
fi
TARGET="$SKILLS/$NAME"
set -- "${PASS[@]}"

for f in SKILL.md scripts/install_update.sh instructions/instructions.md; do
  [[ -r "$HERE/$f" ]] || { echo "ERROR: incomplete package, missing $HERE/$f" >&2; exit 2; }
done

if [[ "$HERE" == "$TARGET" ]]; then
  echo "== skill already runs from $TARGET"
elif [[ -d "$TARGET" ]] && diff -rq --exclude=MANIFEST.sha256 "$HERE" "$TARGET" >/dev/null 2>&1; then
  echo "== skill already installed and identical: $TARGET"
else
  if [[ -d "$TARGET" ]]; then
    bak="$CLAUDE_HOME/skills_backup/$NAME.$(date +%Y%m%d-%H%M%S)"
    if (( CHECK )); then echo "== (dry run) previous skill copy would move to $bak"; else echo "== previous skill copy moved to $bak"; mkdir -p "$(dirname "$bak")"; mv "$TARGET" "$bak"; fi
  fi
  if (( CHECK )); then echo "== (dry run) skill would be installed to $TARGET"; else echo "== installing skill to $TARGET"; fi
  (( CHECK )) || { mkdir -p "$SKILLS"; cp -R "$HERE" "$TARGET"; chmod +x "$TARGET/install.sh" "$TARGET/scripts/"*.sh; }
fi

echo
# A dry run must not depend on the (possibly older or absent) installed copy: run this package's installer.
if (( CHECK )); then exec bash "$HERE/$INSTALLER" "$@"; fi
exec bash "$TARGET/$INSTALLER" "$@"
