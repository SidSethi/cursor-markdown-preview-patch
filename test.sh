#!/usr/bin/env bash
# Smoke tests for the Cursor editable rendered Markdown preview patch scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
FAIL=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK   $label"
    ((PASS++)) || true
  else
    echo "  FAIL $label"
    ((FAIL++)) || true
  fi
}

echo "=== Syntax ==="
check "patch syntax" bash -n "$SCRIPT_DIR/patch"
check "rollback syntax" bash -n "$SCRIPT_DIR/rollback"
check "CSS has no template tokens" bash -c '
  ! grep -q "{{" "$1/custom.css"
' _ "$SCRIPT_DIR"
check "CSS has font-size variable" bash -c '
  grep -q -- "--cursor-inline-markdown-editor-font-size:" "$1/custom.css"
' _ "$SCRIPT_DIR"

echo "=== Fixtures ==="
check "patch fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  mkdir -p "$tmp/home/Library/Application Support/Cursor/User"
  cat > "$tmp/home/Library/Application Support/Cursor/User/settings.json" <<JSON
{
  "editor.fontSize": 15
}
JSON

  cat > "$tmp/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body></body>
<!-- !! VSCODE-CUSTOM-CSS-SESSION-ID old !! -->
<!-- !! VSCODE-CUSTOM-CSS-START !! -->
<style>.old { color: hotpink; }</style>
<!-- !! VSCODE-CUSTOM-CSS-END !! -->
</html>
HTML

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    "$1/patch" >/dev/null

  grep -q -- "--cursor-inline-markdown-editor-font-size: 15px" "$tmp/workbench.html"
  ! grep -q "hotpink" "$tmp/workbench.html"
  ! grep -q "SESSION-ID old" "$tmp/workbench.html"
' _ "$SCRIPT_DIR"

check "patch explicit font-size fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  mkdir -p "$tmp/home/Library/Application Support/Cursor/User"
  cat > "$tmp/home/Library/Application Support/Cursor/User/settings.json" <<JSON
{
  "editor.fontSize": 15
}
JSON

  cat > "$tmp/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body></body>
</html>
HTML

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    "$1/patch" --font-size 18 >/dev/null

  grep -q -- "--cursor-inline-markdown-editor-font-size: 18px" "$tmp/workbench.html"
' _ "$SCRIPT_DIR"

check "patch CSS font-size fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  mkdir -p "$tmp/home/Library/Application Support/Cursor/User"
  cat > "$tmp/home/Library/Application Support/Cursor/User/settings.json" <<JSON
{
  "editor.fontSize": 15
}
JSON

  cat > "$tmp/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body></body>
</html>
HTML

  expected=$(sed -nE "s/^[[:space:]]*--cursor-inline-markdown-editor-font-size:[[:space:]]*([^;]+);.*/\\1/p" "$1/custom.css" | head -n 1)
  [[ -n "$expected" ]]

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    "$1/patch" --font-size css >/dev/null

  grep -q -- "--cursor-inline-markdown-editor-font-size: $expected" "$tmp/workbench.html"
  ! grep -q -- "--cursor-inline-markdown-editor-font-size: 15px" "$tmp/workbench.html"
' _ "$SCRIPT_DIR"

check "patch invalid font-size fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  cat > "$tmp/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body></body>
</html>
HTML

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    "$1/patch" --font-size huge >/dev/null 2>&1 && exit 1
  exit 0
' _ "$SCRIPT_DIR"

check "rollback fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  mkdir -p "$tmp/home/Library/Application Support/Cursor/User"
  cat > "$tmp/home/Library/Application Support/Cursor/User/settings.json" <<JSON
{
  "editor.fontSize": 15
}
JSON

  cat > "$tmp/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body>original</body>
</html>
HTML

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_WORKBENCH_PATCH_BACKUP_ROOT="$tmp/backups" \
    "$1/patch" >/dev/null

  grep -q -- "--cursor-inline-markdown-editor-font-size: 15px" "$tmp/workbench.html"

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_WORKBENCH_PATCH_BACKUP_ROOT="$tmp/backups" \
    "$1/rollback" >/dev/null

  grep -q "<body>original</body>" "$tmp/workbench.html"
  ! grep -q "VSCODE-CUSTOM-CSS-START" "$tmp/workbench.html"
' _ "$SCRIPT_DIR"

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"

if ((FAIL > 0)); then
  exit 1
fi
