# 2026-05-14 Frontmatter Rendering Postmortem

> Read-only archive note. This records the debugging session that turned this repo from a CSS-only Cursor preview tweak into a CSS/JS frontmatter renderer.

## Context

This started from a specific rendering problem in Cursor's native editable `Preview | Markdown` surface. A Codex skill file at:

```text
/Users/sidsethi/code/dotfiles/stow/agents/.agents/skills/skill-author/SKILL.md
```

begins with YAML frontmatter:

```yaml
---
name: skill-author
description: Create or update Codex and Agent Skills.
metadata:
  short-description: Create and refine local skills
---
```

Cursor's editable preview did not treat that block as frontmatter. Instead, it rendered the `---` marker as a horizontal rule and the YAML text as a large heading-like block. The result was visually loud, hard to scan, and unlike GitHub's Markdown preview, which renders frontmatter as structured metadata.

The existing repo was a CSS-only app-bundle patch for Cursor's editable Markdown preview. That was enough for typography, but not enough to reliably parse or reshape frontmatter.

## Constraints

- Cursor did not expose a supported API for styling or extending the editable preview.
- The target UI lived in Cursor's private workbench DOM, not a Markdown preview webview.
- The app bundle was sealed enough that macOS required App Management permission for the process writing into `/Applications/Cursor.app`.
- Cursor's `workbench.html` Content Security Policy allowed same-origin scripts, but blocked inline scripts.
- The preview was still an editor. The patch had to preserve selection, cursor movement, arrow keys, typing, and ProseMirror document state.
- The user's dotfiles wrapper was the stable interface:

  ```bash
  cursor-inline-markdown-preview-patch
  cursor-inline-markdown-preview-rollback
  ```

## Failed Or Incomplete Attempts

### Styling Raw Markdown Only

The first instinct was CSS: if Cursor rendered frontmatter into predictable nodes, perhaps CSS alone could restyle it.

That was not sufficient. CSS can hide, collapse, and restyle known DOM shapes, but it cannot robustly parse flattened YAML, split nested metadata keys, or build a GitHub-like table from arbitrary frontmatter values.

### Inline JavaScript Injection

The next step was JavaScript, inserted directly into the managed `workbench.html` block.

Cursor's CSP blocked inline scripts. That explained why CSS changes could visibly apply while the frontmatter table did not appear: the script was present in the patched HTML but never ran.

The fix was to install `custom.js` as a same-origin asset next to `workbench.html`:

```text
/Applications/Cursor.app/Contents/Resources/app/out/vs/code/electron-sandbox/workbench/cursor-markdown-preview-patch.js
```

Then `workbench.html` could load it with:

```html
<script src="./cursor-markdown-preview-patch.js"></script>
```

### Mutating The ProseMirror Nodes

One version of the patch hid Cursor's raw frontmatter render by applying classes or attributes directly to the source nodes.

That made the visual output look right, but it was too invasive. The user noticed a serious editing regression: text selection and arrow-key movement behaved strangely, and most of the document felt non-editable except near the `Skill Author` heading.

That shifted the main design principle:

> The patch may add display-only UI, but it should not mutate Cursor's editable ProseMirror document nodes.

## Final Design

The final approach splits responsibilities:

- JavaScript detects frontmatter and inserts a display table.
- CSS styles the table and visually folds Cursor's raw frontmatter render.
- The editable ProseMirror subtree remains structurally intact.

### JavaScript Responsibilities

`custom.js` watches for Cursor's editable Markdown preview container:

```text
.markdown-editor-react__richtext-content
```

It recognizes Cursor's rendered frontmatter shape. In the observed Cursor version, the ProseMirror document began like this:

```text
doc(
  horizontalRule,
  heading("name: skill-author", hardBreak, "description: ...", hardBreak, "metadata:", hardBreak, "  short-description: ..."),
  heading("Skill Author"),
  ...
)
```

Because Cursor sometimes presented this content as flattened text, the parser had to handle boundaries like:

```text
name: skill-authordescription:
```

The script converts recognized YAML-ish rows into a table:

```text
name
description
metadata.short-description
```

It inserts that table outside the ProseMirror editor subtree and marks it as non-editable:

```html
<section class="cursor-md-frontmatter" contenteditable="false">
  ...
</section>
```

The only class added near the editable document is on the outer preview container:

```text
cursor-md-has-frontmatter
```

### CSS Responsibilities

`custom.css` styles the table and uses structural selectors to visually collapse the raw frontmatter nodes:

```css
.markdown-editor-react__richtext-content.cursor-md-has-frontmatter
  .tiptap.ProseMirror
  > hr:first-child { ... }

.markdown-editor-react__richtext-content.cursor-md-has-frontmatter
  .tiptap.ProseMirror
  > hr:first-child
  + :is(h1, h2, h3, h4, h5, h6) { ... }
```

This keeps the raw frontmatter in the editor model while removing it from the visible layout.

The table styling was tuned after comparing against GitHub's frontmatter preview:

- border and grid treatment similar to GitHub's metadata table
- compact row spacing
- more space above the table than below it
- key column with restrained contrast
- value column using the same foreground color family as body text
- no nested cards or heavy custom UI

## Verification Process

The most useful shift was moving from screenshots to direct runtime inspection.

### App-Bundle Verification

The patch script verifies that:

- managed start/end markers exist in `workbench.html`
- the CSS custom property is present
- the external JS script reference is present
- the installed JS asset exists
- the installed JS asset contains the expected verification token

The fixture tests run the patch against temporary `workbench.html` files instead of the real Cursor app bundle.

### Cursor Runtime Verification

Cursor was launched with a temporary Chrome DevTools Protocol port:

```bash
open -a Cursor --args --remote-debugging-port=9333
```

Codex then used CDP to inspect the live Cursor workbench. That made it possible to verify facts that screenshots could not prove:

- whether the managed script tag existed
- whether the frontmatter table existed
- whether the table was outside the ProseMirror subtree
- whether the table was `contenteditable=false`
- whether ProseMirror children had injected `class`, `style`, or `aria-hidden` attributes
- whether computed CSS was responsible for visual folding
- whether the editor's selection moved after key events

The important comparison was patched versus unpatched DOM.

Unpatched:

- no managed script
- no frontmatter table
- `.markdown-editor-react__richtext-content`
- `.tiptap.ProseMirror` children begin with `HR`, frontmatter heading, then `H1`

Patched:

- managed script present
- one `.cursor-md-frontmatter` table outside ProseMirror
- `.markdown-editor-react__richtext-content cursor-md-has-frontmatter`
- same ProseMirror child elements
- no injected classes, inline styles, or ARIA attributes on those child elements
- raw frontmatter nodes visually collapsed by computed CSS

### Editing Verification

The first automated key test accidentally clicked a paragraph that was offscreen, which produced misleading selection data. After scrolling the paragraph into view first, the check became meaningful:

- click body paragraph
- read ProseMirror selection
- dispatch ArrowRight
- dispatch ArrowDown
- read ProseMirror selection again

The observed selection moved from position `567` to `649`, confirming that arrow-key navigation still worked in the visible body paragraph after the less-invasive patch.

### Video Verification

The user provided a screen recording of the broken behavior. After `ffmpeg` was fixed locally, frames were extracted and reviewed. The recording showed:

- the table itself rendered correctly
- the caret and selection behavior clustered around the `Skill Author` heading
- body editing and arrow-key navigation looked impaired

That video was the key evidence that a visually correct table was not enough. The patch needed to be judged by editor behavior, not only by rendering.

## Rollback Fix

During the verification pass, rollback revealed a separate issue.

The patch script created a timestamped backup before replacing the managed block. If the patch was run repeatedly, the newest backup could already contain an older managed patch block. A no-argument rollback could therefore restore a patched file rather than a clean file.

There was also a same-second collision risk: two patch runs inside one second could reuse the same backup directory and overwrite the clean backup.

The fix:

- `patch` now creates unique backup directories, even for multiple runs in the same second.
- `rollback` now defaults to the newest clean backup.
- Explicit backup paths still restore exactly the requested file.
- The rollback fixture now applies the patch twice before rolling back, so this regression is covered.

## Current Commands

Apply:

```bash
cursor-inline-markdown-preview-patch --font-size 14
```

Rollback:

```bash
cursor-inline-markdown-preview-rollback
```

Run repo tests:

```bash
cd /Users/sidsethi/code/cursor-markdown-preview-patch
./test.sh
```

## Learnings

- A rendered editor is not just a document viewer. DOM changes that are harmless in a preview can break selection and keyboard behavior in an editor.
- For this kind of patch, the editable model subtree is the boundary to protect.
- CSS is better for styling and visual folding; JavaScript is better for detection and generated display UI.
- Cursor's CSP made an external same-origin JS asset more reliable than inline script injection.
- Runtime CDP inspection was more useful than screenshot comparison because it showed exact DOM placement, attributes, computed styles, and editor selection state.
- A successful visual patch still needs behavioral verification: cursor placement, text selection, arrow keys, and typing.
- Rollback logic needs tests that simulate repeated patching, not only first-run patching.

## Chat Reference

Source: local Codex/Cursor debugging session with Sid Sethi on 2026-05-14.

- Codex thread id: `019e2787-c6d4-70f0-bfac-af3f99042544`
- Codex deeplink: `codex://threads/019e2787-c6d4-70f0-bfac-af3f99042544`
- Local rollout transcript:

  ```text
  /Users/sidsethi/.codex/sessions/2026/05/14/rollout-2026-05-14T10-27-50-019e2787-c6d4-70f0-bfac-af3f99042544.jsonl
  ```

This note intentionally summarizes the chat rather than embedding a transcript. The transcript included iterative screenshots, a screen recording, permission debugging for macOS App Management, Cursor CDP inspection, and repeated patch/test/rollback cycles.
