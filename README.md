# Cursor editable Markdown preview patch

Cursor's native editable rendered Markdown preview does not currently allow custom styling or frontmatter rendering. This repo is a small unsupported workaround: it patches Cursor's installed app bundle, injects custom CSS into `workbench.html`, and installs a same-origin JavaScript asset next to `workbench.html`.

It targets Cursor's private `.markdown-editor-react__richtext-content` DOM, which is used by the native `Preview | Markdown` editor surface. The current patch keeps typography customizable and renders leading YAML frontmatter as a compact metadata table inspired by GitHub's Markdown preview.

## Why this matters

Cursor's native `Preview | Markdown` mode is the only editable rendered Markdown preview I have found in Cursor so far, but it does not currently offer a supported API for custom styling or frontmatter-specific rendering.

Other options like Cursor's VS Code-style `Markdown: Open Preview` and popular extensions like `Markdown Preview Enhanced` offer custom styling, but not inline editing - they both require you to edit the file in the raw editor and view rendered Markdown in a separate window.

See [Surfaces tested](#surfaces-tested) for details.

## Usage

Use the repo checkout as-is, then run:

```bash
chmod +x patch rollback
./patch
```

On Sid's dotfiles-managed machines, prefer the stable wrapper:

```bash
cursor-inline-markdown-preview-patch
```

To see changes, reload Cursor with `Developer: Reload Window` or restart Cursor.

By default, the script sets the preview base font size to match Cursor's current `editor.fontSize`. Edit `custom.css` for styling changes, edit `custom.js` for frontmatter detection/rendering changes, then re-run `./patch` and reload Cursor.

You can choose how the font-size variable is rendered:

```bash
./patch --font-size editor # default: use Cursor editor.fontSize
./patch --font-size css    # use the value already written in custom.css
./patch --font-size 18     # inject 18px
```

To restore the previous backed-up workbench:

```bash
./rollback
```

On Sid's dotfiles-managed machines, prefer the stable rollback wrapper:

```bash
cursor-inline-markdown-preview-rollback
```

## Files

- `patch`
  - Bash script that backs up and patches Cursor's `workbench.html`.
  - Reads Cursor's `editor.fontSize` and renders the CSS with that value.
  - Installs `custom.js` as `cursor-markdown-preview-patch.js` next to Cursor's `workbench.html`, because Cursor's CSP blocks inline scripts.
  - Can be re-run to apply changes.
- `rollback`
  - Bash script that restores the latest clean backup created by the patch script.
  - Can also restore a specific `workbench.html` backup path.
  - Removes the managed JavaScript asset when restoring a workbench that no longer references it.
- `custom.css`
  - CSS source for Cursor's editable rendered Markdown preview and rendered frontmatter table.
- `custom.js`
  - JavaScript source that recognizes leading YAML frontmatter in Cursor's rendered Markdown DOM and replaces the raw render with a compact metadata table.
- `test.sh`
  - Fixture smoke tests for the patch and rollback scripts.

## Caveats

- This is not a supported Cursor API.
- Cursor may show this or a similar message: `Your Cursor installation appears to be corrupt. Please reinstall.` This warning is expected because the patch modifies a sealed app-bundle resource.
- Cursor updates may overwrite the patch. Re-running the script will re-apply the patch.
- Private selectors may change on any Cursor update.
- macOS may require App Management permission for the terminal app running the patch.
- The frontmatter renderer is intentionally conservative: JavaScript detects and inserts the display table, while CSS does the visual folding of Cursor's raw frontmatter render.

## How it works

The script inserts a managed block before `</html>` in Cursor's workbench file:

```html
<!-- !! VSCODE-CUSTOM-CSS-SESSION-ID ... !! -->
<!-- !! VSCODE-CUSTOM-CSS-START !! -->
<style>
...
</style>
<script src="./cursor-markdown-preview-patch.js"></script>
<!-- !! VSCODE-CUSTOM-CSS-END !! -->
```

The script removes any previous managed block before writing a new one, so it is safe to rerun after editing the CSS or after Cursor updates.

`custom.css` stays valid CSS. Instead of using invalid template tokens, `patch` can rewrite this custom property in the temporary injected copy:

```css
--cursor-inline-markdown-editor-font-size: 13px;
```

The value in `custom.css` is used directly when running `./patch --font-size css`. Otherwise, the injected value is read from Cursor's user setting or from an explicit numeric `--font-size` value:

```json
"editor.fontSize": 13
```

This is a snapshot at patch time. It does not live-update if you later change `editor.fontSize` or `custom.css`. Rerun `./patch` and reload Cursor.

### Frontmatter rendering

`custom.js` watches Cursor's editable Markdown preview for the rendered shape of
leading YAML frontmatter. When it sees a document begin with a `---` block, it
hides Cursor's raw rendered nodes and inserts a compact table inspired by
GitHub's Markdown frontmatter preview.

For example:

```yaml
---
name: skill-author
description: Create or update Codex and Agent Skills.
metadata:
  short-description: Create and refine local skills
---
```

renders as rows for `name`, `description`, and
`metadata.short-description`. The replacement table is `contenteditable=false`
so normal document editing stays focused on the Markdown body.

## Rollback and backups

Every run creates a timestamped backup and prints the rollback command. Backup
directory names are made unique even when the patch is run multiple times in the
same second.

`./rollback` restores the newest clean backup created by `./patch`, skipping
backups that already contain the managed patch block. To restore a specific
backup, pass that backup path explicitly.

Default backup root:

```text
~/Library/Application Support/Cursor/workbench-patch-backups
```

Override it if desired:

```bash
CURSOR_WORKBENCH_PATCH_BACKUP_ROOT="$HOME/somewhere/cursor-backups" ./patch
```

Restore the latest clean backup:

```bash
./rollback
```

Restore a specific backup:

```bash
./rollback "$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-YYYYMMDD-HHMMSS/workbench.html"
```

The rollback script uses the same `CURSOR_WORKBENCH_PATCH_BACKUP_ROOT` override.

## Archive

Read-only historical notes:

- [2026-05-14 frontmatter rendering postmortem](./ARCHIVE-2026-05-14-frontmatter-rendering-postmortem.md)

## Verification and version support

Fixture tests were last run locally against this checkout on 2026-05-21:

- `./test.sh`: 11 passed, 0 failed

The live Cursor app was not modified during that preflight. The local app bundle
was checked for the private selectors this patch depends on:

- Cursor Version: 3.4.20
- `markdown-editor-react__richtext-content`: present in bundled CSS and JS
- `contentClassName:"markdown-editor-react__richtext-content"`: present in bundled JS
- `editable:!0`: present in bundled JS

The original runtime validation for this patch was performed on:

- Version: 3.3.16 (Universal)
- VSCode Version: 1.105.1
- Commit: 7f0f522221d0ba220e4edb766bb3c47c08c14ab0
- Layout: editor
- Build Type: Stable
- Release Track: Default
- Platform: Darwin arm64 25.2.0

## Appendix

### Surfaces tested

The alternatives I tested did not cover the same workflow:

- `Markdown: Open Preview` / `Markdown: Open Preview to the Side`
  - VS Code-style Markdown preview webview.
  - Supports `markdown.styles` / `markdown.preview.*`.
  - Customizable through supported settings, but not editable inline.
- Cursor native `Preview | Markdown`
  - Main workbench DOM.
  - Editable rendered Markdown behavior.
  - Best checkbox/editing behavior I found.
  - No supported CSS setting found.
- Markdown Preview Enhanced
  - Has its own CSS pipeline.
  - CSS works there.
  - Did not replace Cursor native editable rendered Markdown behavior in my testing.
- Markdown All in One
  - Affects/improves the side preview.
  - Did not make the side preview directly editable.
  - Did not affect Cursor native `Preview | Markdown`.

### Inspecting Cursor internals

These are local app-bundle files, not public API:

```text
/Applications/Cursor.app/Contents/Resources/app/out/vs/code/electron-sandbox/workbench/workbench.html
/Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.css
/Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js
```

Useful searches:

```bash
rg -n "markdown-editor-react|richtext-content|markdownEditor" \
  /Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.css \
  /Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js
```

Relevant CSS snippet observed in Cursor `3.3.16`:

```css
.markdown-editor-react {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
  width: 100%;
}

.markdown-editor-react__content {
  display: flex;
  flex: 1;
  flex-direction: column;
  overflow: hidden;
}

.markdown-editor-react__scroll-area-wrapper {
  cursor: text;
  display: flex;
  flex: 1;
  flex-direction: column;
  min-height: 0;
}

.markdown-editor-react__scroll-area {
  flex: 1;
  height: 100%;
}

.markdown-editor-react__richtext-content {
  --markdown-editor-content-padding: 32px 16px 64px;
  margin: 0 auto;
  max-width: 800px;
  padding: var(--markdown-editor-content-padding);
}
```

Relevant JS snippet observed in Cursor `3.3.16`, reformatted from the minified workbench bundle:

```js
K(tEr, {
  className: "markdown-editor-react__richtext",
  contentClassName: "markdown-editor-react__richtext-content",
  debounceMs: 100,
  editable: !0,
  initialMarkdown: n,
  onMarkdownChange: W,
  placeholder: "Start writing...",
  plugins: J,
  ref: S,
  variant: "document"
})
```

The key detail is `editable: !0`. This is why I think of Cursor's native `Preview | Markdown` surface as an editable rendered Markdown preview, not just a normal read-only Markdown preview.

The default CSS above also shows why changing only `markdown.styles` is not enough: this surface is in the main workbench DOM, not the VS Code-style Markdown preview webview.
