# Cursor editable Markdown preview CSS/JS patch

Cursor's native editable rendered Markdown preview does not currently allow custom styling or frontmatter rendering. This repo is a small unsupported workaround: it patches Cursor's installed app bundle, injects custom CSS into `workbench.html`, and installs a same-origin JavaScript renderer next to `workbench.html`.

It targets Cursor's private `.markdown-editor-react__richtext-content` DOM, which is used by the native `Preview | Markdown` editor surface. The current patch combines CSS typography/layout changes with JavaScript frontmatter detection so leading YAML frontmatter renders as a compact metadata table inspired by GitHub's Markdown preview, and normal Markdown headings can be visually folded from the editable preview.

## Why this matters

Cursor's native `Preview | Markdown` mode is the only editable rendered Markdown preview I have found in Cursor so far, but it does not currently offer a supported API for custom styling or frontmatter-specific behavior.

Other options like Cursor's VS Code-style `Markdown: Open Preview` and popular extensions like `Markdown Preview Enhanced` offer custom styling, but not inline editing - they both require you to edit the file in the raw editor and view rendered Markdown in a separate window.

See [Surfaces tested](#surfaces-tested) for details.

## Usage

Use the repo checkout as-is, then run:

```bash
chmod +x patch rollback ensure-patched install-auto-reapply verify-auto-reapply
./patch
```

On Sid's dotfiles-managed machines, prefer the stable wrapper:

```bash
cursor-inline-markdown-preview-patch
```

To see changes, reload Cursor with `Developer: Reload Window` or restart Cursor.

By default, the script sets the preview base font size to match Cursor's current `editor.fontSize`. Edit `custom.css` for styling changes, edit `custom.js` for frontmatter or heading-folding behavior changes, then re-run `./patch` and reload Cursor.

You can choose how the font-size variable is rendered:

```bash
./patch --font-size editor # default: use Cursor editor.fontSize
./patch --font-size css    # use the value already written in custom.css
./patch --font-size 18     # inject 18px
```

## Auto-reapply after Cursor updates

Cursor updates replace the app bundle and can remove the injected patch. The
repo includes `ensure-patched`, a small idempotent wrapper intended for macOS
`launchd` triggers:

```bash
./ensure-patched
```

`ensure-patched` checks whether the managed markers and JavaScript asset are
already present. If the patch is missing, it runs `./patch`; if the patch is
already present, it exits without creating a new backup. By default it waits 20
seconds before checking so Cursor's updater can finish replacing files; set
`CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0` for immediate manual checks.

For automatic reapply on macOS, use the app-backed per-user LaunchAgent:

```bash
./install-auto-reapply
```

This builds a small local runner app, installs it at:

```text
~/Applications/Cursor Markdown Preview Patch Ensure.app
```

and installs a per-user LaunchAgent at:

```text
~/Library/LaunchAgents/com.sidsethi.cursor-markdown-preview-patch.ensure.plist
```

The LaunchAgent runs the executable inside the runner app bundle, and the runner
executes `./ensure-patched`. This gives macOS a concrete app bundle to grant
App Management permission to. Grant that one-time permission in:

```text
System Settings > Privacy & Security > App Management
```

Enable:

```text
~/Applications/Cursor Markdown Preview Patch Ensure.app
```

If the runner is not listed yet, run `./verify-auto-reapply` once. macOS should
block the runner's first protected write and add it to App Management as a
disabled app; the verifier restores the patch manually before failing. Then
enable the runner and rerun `./verify-auto-reapply`.

Do not rebuild or reinstall the runner after granting App Management unless you
are prepared to re-enable the permission. This local app is ad-hoc signed, so
changing its executable can change the code identity macOS uses for privacy
decisions.

The LaunchAgent watches:

```text
~/Library/Caches/<Cursor bundle id>.ShipIt
/Applications/Cursor.app
```

The example app-backed plist is:

```text
launchd/com.example.cursor-markdown-preview-patch.ensure.plist
```

`./install-auto-reapply` writes the live plist for this machine. To inspect it:

```bash
plutil -p "$HOME/Library/LaunchAgents/com.sidsethi.cursor-markdown-preview-patch.ensure.plist"
launchctl kickstart -k "gui/$(id -u)/com.sidsethi.cursor-markdown-preview-patch.ensure"
launchctl print "gui/$(id -u)/com.sidsethi.cursor-markdown-preview-patch.ensure"
```

The app-backed LaunchAgent runs the runner executable directly, so `launchctl`
shows the runner's exit status. The logs are still the best place to inspect the
patch result:

```text
~/Library/Logs/cursor-markdown-preview-patch/ensure.log
~/Library/Logs/cursor-markdown-preview-patch/ensure.err.log
```

To run the end-to-end acceptance test:

```bash
./verify-auto-reapply
```

That verifier intentionally rolls back the live patch, triggers the LaunchAgent,
waits for the runner to finish, and confirms the managed markers and JavaScript
asset returned. If the LaunchAgent path fails, it restores the patch through the
manual `ensure-patched` path before exiting with failure.

To find Cursor's current bundle id:

```bash
defaults read /Applications/Cursor.app/Contents/Info CFBundleIdentifier
```

See [AUTO-REAPPLY.md](./AUTO-REAPPLY.md) for the design notes, tradeoffs, and
multi-machine considerations.

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
- `ensure-patched`
  - Bash script for launchd or other update triggers.
  - Checks for the managed patch before running `patch`, so it avoids unnecessary backups.
  - Uses a lock and short debounce for duplicate filesystem events during updates.
- `install-auto-reapply`
  - Builds the local runner app and installs the app-backed LaunchAgent.
  - Backs up an existing live plist before replacing it.
- `verify-auto-reapply`
  - End-to-end verifier for the auto-reapply path.
  - Rolls back the live patch, triggers the LaunchAgent, verifies restoration,
    and restores manually on failure.
- `runner/`
  - Swift source for the local app that runs `ensure-patched`.
- `launchd/`
  - Example app-backed per-user LaunchAgent plist for macOS auto-reapply.
- `custom.css`
  - CSS source for Cursor's editable rendered Markdown preview, rendered frontmatter table, and heading-folding controls.
- `custom.js`
  - JavaScript source that recognizes leading YAML frontmatter in Cursor's rendered Markdown DOM, replaces the raw render with a compact metadata table, and adds visual heading folding in the editable Markdown preview.
- `test.sh`
  - Fixture smoke tests for the patch and rollback scripts.

## Caveats

- This is not a supported Cursor API.
- Cursor may show this or a similar message: `Your Cursor installation appears to be corrupt. Please reinstall.` This warning is expected because the patch modifies a sealed app-bundle resource.
- Cursor updates may overwrite the patch. Re-running the script will re-apply the patch.
- Private selectors may change on any Cursor update.
- macOS requires App Management permission for the app that writes into another
  app bundle. For auto-reapply, grant it to the local runner app installed by
  `./install-auto-reapply`.
- The LaunchAgent auto-reapply flow is macOS-specific and still modifies
  Cursor's unsupported app-bundle internals.
- The frontmatter renderer is intentionally conservative: JavaScript detects and inserts the display table, while CSS does the visual folding of Cursor's raw frontmatter render.
- Heading folding is also intentionally conservative: generated controls and generated styles live outside Cursor's editable ProseMirror subtree. The current implementation provides in-preview controls only; it does not add real Command Palette commands.

## How it works

The script inserts a managed block before `</html>` in Cursor's workbench file:

```html
<!-- !! VSCODE-CUSTOM-CSS-SESSION-ID ... !! -->
<!-- !! VSCODE-CUSTOM-CSS-START !! -->
<style>
...
</style>
<script src="./cursor-markdown-preview-patch.js?v=YYYYMMDD-HHMMSS"></script>
<!-- !! VSCODE-CUSTOM-CSS-END !! -->
```

The script removes any previous managed block before writing a new one, so it is safe to rerun after editing `custom.css`, editing `custom.js`, or after Cursor updates. The query string is a cache buster so an existing Cursor renderer reloads the current JS asset after a live reapply.

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

### Heading folding

`custom.js` also watches headings in Cursor's native editable Markdown preview.
For each direct heading child inside the editable ProseMirror document, it
derives the section range from that heading to the next heading of the same or
shallower level. The level resolver prefers real heading semantics, then falls
back to common rich-text level hints and computed heading size if Cursor changes
the rendered DOM shape.

The fold model is visual-only and session-local:

- It stores fold state in memory for the current preview container.
- It adds generated fold controls outside `.tiptap.ProseMirror`.
- It writes generated CSS outside `.tiptap.ProseMirror`.
- It does not wrap, reorder, add classes to, or add inline styles to ProseMirror
  document children.

In the preview, hover a heading to reveal its left-gutter marker, then click the
marker to fold or unfold that section. The marker is positioned outside the
normal text column, so headings do not shift horizontally when controls appear.
Only headings with content get a fold marker or participate in bulk fold
actions. Empty heading sections are left unmarked, and collapsed non-empty
headings keep their `+` marker visible as a lightweight indicator that hidden
content exists.

The injected toolbar supports:

- `Fold all`
- `Unfold all`
- `Fold to current`
- `Unfold current`
- `Fold to H2`
- `Fold to H3`
- `Fold to H4`

When Cursor exposes the surrounding `Preview | Markdown` mode-toggle host, the
toolbar is promoted just above the preview scroll container so it remains
available while scrolling through a long Markdown file. If that host shape is
not detected, the toolbar falls back to the original generated-control host with
sticky positioning. In both cases it stays outside `.tiptap.ProseMirror`.

`Fold to current` uses the active caret or selection to find the nearest parent
heading section, then folds peer and descendant headings at that heading level
while keeping the current section open. Other bulk folding actions also skip any
section that contains the active selection, so the caret is not stranded in
hidden content. `Unfold current` uses the same current-heading lookup, then
unfolds that heading and every descendant heading inside it without unfolding
peer sections.

A real Command Palette integration is deliberately deferred because the current
`custom.js` injection does not have a proven low-risk command registration bridge
into Cursor's workbench.

If the toolbar does not appear in an already-open Cursor window after reapplying
the patch, open the Markdown file in a fresh Cursor window or fully restart
Cursor. The injected script URL includes a timestamp query string to avoid stale
renderer cache, but an existing workbench window can still keep old runtime
state until it is actually restarted.

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

Verification was last run locally against this checkout on 2026-05-26:

- `./test.sh`: 21 passed, 0 failed
- `./verify-auto-reapply`: passed
- `shellcheck patch rollback ensure-patched install-auto-reapply verify-auto-reapply test.sh`: passed
- `swiftc -parse runner/CursorMarkdownPreviewPatchEnsure.swift`: passed

Additional heading-folding verification was run on 2026-06-02:

- `./test.sh`: 24 passed, 0 failed
- `./patch`: applied to the live Cursor app bundle
- Live bundle marker check: `cursorMarkdownPreviewHeadingFolds`,
  `cursor-md-heading-fold`, `Fold to H2`, and
  `cursorMarkdownPreviewFrontmatter` present in the installed workbench asset
- Computer Use live UI check:
  - opened a temporary Markdown file in a separate Cursor window
  - switched to native `Preview | Markdown`
  - confirmed the `Fold all`, `Unfold all`, `Fold to H2`, `Fold to H3`, and
    `Fold to H4` toolbar rendered
  - confirmed `Fold all`, `Unfold all`, `Fold to H2`, `Fold to H3`, and
    direct heading-gutter toggles changed visible preview sections correctly
- Live backup from that apply:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260602-122651/workbench.html`

The 2026-06-02 live run did not run `./rollback` or
`./verify-auto-reapply`. Cursor displayed its standard corrupt-installation
warning after the app-bundle modification.

Follow-up verification on 2026-06-02 found that an already-open workspace
preview did not show the toolbar even though a fresh file window did. The fix
expanded detection to fallback `.tiptap.ProseMirror` preview roots, added a
timestamp query string to the injected script URL, and added a browser fixture
for that fallback shape.

- `./test.sh`: 24 passed, 0 failed
- Live bundle marker check: installed `workbench.html` used
  `cursor-markdown-preview-patch.js?v=20260602-131005`
- Computer Use live UI check:
  - reopened `REDDIT-BOOKMARK-INGESTION-DESIGN.md` in a fresh Cursor window
  - confirmed the heading-fold toolbar rendered
  - confirmed `Fold all`, `Unfold all`, and heading markers changed visible
    preview sections correctly
- Live backup from that apply:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260602-131005/workbench.html`

Heading-folding UI polish verification was run later on 2026-06-02:

- `node --check custom.js`: passed
- `bash tests/heading-folding-browser-fixture.sh`: passed
- `./test.sh`: 24 passed, 0 failed
- `git diff --check`: passed
- `./patch`: applied to the live Cursor app bundle
- Browser fixture coverage includes:
  - gutter marker CSS does not inject generated padding into per-heading rules
  - direct heading-gutter clicks survive rerender when generated marker text
    appears in `innerText`
  - same-tag heading DOM with misleading `aria-level` values still resolves
    nested visual heading levels
  - `Fold to current` keeps the active section open while folding peer sections
- Computer Use live UI check:
  - opened `README.md` in Cursor's native `Preview | Markdown` surface
  - confirmed heading text alignment did not shift when the gutter marker
    appeared
  - confirmed the gutter marker is hidden until heading hover/focus
  - confirmed H1 and H2 gutter toggles changed visible preview sections
    correctly
  - confirmed `Fold to current` used the active `Usage` section and folded peer
    H2 sections while keeping `Usage` open
- Live backup from that apply:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260602-133910/workbench.html`

Pinned toolbar verification was run later on 2026-06-02:

- `node --check custom.js`: passed
- `bash tests/heading-folding-browser-fixture.sh`: passed
- `./test.sh`: 24 passed, 0 failed
- `git diff --check`: passed
- `./patch`: applied to the live Cursor app bundle
- Browser fixture coverage includes:
  - the toolbar computes as sticky in the fallback generated-control host
  - the toolbar is promoted below Cursor's `Preview` and `Markdown` controls
    when that non-scrolling mode-toggle host is detectable
  - the promoted toolbar stays outside the preview scroll host and outside
    `.tiptap.ProseMirror`
- Computer Use live UI check:
  - reloaded the existing Cursor window instead of opening a new one
  - scrolled `REDDIT-BOOKMARK-INGESTION-DESIGN.md` in Cursor's native
    `Preview | Markdown` surface
  - confirmed the fold toolbar remained visible while the document body
    scrolled underneath it
- Live backup from that apply:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260602-142509/workbench.html`

`Unfold current` and empty-heading verification was run later on 2026-06-02:

- `node --check custom.js`: passed
- `bash tests/heading-folding-browser-fixture.sh`: passed
- `./test.sh`: 24 passed, 0 failed
- `git diff --check`: passed
- `./patch`: applied to the live Cursor app bundle
- Browser fixture coverage includes:
  - `Unfold current` reopens the current heading section and descendant
    headings without reopening peer sections
  - empty heading sections do not receive generated marker rules
  - bulk fold actions ignore empty heading sections
  - collapsed non-empty headings keep a visible `+` marker
- Computer Use live UI check:
  - reloaded and reused the existing Cursor window instead of opening a new one
  - created a temporary Markdown file with an empty H2, contentful H2 siblings,
    and a nested H3
  - confirmed `Fold to H2` left the empty H2 unmarked while collapsed
    contentful H2 sections showed persistent `+` markers
  - confirmed clicking the empty H2 gutter did not toggle any fold state
  - confirmed `Unfold current` reopened a folded contentful section and its
    nested H3 while leaving the trailing sibling folded
  - confirmed selecting the parent H1 intro area and running `Unfold current`
    reopened all descendant headings under that H1
  - removed the temporary Markdown file after the live check
- Live backup from that apply:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260602-144146/workbench.html`

A previous local app-bundle selector preflight was run on 2026-05-21. The live
Cursor app was not modified during that preflight:

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
