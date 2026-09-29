#!/usr/bin/env bash
# Refresh the bundled instruction files and package the skill for sharing.
#
# Usage:
#   build_bundle.sh                    package the bundle as it is (writes VERSION, MANIFEST.sha256, tarball)
#   build_bundle.sh --from DIR         first copy DIR/*.md into <skill>/instructions/ (shows diffs), then package
#   build_bundle.sh --out DIR          write the tarball to DIR (default: <skill>/../../dist)
#   build_bundle.sh --check            with --from: only show what would change, write nothing
#
# Output: <out>/install-update-instructions-<version>.tar.gz
#   The tarball extracts to a single directory `install-update-instructions/` that contains everything:
#   run `install-update-instructions/install.sh` on the target machine.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="install-update-instructions"   # fixed: install.sh installs under this name regardless of the source dir name
BUNDLE="$SKILL_DIR/instructions"
OUT="$(cd "$SKILL_DIR/../.." && pwd)/dist"
FROM=""; CHECK=0
while (( $# )); do
  case "$1" in
    --from) [[ $# -ge 2 ]] || { echo "ERROR: --from needs a directory" >&2; exit 1; }; FROM="$2"; shift ;;
    --out)  [[ $# -ge 2 ]] || { echo "ERROR: --out needs a directory" >&2; exit 1; }; OUT="$2"; shift ;;
    --check) CHECK=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

# --- 1. optional refresh of the bundled files from an edited directory --------------
if [[ -n "$FROM" ]]; then
  [[ -d "$FROM" ]] || { echo "ERROR: --from directory not found: $FROM" >&2; exit 2; }
  n=0
  for src in "$FROM"/*.md; do
    [[ -e "$src" ]] || continue
    f="$(basename "$src")"; n=$((n+1))
    if [[ ! -e "$BUNDLE/$f" ]]; then
      echo "== ADD $f to bundle"
    elif ! cmp -s "$src" "$BUNDLE/$f"; then
      echo "== UPDATE $f in bundle  (bundle -> $FROM)"
      diff -u "$BUNDLE/$f" "$src" || true
    else
      echo "== unchanged $f"; continue
    fi
    (( CHECK )) || cp "$src" "$BUNDLE/$f"
  done
  (( n )) || { echo "ERROR: no *.md files in $FROM" >&2; exit 2; }
  if (( CHECK )); then echo; echo "DRY RUN (--check): nothing was written."; exit 0; fi
  echo
fi

# --- 2. version + manifest ------------------------------------------------------------
[[ -r "$BUNDLE/instructions.md" ]] || { echo "ERROR: bundle has no instructions.md: $BUNDLE" >&2; exit 2; }
hash="$(cd "$BUNDLE" && cat $(ls -1 *.md | sort) | sha256sum | cut -c1-8)"
version="$(date +%Y.%m.%d).$hash"
printf '%s\n' "$version" > "$SKILL_DIR/VERSION"
( cd "$SKILL_DIR" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum ) > "$SKILL_DIR/MANIFEST.sha256"
chmod +x "$SKILL_DIR/install.sh" "$SKILL_DIR/scripts/"*.sh

# --- 3. tarball -----------------------------------------------------------------------
mkdir -p "$OUT"
tarball="$OUT/$NAME-$version.tar.gz"
tar -czf "$tarball" -C "$(dirname "$SKILL_DIR")" --transform "s|^$(basename "$SKILL_DIR")|$NAME|" "$(basename "$SKILL_DIR")"
ln -sfn "$(basename "$tarball")" "$OUT/$NAME-latest.tar.gz"

echo "Bundle version: $version"
echo "Files:          $(cd "$BUNDLE" && ls -1 *.md | tr '\n' ' ')"
echo "Tarball:        $tarball"
echo "Latest link:    $OUT/$NAME-latest.tar.gz"
echo
echo "Install elsewhere:  tar xzf $NAME-$version.tar.gz && ./$NAME/install.sh"
