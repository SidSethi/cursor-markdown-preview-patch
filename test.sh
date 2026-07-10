#!/usr/bin/env bash
# Smoke tests for the Cursor editable rendered Markdown preview patch scripts.
#
# shellcheck disable=SC2016

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
check "shared shell library syntax" bash -n "$SCRIPT_DIR/lib/cursor-patch-common.sh"
check "patch syntax" bash -n "$SCRIPT_DIR/patch"
check "rollback syntax" bash -n "$SCRIPT_DIR/rollback"
check "ensure-patched syntax" bash -n "$SCRIPT_DIR/ensure-patched"
check "install-auto-reapply syntax" bash -n "$SCRIPT_DIR/install-auto-reapply"
check "verify-auto-reapply syntax" bash -n "$SCRIPT_DIR/verify-auto-reapply"
check "README demo generator syntax" bash -n "$SCRIPT_DIR/docs/generate-readme-demo.sh"
if command -v node >/dev/null 2>&1; then
  check "custom JS syntax" node --check "$SCRIPT_DIR/preview/custom.js"
fi
if command -v swiftc >/dev/null 2>&1; then
  check "runner Swift syntax" swiftc -parse "$SCRIPT_DIR/auto-reapply/runner/CursorMarkdownPreviewPatchEnsure.swift"
fi
if command -v plutil >/dev/null 2>&1; then
  check "LaunchAgent example plist syntax" plutil -lint "$SCRIPT_DIR/auto-reapply/launchd/com.example.cursor-markdown-preview-patch.ensure.plist"
fi
check "CSS has no template tokens" bash -c '
  ! grep -q "{{" "$1/preview/custom.css"
' _ "$SCRIPT_DIR"
check "CSS has font-size variable" bash -c '
  grep -q -- "--cursor-inline-markdown-editor-font-size:" "$1/preview/custom.css"
' _ "$SCRIPT_DIR"
check "JS has frontmatter marker" bash -c '
  grep -q -- "cursorMarkdownPreviewFrontmatter" "$1/preview/custom.js"
' _ "$SCRIPT_DIR"
check "JS has heading fold runtime" bash -c '
  grep -q -- "cursorMarkdownPreviewHeadingFolds" "$1/preview/custom.js"
' _ "$SCRIPT_DIR"
check "CSS has heading fold toolbar" bash -c '
  grep -q -- "cursor-md-heading-fold-toolbar" "$1/preview/custom.css"
' _ "$SCRIPT_DIR"
check "CSS has heading level label gutter" bash -c '
  grep -q -- "--cursor-md-heading-level-label" "$1/preview/custom.css"
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
  grep -q -- "cursor-markdown-preview-patch.js" "$tmp/workbench.html"
  grep -q -- "cursorMarkdownPreviewFrontmatter" "$tmp/cursor-markdown-preview-patch.js"
  grep -q -- "cursorMarkdownPreviewHeadingFolds" "$tmp/cursor-markdown-preview-patch.js"
  grep -qE -- "<script src=\"\\./cursor-markdown-preview-patch\\.js\\?v=[0-9-]+\"></script>" "$tmp/workbench.html"
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

check "patch Trusted Types repair fixture" bash -c '
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
<head>
<meta
  http-equiv="Content-Security-Policy"
  content="
    require-trusted-types-for
      '\''script'\''
    ;
    trusted-types
      amdLoader
      solidjs
    ;
  "/>
</head>
<body></body>
</html>
HTML

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    "$1/patch" >/dev/null

  grep -q -- "streamingMarkdownPolicy" "$tmp/workbench.html"
  grep -q -- "mermaidDiagram2" "$tmp/workbench.html"
  grep -q -- "mermaidDiagramOuter" "$tmp/workbench.html"
  grep -q -- "cursorMarkdownPreviewHeadingFolds" "$tmp/cursor-markdown-preview-patch.js"
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

  expected=$(sed -nE "s/^[[:space:]]*--cursor-inline-markdown-editor-font-size:[[:space:]]*([^;]+);.*/\\1/p" "$1/preview/custom.css" | head -n 1)
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
  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_WORKBENCH_PATCH_BACKUP_ROOT="$tmp/backups" \
    "$1/patch" >/dev/null

  grep -q -- "--cursor-inline-markdown-editor-font-size: 15px" "$tmp/workbench.html"
  test -f "$tmp/cursor-markdown-preview-patch.js"

  HOME="$tmp/home" CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_WORKBENCH_PATCH_BACKUP_ROOT="$tmp/backups" \
    "$1/rollback" >/dev/null

  grep -q "<body>original</body>" "$tmp/workbench.html"
  ! grep -q "VSCODE-CUSTOM-CSS-START" "$tmp/workbench.html"
  ! test -e "$tmp/cursor-markdown-preview-patch.js"
' _ "$SCRIPT_DIR"

check "ensure-patched skips patched fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  cat > "$tmp/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body></body>
<!-- !! VSCODE-CUSTOM-CSS-START !! -->
<script src="./cursor-markdown-preview-patch.js"></script>
<!-- !! VSCODE-CUSTOM-CSS-END !! -->
</html>
HTML

  cat > "$tmp/cursor-markdown-preview-patch.js" <<JS
window.cursorMarkdownPreviewFrontmatter = true;
window.cursorMarkdownPreviewHeadingFolds = true;
JS

  cat > "$tmp/fail-if-called" <<SH
#!/usr/bin/env bash
exit 99
SH
  chmod +x "$tmp/fail-if-called"

  CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_CMD="$tmp/fail-if-called" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0 \
    CURSOR_MARKDOWN_PREVIEW_PATCH_LOCK_DIR="$tmp/lock" \
    "$1/ensure-patched" >/dev/null
  ! test -e "$tmp/patch-called"
' _ "$SCRIPT_DIR"

check "ensure-patched applies missing fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  cat > "$tmp/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body></body>
</html>
HTML

  cat > "$tmp/fake-patch" <<SH
#!/usr/bin/env bash
set -euo pipefail
touch "\$TMP_FIXTURE/patch-called"
cat > "\$CURSOR_WORKBENCH_HTML" <<HTML
<!DOCTYPE html>
<html>
<body></body>
<!-- !! VSCODE-CUSTOM-CSS-START !! -->
<script src="./cursor-markdown-preview-patch.js"></script>
<!-- !! VSCODE-CUSTOM-CSS-END !! -->
</html>
HTML
cat > "\$(dirname "\$CURSOR_WORKBENCH_HTML")/cursor-markdown-preview-patch.js" <<JS
window.cursorMarkdownPreviewFrontmatter = true;
window.cursorMarkdownPreviewHeadingFolds = true;
JS
SH
  chmod +x "$tmp/fake-patch"

  TMP_FIXTURE="$tmp" \
    CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_CMD="$tmp/fake-patch" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0 \
    CURSOR_MARKDOWN_PREVIEW_PATCH_LOCK_DIR="$tmp/lock" \
    "$1/ensure-patched" >/dev/null
  test -f "$tmp/patch-called"
  grep -q "VSCODE-CUSTOM-CSS-START" "$tmp/workbench.html"
  grep -q "cursorMarkdownPreviewFrontmatter" "$tmp/cursor-markdown-preview-patch.js"
  grep -q "cursorMarkdownPreviewHeadingFolds" "$tmp/cursor-markdown-preview-patch.js"
' _ "$SCRIPT_DIR"

check "ensure-patched patches ShipIt update fixture" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  workbench_dir="$tmp/shipit/update.test/Cursor.app/Contents/Resources/app/out/vs/code/electron-sandbox/workbench"
  mkdir -p "$workbench_dir"
  cat > "$workbench_dir/workbench.html" <<HTML
<!DOCTYPE html>
<html>
<body></body>
</html>
HTML

  cat > "$tmp/fake-patch" <<SH
#!/usr/bin/env bash
set -euo pipefail
touch "\$TMP_FIXTURE/patch-called"
cat > "\$CURSOR_WORKBENCH_HTML" <<HTML
<!DOCTYPE html>
<html>
<body></body>
<!-- !! VSCODE-CUSTOM-CSS-START !! -->
<script src="./cursor-markdown-preview-patch.js"></script>
<!-- !! VSCODE-CUSTOM-CSS-END !! -->
</html>
HTML
cat > "\$(dirname "\$CURSOR_WORKBENCH_HTML")/cursor-markdown-preview-patch.js" <<JS
window.cursorMarkdownPreviewFrontmatter = true;
window.cursorMarkdownPreviewHeadingFolds = true;
JS
SH
  chmod +x "$tmp/fake-patch"

  TMP_FIXTURE="$tmp" \
    CURSOR_APP_BUNDLE="$tmp/missing-app/Cursor.app" \
    CURSOR_HOME_APP_BUNDLE="$tmp/missing-home-app/Cursor.app" \
    CURSOR_SHIPIT_DIR="$tmp/shipit" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_CMD="$tmp/fake-patch" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0 \
    CURSOR_MARKDOWN_PREVIEW_PATCH_LOCK_DIR="$tmp/lock" \
    "$1/ensure-patched" >/dev/null
  test -f "$tmp/patch-called"
  grep -q "VSCODE-CUSTOM-CSS-START" "$workbench_dir/workbench.html"
  grep -q "cursorMarkdownPreviewFrontmatter" "$workbench_dir/cursor-markdown-preview-patch.js"
  grep -q "cursorMarkdownPreviewHeadingFolds" "$workbench_dir/cursor-markdown-preview-patch.js"
' _ "$SCRIPT_DIR"

check "ensure-patched real patch fixture" bash -c '
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

  HOME="$tmp/home" \
    CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_WORKBENCH_PATCH_BACKUP_ROOT="$tmp/backups" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0 \
    CURSOR_MARKDOWN_PREVIEW_PATCH_LOCK_DIR="$tmp/lock" \
    "$1/ensure-patched" --font-size 18 >/dev/null

  grep -q -- "--cursor-inline-markdown-editor-font-size: 18px" "$tmp/workbench.html"
  grep -q "cursorMarkdownPreviewFrontmatter" "$tmp/cursor-markdown-preview-patch.js"
  grep -q "cursorMarkdownPreviewHeadingFolds" "$tmp/cursor-markdown-preview-patch.js"
  backup_count=$(find "$tmp/backups" -path "*/workbench.html" -type f | wc -l | tr -d " ")
  [[ "$backup_count" == "1" ]]

  HOME="$tmp/home" \
    CURSOR_WORKBENCH_HTML="$tmp/workbench.html" \
    CURSOR_WORKBENCH_PATCH_BACKUP_ROOT="$tmp/backups" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0 \
    CURSOR_MARKDOWN_PREVIEW_PATCH_LOCK_DIR="$tmp/lock" \
    "$1/ensure-patched" --font-size 20 >/dev/null

  backup_count=$(find "$tmp/backups" -path "*/workbench.html" -type f | wc -l | tr -d " ")
  [[ "$backup_count" == "1" ]]
  grep -q -- "--cursor-inline-markdown-editor-font-size: 18px" "$tmp/workbench.html"
' _ "$SCRIPT_DIR"

check "ensure-patched exits when locked" bash -c '
  set -euo pipefail
  tmp=$(mktemp -d)
  trap "rm -rf \"$tmp\"" EXIT

  mkdir "$tmp/lock"
  cat > "$tmp/fail-if-called" <<SH
#!/usr/bin/env bash
exit 99
SH
  chmod +x "$tmp/fail-if-called"

  CURSOR_WORKBENCH_HTML="$tmp/missing-workbench.html" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_CMD="$tmp/fail-if-called" \
    CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0 \
    CURSOR_MARKDOWN_PREVIEW_PATCH_LOCK_DIR="$tmp/lock" \
    "$1/ensure-patched" >/dev/null
  test -d "$tmp/lock"
' _ "$SCRIPT_DIR"

check "heading folding browser fixture" bash "$SCRIPT_DIR/tests/heading-folding-browser-fixture.sh"

echo
echo "Passed: $PASS"
echo "Failed: $FAIL"

if ((FAIL > 0)); then
  exit 1
fi
