# Cursor editable Markdown preview CSS/JS patch

Cursor's native editable rendered Markdown preview does not currently allow custom styling, frontmatter rendering, or heading folding. This repo is a small unsupported workaround: it patches Cursor's installed app bundle, injects custom CSS into `workbench.html`, and installs a same-origin JavaScript renderer next to `workbench.html`.

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

By default, the script sets the preview base font size to match Cursor's current
`editor.fontSize`. Edit `preview/custom.css` for styling changes, edit
`preview/custom.js` for frontmatter or heading-folding behavior changes, then
re-run `./patch` and reload Cursor.

You can choose how the font-size variable is rendered:

```bash
./patch --font-size editor # default: use Cursor editor.fontSize
./patch --font-size css    # use the value already written in preview/custom.css
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
auto-reapply/launchd/com.example.cursor-markdown-preview-patch.ensure.plist
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

See [docs/auto-reapply.md](./docs/auto-reapply.md) for the design notes,
tradeoffs, and multi-machine considerations.

To restore the previous backed-up workbench:

```bash
./rollback
```

On Sid's dotfiles-managed machines, prefer the stable rollback wrapper:

```bash
cursor-inline-markdown-preview-rollback
```

## Architecture

The repo has four small subsystems:

- Root scripts are the public command surface: `patch`, `rollback`,
  `ensure-patched`, `install-auto-reapply`, `verify-auto-reapply`, and
  `test.sh`.
- `preview/` is the injected preview customization/runtime. These files define
  the CSS and JavaScript behavior installed into Cursor's workbench.
- `lib/` is shared patch-system mechanics: constants, workbench discovery,
  managed asset paths, Trusted Types policy checks, and patch-present
  verification.
- `auto-reapply/` contains macOS support assets used by the root auto-reapply
  commands.

## Files

- `patch`
  - Bash script that backs up and patches Cursor's `workbench.html`.
  - Reads Cursor's `editor.fontSize` and renders `preview/custom.css` with that
    value.
  - Installs `preview/custom.js` as `cursor-markdown-preview-patch.js` next to
    Cursor's `workbench.html`, because Cursor's CSP blocks inline scripts.
  - Repairs known Cursor Trusted Types policy names in stale clean workbench bases before injecting, then verifies them when a `trusted-types` CSP is present.
  - Can be re-run to apply changes.
- `rollback`
  - Bash script that restores the latest clean backup created by the patch script.
  - Can also restore a specific `workbench.html` backup path.
  - Removes the managed JavaScript asset when restoring a workbench that no longer references it.
- `ensure-patched`
  - Bash script for launchd or other update triggers.
  - Checks for the managed patch, JS feature tokens, and repaired Trusted Types policies before running `patch`, so it avoids unnecessary backups.
  - Uses a lock and short debounce for duplicate filesystem events during updates.
- `install-auto-reapply`
  - Builds the local runner app and installs the app-backed LaunchAgent.
  - Backs up an existing live plist before replacing it.
- `verify-auto-reapply`
  - End-to-end verifier for the auto-reapply path.
  - Rolls back the live patch, triggers the LaunchAgent, verifies restoration,
    and restores manually on failure.
  - Verifies managed markers, JS feature tokens, and repaired Trusted Types policies after the LaunchAgent run.
  - Uses the same app-bundle workbench path candidates as the patch script.
- `lib/`
  - Shared patch-system constants and read-only helpers for Cursor workbench
    discovery, managed asset paths, Trusted Types policy checks, and
    patch-presence verification.
- `preview/custom.css`
  - CSS source for Cursor's editable rendered Markdown preview, rendered frontmatter table, and heading-folding controls.
- `preview/custom.js`
  - JavaScript source that recognizes leading YAML frontmatter in Cursor's rendered Markdown DOM, replaces the raw render with a compact metadata table, and adds visual heading folding in the editable Markdown preview.
- `auto-reapply/runner/`
  - Swift source for the local app that runs `ensure-patched`.
- `auto-reapply/launchd/`
  - Example app-backed per-user LaunchAgent plist for macOS auto-reapply.
- `docs/`
  - Auto-reapply runbook, live heading-folding test note, heading gutter label
    mockup, and historical archive notes.
- `tests/`
  - Browser fixture coverage for the injected frontmatter and heading-folding
    runtime.
- `test.sh`
  - Fixture smoke tests for the patch, rollback, ensure, and browser-runtime
    paths.

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

The script removes any previous managed block before writing a new one, so it is
safe to rerun after editing `preview/custom.css`, editing `preview/custom.js`, or
after Cursor updates. The query string is a cache buster so an existing Cursor
renderer reloads the current JS asset after a live reapply.

Before injection, `patch` also repairs the current known Cursor Trusted Types policy names in the workbench CSP if the base `workbench.html` has a `trusted-types` directive. This protects against a stale clean backup being restored after Cursor's JavaScript bundle has started using newer policy names.

`preview/custom.css` stays valid CSS. Instead of using invalid template tokens,
`patch` can rewrite this custom property in the temporary injected copy:

```css
--cursor-inline-markdown-editor-font-size: 13px;
```

The value in `preview/custom.css` is used directly when running
`./patch --font-size css`. Otherwise, the injected value is read from Cursor's
user setting or from an explicit numeric `--font-size` value:

```json
"editor.fontSize": 13
```

This is a snapshot at patch time. It does not live-update if you later change
`editor.fontSize` or `preview/custom.css`. Rerun `./patch` and reload Cursor.

### Frontmatter rendering

`preview/custom.js` watches Cursor's editable Markdown preview for the rendered
shape of leading YAML frontmatter. When it sees a document begin with a `---`
block, it hides Cursor's raw rendered nodes and inserts a compact table inspired
by GitHub's Markdown frontmatter preview.

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

`preview/custom.js` also watches headings in Cursor's native editable Markdown
preview. For each direct heading child inside the editable ProseMirror document,
it derives the section range from that heading to the next heading of the same
or shallower level. The level resolver prefers real heading semantics, then
falls back to common rich-text level hints and computed heading size if Cursor
changes the rendered DOM shape.

The fold model is visual-only and session-local:

- It stores fold state in memory for the current preview container.
- It adds generated fold controls outside `.tiptap.ProseMirror`.
- It writes generated CSS outside `.tiptap.ProseMirror`.
- It does not wrap, reorder, add classes to, or add inline styles to ProseMirror
  document children.

In the preview, headings show an always-visible left-gutter level label such as
`H1`, `H2`, or `H3`. The label uses the heading's resolved level and inherits
the heading's typography with reduced contrast, so it reads as structure rather
than document content. It is positioned outside the normal text column, so
heading text does not shift horizontally.

Headings with content also get a smaller fold marker in the same gutter. Hover a
heading to reveal its `-` marker, then click the gutter to fold or unfold that
section. Empty heading sections get the level label but no fold marker and do
not participate in bulk fold actions. Collapsed non-empty headings keep their
`+` marker visible as a lightweight indicator that hidden content exists.

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
`preview/custom.js` injection does not have a proven low-risk command
registration bridge into Cursor's workbench.

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

- [2026-05-14 frontmatter rendering postmortem](./docs/archive/frontmatter-rendering-postmortem-2026-05-14.md)
- [2026-06-02 heading-folding implementation plan](./docs/archive/heading-folding-plan-2026-06-02.md)

## Verification and version support

Current heading gutter label verification was run on 2026-06-03:

- `bash -n lib/cursor-patch-common.sh patch rollback ensure-patched install-auto-reapply verify-auto-reapply test.sh tests/heading-folding-browser-fixture.sh`: passed
- `node --check preview/custom.js`: passed
- `bash tests/heading-folding-browser-fixture.sh`: passed
- `./test.sh`: 27 passed, 0 failed
- `shellcheck lib/cursor-patch-common.sh patch rollback ensure-patched install-auto-reapply verify-auto-reapply test.sh tests/heading-folding-browser-fixture.sh`: passed
- `git diff --check`: passed
- Browser fixture coverage includes:
  - always-visible generated `H1`/`H2`/`H3` gutter labels
  - fold marker hit areas span the label-marker gutter gap
  - label-marker gutter gap clicks still toggle foldable sections
  - wide heading-label gutter clicks still toggle foldable sections
  - empty headings get level labels but no fold marker or fold action
  - single non-foldable headings get level labels without creating a toolbar
- `./patch`: applied to the live Cursor app bundle after fixture verification
- Live bundle marker check: installed `workbench.html` used
  `cursor-markdown-preview-patch.js?v=20260603-110310`, and installed assets
  contained the heading-label token, flex fold marker, and widened gutter
  hit-test
- Live backup from that apply:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260603-110310/workbench.html`
- This run did not run `./rollback` or `./verify-auto-reapply`.

Baseline auto-reapply verification was run locally against this checkout on 2026-05-26:

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

Review follow-up hardening verification was run later on 2026-06-02:

- `node --check custom.js`: passed
- `bash -n patch rollback ensure-patched install-auto-reapply verify-auto-reapply test.sh tests/heading-folding-browser-fixture.sh`: passed
- `shellcheck patch rollback ensure-patched install-auto-reapply verify-auto-reapply test.sh tests/heading-folding-browser-fixture.sh`: passed
- `./test.sh`: 24 passed, 0 failed
- `git diff --check`: passed
- This run used fixture validation only. It did not run `./patch`,
  `./rollback`, or `./verify-auto-reapply` against the live Cursor app bundle.

Live review follow-up hardening verification was run later on 2026-06-02 against
the working tree based on commit
`2a8e51e69ac2d32cf0d4fb158633e75cfcb03d03`:

- `./test.sh`: 25 passed, 0 failed
- `node --check custom.js`: passed
- `bash -n patch rollback ensure-patched install-auto-reapply verify-auto-reapply test.sh tests/heading-folding-browser-fixture.sh`: passed
- `shellcheck patch rollback ensure-patched install-auto-reapply verify-auto-reapply test.sh tests/heading-folding-browser-fixture.sh`: passed
- `git diff --check`: passed
- `./patch`: applied to the live Cursor app bundle
- `./verify-auto-reapply`: passed against the live LaunchAgent
  - rolled back the live patch
  - triggered `com.sidsethi.cursor-markdown-preview-patch.ensure`
  - LaunchAgent runs advanced from `51` to `54`
  - LaunchAgent state returned to `not running`
  - LaunchAgent last exit was `0`
  - final live script tag used `cursor-markdown-preview-patch.js?v=20260602-164526`
- Live bundle checks:
  - installed JS contained `cursorMarkdownPreviewFrontmatter`,
    `cursorMarkdownPreviewHeadingFolds`, `selectionSectionKeysByContainer`, and
    `cleanupDetachedHeadingFoldContainers`
  - workbench CSP contained `streamingMarkdownPolicy`, `mermaidDiagram2`, and
    `mermaidDiagramOuter`
- Computer Use live UI checks:
  - Cursor opened successfully after the Trusted Types repair
  - the native `Preview | Markdown` fold toolbar rendered
  - clicking an H1 gutter while the caret was in that H1's intro paragraph kept
    the section open
  - clicking the H1 gutter while selection was in the heading still folded the
    section
  - leading frontmatter rendered as a metadata table
  - a later metadata-looking block stayed normal document content
- Live manual patch backup from this run:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260602-164220/workbench.html`
- Live auto-reapply backup from this run:
  `$HOME/Library/Application Support/Cursor/workbench-patch-backups/cursor-app-20260602-164526/workbench.html`

This live run found a Cursor-startup failure that fixture tests did not cover:
restoring a stale clean backup could leave the current Cursor JavaScript bundle
using Trusted Types policy names that were missing from the restored
`workbench.html` CSP. Cursor then opened to a blank workbench. The patch now
repairs `streamingMarkdownPolicy`, `mermaidDiagram2`, and `mermaidDiagramOuter`
before injection, and `ensure-patched` plus `verify-auto-reapply` treat missing
policy names as an unpatched state when a `trusted-types` directive is present.
During the same run, Cursor downloaded an update; the LaunchAgent patched both
the ShipIt update cache workbenches and the installed `/Applications/Cursor.app`
workbench.

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

### Extension/settings viability snapshot

Snapshot date: 2026-06-02.

Inspected repo commit:

```text
2a8e51e69ac2d32cf0d4fb158633e75cfcb03d03
```

Inspected local Cursor app:

- Cursor version: `3.5.33`
- Cursor bundle id: `com.todesktop.230313mzl4w4u92`
- Workbench bundle still contains Cursor's native editable Markdown preview
  surface:
  - `.markdown-editor-react__richtext-content`
  - `contentClassName:"markdown-editor-react__richtext-content"`
  - `editable:!0`
- Built-in Markdown extension still exposes normal VS Code Markdown preview
  machinery:
  - `markdown.styles`
  - `markdown.preview.fontSize`
  - `markdown.previewStyles`
  - `markdown.previewScripts`
  - `markdown.markdownItPlugins`
  - custom editor id `vscode.markdown.preview.editor`

Current verdict:

- A settings or extension path is viable for the VS Code-style Markdown preview
  webview:
  - `Markdown: Open Preview`
  - `Markdown: Open Preview to the Side`
  - the `vscode.markdown.preview.editor` custom editor
  - third-party preview webviews such as Markdown Preview Enhanced
- That path is not currently a replacement for this repo's goal:
  - Cursor native `Preview | Markdown`
  - editable rendered Markdown in the main workbench DOM
  - no separate raw-editor plus side-preview workflow
- The important distinction is surface ownership:
  - VS Code Markdown APIs customize the Markdown preview webview.
  - Cursor's editable preview is a private Tiptap/ProseMirror component in the
    main Cursor workbench bundle.
  - I did not find a supported Cursor/VS Code setting, contribution point, or
    extension API that injects CSS/JS into that native editable preview in place.
- A custom extension could build a new editable webview/custom editor, but that
  would be a replacement editor, not customization of Cursor's native editable
  preview. It would need to recreate editing, selection, document sync, undo,
  checkboxes, focus behavior, and Cursor-specific integration.

Primary docs checked:

- Cursor migration docs state that Cursor is based on VS Code and supports
  importing VS Code settings and extensions:
  <https://docs.cursor.com/en/guides/migration/vscode>
- VS Code Markdown docs describe `markdown.styles` as applying to the Markdown
  preview:
  <https://code.visualstudio.com/docs/languages/markdown#_using-your-own-css>
- VS Code Markdown extension docs describe `markdown.previewStyles`,
  `markdown.markdownItPlugins`, and `markdown.previewScripts` as Markdown
  preview extension points:
  <https://code.visualstudio.com/api/extension-guides/markdown-extension>
- VS Code webview docs describe custom webviews as fully customizable but
  separate, resource-heavy extension UI:
  <https://code.visualstudio.com/api/extension-guides/webview>

Recheck this conclusion when any of these change:

- Cursor exposes an official API or setting for the native editable Markdown
  preview.
- Cursor changes `Preview | Markdown` from the private
  `.markdown-editor-react__richtext-content` / Tiptap surface to a documented
  extension-owned surface.
- The local Cursor bundle no longer contains the current private selector or the
  relevant VS Code Markdown preview contribution points.

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
