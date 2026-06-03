#!/usr/bin/env bash
#
# Shared constants and read-only helpers for the Cursor Markdown preview patch.
#
# shellcheck disable=SC2034
# Constants in this file are consumed by scripts that source it.

readonly CURSOR_PATCH_ROOT="${CURSOR_PATCH_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
readonly CURSOR_PATCH_PREVIEW_DIR="$CURSOR_PATCH_ROOT/preview"
readonly CURSOR_PATCH_CSS_TEMPLATE="$CURSOR_PATCH_PREVIEW_DIR/custom.css"
readonly CURSOR_PATCH_JS_TEMPLATE="$CURSOR_PATCH_PREVIEW_DIR/custom.js"

readonly CURSOR_PATCH_JS_OUTPUT_NAME="cursor-markdown-preview-patch.js"
readonly CURSOR_PATCH_DEFAULT_EDITOR_FONT_SIZE="13"
readonly CURSOR_PATCH_CSS_FONT_SIZE_PROPERTY="--cursor-inline-markdown-editor-font-size"
readonly CURSOR_PATCH_JS_VERIFY_TOKEN_FRONTMATTER="cursorMarkdownPreviewFrontmatter"
readonly CURSOR_PATCH_JS_VERIFY_TOKEN_HEADING_FOLDS="cursorMarkdownPreviewHeadingFolds"
readonly CURSOR_PATCH_START_MARKER="<!-- !! VSCODE-CUSTOM-CSS-START !! -->"
readonly CURSOR_PATCH_END_MARKER="<!-- !! VSCODE-CUSTOM-CSS-END !! -->"
readonly CURSOR_PATCH_SESSION_MARKER_PREFIX="<!-- !! VSCODE-CUSTOM-CSS-SESSION-ID"
readonly -a CURSOR_PATCH_TRUSTED_TYPES_POLICY_NAMES=(
  "streamingMarkdownPolicy"
  "mermaidDiagram2"
  "mermaidDiagramOuter"
)

cursor_patch_is_number() {
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

cursor_patch_cursor_bundle_id() {
  local app_bundle="${1:-${CURSOR_APP_BUNDLE:-/Applications/Cursor.app}}"
  local bundle_id

  [[ -d "$app_bundle" ]] || return 1
  command -v defaults >/dev/null 2>&1 || return 1

  bundle_id="$(defaults read "$app_bundle/Contents/Info" CFBundleIdentifier 2>/dev/null || true)"
  [[ -n "$bundle_id" ]] || return 1
  printf '%s\n' "$bundle_id"
}

cursor_patch_find_app_workbench_htmls() {
  local app_bundle path
  local app_bundles=(
    "${CURSOR_APP_BUNDLE:-/Applications/Cursor.app}"
    "${CURSOR_HOME_APP_BUNDLE:-$HOME/Applications/Cursor.app}"
  )

  for app_bundle in "${app_bundles[@]}"; do
    local candidates=(
      "$app_bundle/Contents/Resources/app/out/vs/code/electron-sandbox/workbench/workbench.html"
      "$app_bundle/Contents/Resources/app/out/vs/code/electron-browser/workbench/workbench.html"
    )

    for path in "${candidates[@]}"; do
      if [[ -f "$path" ]]; then
        printf '%s\n' "$path"
      fi
    done
  done
}

cursor_patch_find_shipit_workbench_htmls() {
  local shipit_dir="${CURSOR_SHIPIT_DIR:-}"

  if [[ -z "$shipit_dir" ]]; then
    local bundle_id
    bundle_id="$(cursor_patch_cursor_bundle_id || true)"
    [[ -n "$bundle_id" ]] || return 0
    shipit_dir="$HOME/Library/Caches/$bundle_id.ShipIt"
  fi

  [[ -d "$shipit_dir" ]] || return 0

  find "$shipit_dir" \
    -path '*/Cursor.app/Contents/Resources/app/out/vs/code/*/workbench/workbench.html' \
    -type f 2>/dev/null | sort
}

cursor_patch_find_primary_workbench_html() {
  local workbench_html

  if [[ -n "${CURSOR_WORKBENCH_HTML:-}" ]]; then
    [[ -f "$CURSOR_WORKBENCH_HTML" ]] || return 1
    printf '%s\n' "$CURSOR_WORKBENCH_HTML"
    return 0
  fi

  while IFS= read -r workbench_html; do
    printf '%s\n' "$workbench_html"
    return 0
  done < <(cursor_patch_find_app_workbench_htmls)

  return 1
}

cursor_patch_find_workbench_htmls() {
  if [[ -n "${CURSOR_WORKBENCH_HTML:-}" ]]; then
    [[ -f "$CURSOR_WORKBENCH_HTML" ]] || return 1
    printf '%s\n' "$CURSOR_WORKBENCH_HTML"
    return 0
  fi

  {
    cursor_patch_find_shipit_workbench_htmls
    cursor_patch_find_app_workbench_htmls
  } | awk '!seen[$0]++'
}

cursor_patch_managed_js_path() {
  local workbench_html="$1"
  printf '%s\n' "$(dirname "$workbench_html")/$CURSOR_PATCH_JS_OUTPUT_NAME"
}

cursor_patch_has_trusted_types_repairs() {
  local workbench_html="$1"
  local policy

  if ! grep -qF "trusted-types" "$workbench_html"; then
    return 0
  fi

  for policy in "${CURSOR_PATCH_TRUSTED_TYPES_POLICY_NAMES[@]}"; do
    grep -qF -- "$policy" "$workbench_html" || return 1
  done
}

cursor_patch_is_present() {
  local workbench_html="$1"
  local managed_js
  managed_js="$(cursor_patch_managed_js_path "$workbench_html")"

  [[ -f "$workbench_html" ]] &&
    grep -qF "$CURSOR_PATCH_START_MARKER" "$workbench_html" &&
    grep -qF "$CURSOR_PATCH_END_MARKER" "$workbench_html" &&
    grep -qF "$CURSOR_PATCH_JS_OUTPUT_NAME" "$workbench_html" &&
    [[ -f "$managed_js" ]] &&
    grep -qF "$CURSOR_PATCH_JS_VERIFY_TOKEN_FRONTMATTER" "$managed_js" &&
    grep -qF "$CURSOR_PATCH_JS_VERIFY_TOKEN_HEADING_FOLDS" "$managed_js" &&
    cursor_patch_has_trusted_types_repairs "$workbench_html"
}

cursor_patch_is_verified() {
  local workbench_html="$1"

  cursor_patch_is_present "$workbench_html" &&
    grep -qF -- "$CURSOR_PATCH_CSS_FONT_SIZE_PROPERTY" "$workbench_html"
}

cursor_patch_repair_trusted_types_policies() {
  local source_html="$1"
  local repaired_html="$2"
  local policies
  policies="$(printf '%s\n' "${CURSOR_PATCH_TRUSTED_TYPES_POLICY_NAMES[@]}")"

  PATCH_TRUSTED_TYPES_POLICIES="$policies" perl -0pe '
    @policies = grep { length } split /\n/, $ENV{"PATCH_TRUSTED_TYPES_POLICIES"};
    s/(\n\s*trusted-types\s+)(.*?)(\n\s*;\s*)/
      my ($prefix, $body, $suffix) = ($1, $2, $3);
      for my $policy (@policies) {
        if ($body !~ m{(^|\s)\Q$policy\E(?=\s|$)}) {
          $body .= "\n\t\t\t\t\t$policy";
        }
      }
      "$prefix$body$suffix";
    /egs;
  ' "$source_html" > "$repaired_html"
}

cursor_patch_is_clean_backup() {
  local backup_path="$1"

  ! grep -qF "$CURSOR_PATCH_JS_OUTPUT_NAME" "$backup_path" &&
    ! grep -qF "VSCODE-CUSTOM-CSS-START" "$backup_path"
}
