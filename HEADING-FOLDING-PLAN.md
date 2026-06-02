# Heading Folding In Cursor Markdown Preview - Plan

> Adversarial implementation plan for Obsidian-like heading folding in Cursor's native editable Markdown preview.

---

# Current Conclusion

| Topic | Decision |
| ----- | -------- |
| MVP scope | In-preview heading toggles plus in-preview fold controls |
| Command Palette | Defer until a low-risk command bridge is proven |
| ProseMirror children | Never wrap, reorder, annotate, or style inline from JavaScript |
| Fold state | Keep ephemeral per preview container at first |
| Fold to current | Implement as in-preview toolbar action, not Command Palette |
| Unfold current | Implement as in-preview toolbar action for current section and descendants |
| Empty sections | Do not make empty heading sections foldable |
| Toolbar placement | Promote above the preview scroll host when Cursor's mode-toggle host is detectable; otherwise use sticky fallback |
| Live Cursor writes | Only after explicit user approval |
| Verification | Fixture-first, then optional live runtime inspection |

- The optimal first version is not a full Cursor command integration.
- The optimal first version is a conservative visual-folding layer:
  - Detect headings from the rendered editable preview DOM.
  - Store fold state in injected JavaScript.
  - Insert generated UI only outside the ProseMirror editable subtree.
  - Hide folded section content with generated CSS selectors.
  - Preserve Cursor's underlying document model.
- A true Command Palette command is a separate project:
  - Existing editor fold commands target Monaco text editors, not this rich preview.
  - The current injected script can run in the workbench page, but does not have a proven command-registration API.
  - Patching `workbench.desktop.main.js` to register commands would be much more brittle than the current `workbench.html` injection.
- The implemented toolbar includes `Fold to current` because selection-to-parent-heading mapping was proven in fixture and live checks without command registration.
- The implemented toolbar includes `Unfold current` so a user can reopen a parent section and then clear all nested folds inside it without touching peer sections.
- Empty heading sections are not foldable; collapsed non-empty headings keep their `+` marker visible so hidden content is obvious.
- The implemented toolbar is promoted outside the preview scroll host when Cursor's surrounding `Preview | Markdown` host is detectable, so the fold controls remain visible while the document body scrolls.

---

# Adversarial Review

**P0 - ProseMirror mutation can recreate the previous editing regression**

- Failure mode:
  - JavaScript adds classes, inline styles, wrappers, attributes, buttons, or sentinel nodes to `.tiptap.ProseMirror > *`.
  - Cursor's Tiptap/ProseMirror editor loses reliable selection, cursor movement, typing, or undo behavior.
- Evidence:
  - Previous frontmatter implementation broke editing after mutating editable nodes.
- Guardrail:
  - Generated controls must live outside `.tiptap.ProseMirror`.
  - JavaScript may add state to the outer `.markdown-editor-react__richtext-content` container only.
  - Runtime verification must compare child count and child attributes before and after toggling.

**P0 - Hiding content can strand the active selection inside invisible nodes**

- Failure mode:
  - User folds a heading while the caret or selected text is inside the section.
  - Cursor still thinks the selection is in hidden content.
  - Arrow keys, typing, copy, and undo appear broken.
- Guardrail:
  - Before collapsing a range, inspect `window.getSelection()`.
  - If selection intersects the range to hide, either:
    - refuse the collapse for that range, or
    - only collapse after a runtime-proven safe focus transfer to the heading.
  - "Fold all" must skip ranges containing active selection until a safe behavior is proven.

**P1 - Heading identity is unstable under editing**

- Failure mode:
  - Fold state keyed by heading text or child index applies to the wrong heading after edits.
  - Duplicate headings collapse together or restore incorrectly.
- Guardrail:
  - MVP fold state should be ephemeral and recomputed on each render.
  - Do not persist state to `localStorage` until identity is proven.
  - Use a runtime key such as `{containerId, headingChildIndex, headingLevel, normalizedText}` only within the current rendered session.
  - Reset questionable state after large DOM changes.

**P1 - CSS range selectors can hide the wrong nodes after Cursor DOM changes**

- Failure mode:
  - Cursor inserts extra direct children, changes wrappers, or uses non-heading nodes for headings.
  - Generated `nth-child` selectors target the wrong content.
- Guardrail:
  - Always derive ranges from the current `.tiptap.ProseMirror` direct element children.
  - Recompute selectors after every scheduled render.
  - Disable folding for a container when expected anchors are missing.
  - Treat selector support as a runtime preflight.

**P1 - MutationObserver loops and large-document performance can degrade editing**

- Failure mode:
  - Every keystroke schedules heading scan, CSS rebuild, and overlay positioning.
  - Large files become sluggish.
- Guardrail:
  - Reuse the existing `requestAnimationFrame` scheduler.
  - Avoid layout reads during normal character edits.
  - Rebuild CSS only when the heading signature changes.
  - Cap work per render or disable folding above a documented heading/node threshold until optimized.

**P1 - Overlay controls can intercept normal editing**

- Failure mode:
  - Buttons or click targets cover heading text.
  - Users cannot place the caret in headings normally.
  - Text selection starts toggling folds.
- Guardrail:
  - Prefer a CSS gutter affordance on headings plus delegated click handling only inside the gutter.
  - Do not place floating controls over editable text.
  - Keep global controls outside ProseMirror and `contenteditable=false`.
  - Validate click-to-edit headings still works outside the gutter.

**P1 - Command Palette integration is an attractive footgun**

- Failure mode:
  - The implementation patches minified command-registration internals.
  - Cursor updates break commands or prevent startup.
  - Commands affect the wrong editor type.
- Guardrail:
  - Ship no workbench-bundle command patch in the first implementation.
  - Provide in-preview controls first.
  - Revisit commands only after proving a stable bridge:
    - registered command can reach the active preview container
    - command can be removed or disabled cleanly
    - command survives reload/update without deeper bundle surgery

**P2 - Nested fold state can produce confusing outcomes**

- Failure mode:
  - Child headings keep collapsed state while hidden under a collapsed parent.
  - "Unfold all" does not visibly restore expected content.
  - "Fold to level" produces overlapping CSS ranges.
- Guardrail:
  - Normalize state after every action.
  - Parent collapse wins visually.
  - "Unfold all" clears all state for the container.
  - "Fold to level N" means:
    - collapse headings with level greater than or equal to `N`
    - leave headings shallower than `N` expanded
    - document this exact behavior in code comments and tests

**P2 - Frontmatter and heading folding can interfere**

- Failure mode:
  - Frontmatter raw nodes are already visually collapsed.
  - Heading scan treats frontmatter YAML as a real heading.
  - Fold controls appear on the generated frontmatter table.
- Guardrail:
  - Exclude generated `.cursor-md-frontmatter`.
  - Exclude the raw frontmatter nodes already handled by the frontmatter renderer.
  - Preserve the existing frontmatter tests.

**P2 - Hidden content changes find, copy, and accessibility behavior**

- Failure mode:
  - Browser find skips hidden content.
  - Screen readers see unexpected hidden regions.
  - Copying a folded document omits hidden content from DOM selection.
- Guardrail:
  - Accept this for MVP only if editing behavior is sound.
  - Do not claim parity with Obsidian.
  - Avoid `aria-hidden` on ProseMirror content because that mutates editable nodes.
  - Reassess after live testing.

---

# Preferred Design

**Runtime model**

- Use one namespace for all injected behavior:
  - frontmatter rendering
  - heading folding
  - shared scheduling
- Keep generated artifacts outside `.tiptap.ProseMirror`:
  - frontmatter table
  - fold toolbar
  - per-container `<style>` for generated fold selectors
- Add only container-level state:
  - `data-cursor-md-fold-root`
  - `cursor-md-has-heading-folds`
  - no direct child mutation

**Heading detection**

- For each `.markdown-editor-react__richtext-content`:
  - Find the child `.tiptap.ProseMirror`.
  - Read direct element children only.
  - Identify headings with `H1` through `H6`.
  - Ignore generated UI outside ProseMirror.
  - Ignore frontmatter source nodes when `cursor-md-has-frontmatter` is active.
- For each heading:
  - `level = Number(tagName.slice(1))`
  - `startChildIndex = directChildIndex`
  - `endChildIndex = child before next heading with level <= current level`

**Per-heading toggle UI**

- Preferred MVP:
  - CSS heading gutter marker.
  - Delegated click handler on the preview container.
  - Toggle only when click coordinates are inside the marker gutter.
- Avoid initially:
  - Floating overlay buttons.
  - Buttons inserted inside headings.
  - Any DOM node inserted into ProseMirror.

**Global fold controls**

- Add one small `contenteditable=false` toolbar outside ProseMirror.
- Controls:
  - Fold all
  - Unfold all
  - Fold to current
  - Unfold current
  - Fold to level 2
  - Fold to level 3
  - Fold to level 4
- Defer:
  - Command Palette commands
  - Persistent state

**Generated CSS**

- One `<style>` per preview container.
- CSS targets only the current container id.
- Hidden range rule shape:
  ```css
  .markdown-editor-react__richtext-content[data-cursor-md-fold-root="..."]
    .tiptap.ProseMirror
    > :nth-child(n + 4):nth-child(-n + 12) {
    display: none !important;
  }
  ```

- Heading marker rule shape:
  ```css
  .markdown-editor-react__richtext-content.cursor-md-has-heading-folds
    .tiptap.ProseMirror
    > :is(h1, h2, h3, h4, h5, h6) {
    position: relative;
    padding-left: 1.2em;
  }
  ```

**State policy**

- Start with memory-only state:
  - no `localStorage`
  - no file writes
  - no user settings
- Clear state when:
  - heading count changes unexpectedly
  - container disappears
  - signature no longer maps to the same heading sequence

---

# Implementation Steps

**0a - Preflight**

- [ ] **0.1** Confirm working tree state:
  ```bash
  git status --short --branch
  git diff --stat
  ```

- [ ] **0.2** Run read-only Cursor selector preflight:
  ```bash
  defaults read /Applications/Cursor.app/Contents/Info CFBundleShortVersionString
  rg -n "markdown-editor-react|contentClassName:\"markdown-editor-react__richtext-content\"|editable:!0" \
    /Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.js \
    /Applications/Cursor.app/Contents/Resources/app/out/vs/workbench/workbench.desktop.main.css
  ```

- [ ] **0.3** Do not run live `./patch`, `./rollback`, or `./verify-auto-reapply` during planning or fixture-only work.

**1a - Refactor shared injection structure**

- [ ] **1.1** Rename the top-level JS namespace away from frontmatter-only naming.
- [ ] **1.2** Keep the existing frontmatter API and marker strings covered by tests.
- [ ] **1.3** Preserve the single `MutationObserver` and `requestAnimationFrame` scheduler.
- [ ] **1.4** Make `renderContainer(container)` call separate modules:
  - `renderFrontmatter(container)`
  - `renderHeadingFolds(container)`

**2a - Add heading model**

- [ ] **2.1** Implement `getEditorRoot(container)`:
  - returns `.tiptap.ProseMirror`
  - returns `null` if missing
- [ ] **2.2** Implement `getHeadingSections(container)`:
  - direct children only
  - levels 1 through 6
  - section ranges by next heading of same or shallower level
- [ ] **2.3** Implement `getHeadingSignature(sections)`:
  - heading levels
  - normalized heading text
  - child indices
- [ ] **2.4** Recompute only when signature changes.

**3a - Add folding state and CSS output**

- [ ] **3.1** Assign each container a `data-cursor-md-fold-root`.
- [ ] **3.2** Keep a `WeakMap<Element, FoldState>`.
- [ ] **3.3** Generate per-container CSS from collapsed ranges.
- [ ] **3.4** Insert/update the generated `<style>` outside ProseMirror.
- [ ] **3.5** Remove stale generated styles when the container no longer has headings.

**4a - Add interaction**

- [ ] **4.1** Add delegated `click` handling on preview containers.
- [ ] **4.2** Toggle only when clicking the heading gutter marker area.
- [ ] **4.3** Before collapse, detect whether selection intersects the range to hide.
- [ ] **4.4** Skip unsafe collapses until a safe focus-transfer behavior is proven.
- [ ] **4.5** Add outside-ProseMirror toolbar for:
  - fold all
  - unfold all
  - fold to current
  - unfold current
  - fold to level 2
  - fold to level 3
  - fold to level 4
- [ ] **4.6** Promote the toolbar above the preview scroll host when Cursor's surrounding `Preview | Markdown` host is detectable.

**5a - Update styling**

- [ ] **5.1** Keep `custom.css` valid standalone CSS.
- [ ] **5.2** Add restrained heading gutter styling.
- [ ] **5.3** Add toolbar styling using Cursor theme variables.
- [ ] **5.4** Avoid layout shifts beyond the heading gutter padding.
- [ ] **5.5** Hide heading gutter markers until hover/focus.
- [ ] **5.6** Keep toolbar available while scrolling through long preview documents.
- [ ] **5.7** Keep collapsed non-empty heading markers visible.
- [ ] **5.8** Do not show fold markers for empty heading sections.

**6a - Update fixture tests**

- [ ] **6.1** Add static tests:
  - JS marker for heading folding
  - CSS marker for heading folding
  - no template tokens
- [ ] **6.2** Add DOM fixture coverage for:
  - section range calculation
  - duplicate headings
  - nested headings
  - no headings
  - frontmatter plus headings
- [ ] **6.3** Add mutation assertions:
  - ProseMirror direct child count unchanged
  - no `class`, `style`, `aria-hidden`, or `contenteditable` added to ProseMirror children
  - generated controls outside ProseMirror
- [ ] **6.4** Add behavior fixture checks:
  - fold one heading
  - unfold one heading
  - fold all
  - unfold all
  - fold to level
  - fold to current
  - same-tag visual heading level fallback
  - toolbar promotion outside the preview scroll host
  - empty heading sections stay unmarked and uncollapsed by bulk actions

**7a - Optional live verification after explicit approval**

- [ ] **7.1** Apply through the repo wrapper or `./patch`, only with explicit user approval.
- [ ] **7.2** Reload Cursor.
- [ ] **7.3** Use Codex-controlled inspection:
  - shell read-only app-bundle checks
  - Computer Use for visible Cursor interactions when needed
  - local CDP inspection only if Cursor is launched with a debug port and the user accepts that workflow
- [ ] **7.4** Verify runtime DOM:
  - generated UI exists outside ProseMirror
  - ProseMirror children unchanged
  - folded ranges hidden by computed CSS
  - no command-palette patch was added

---

# Testing Criteria

**Static checks**

- [ ] `node --check custom.js`
- [ ] `bash tests/heading-folding-browser-fixture.sh`
- [ ] `./test.sh`
- [ ] `git diff --check`
- [ ] `bash -n patch`
- [ ] `bash -n rollback`
- [ ] `bash -n ensure-patched`
- [ ] `bash -n install-auto-reapply`
- [ ] `bash -n verify-auto-reapply`

**Fixture checks**

- [ ] Heading ranges:
  - `H1 -> H2 -> H3 -> H2 -> paragraph`
  - repeated heading text
  - heading followed immediately by same-level heading
  - no heading content at end of document
- [ ] Frontmatter coexistence:
  - generated frontmatter table remains outside ProseMirror
  - raw frontmatter source stays visually folded
  - heading folding starts after frontmatter source nodes
- [ ] Mutation safety:
  - no direct child wrappers added
  - no classes added to ProseMirror direct children
  - no inline styles added to ProseMirror direct children
  - no ARIA mutations added to ProseMirror direct children
- [ ] Interaction:
  - click heading text edits or selects heading text
  - click gutter toggles only that section
  - fold all skips active selection ranges or handles them safely
  - fold to current keeps the active section open and folds peer sections
  - unfold current clears current-section and descendant folds only
  - unfold all restores every hidden range
- [ ] Toolbar placement:
  - toolbar exists outside ProseMirror
  - toolbar is promoted below `Preview` and `Markdown` controls when that host is detectable
  - sticky fallback remains available when the mode-toggle host is not detected
- [ ] Performance:
  - 200 headings does not cause visible typing lag in fixture
  - repeated character edits do not rebuild CSS unless heading signature changes

**Live checks**

- [ ] Live app modified only after explicit approval.
- [ ] Verification clearly reports whether it touched only fixtures or the live Cursor app.
- [ ] Cursor editable preview still supports:
  - placing caret in body text
  - placing caret in headings
  - typing in body text
  - typing in headings
  - arrow-key movement across visible paragraphs
  - undo and redo
  - selection and copy of visible text
- [ ] Folding does not break:
  - frontmatter table rendering
  - checkbox editing
  - link click behavior
  - scroll position
- [ ] Toolbar remains visible after scrolling far down a long Markdown preview.

---

# Success Criteria

- Heading folding works in Cursor native `Preview | Markdown` for normal Markdown headings.
- The feature remains scoped to the current preview container.
- The feature is reversible through the existing rollback path.
- No live ProseMirror document nodes are mutated by JavaScript.
- Editing behavior remains normal after:
  - single fold
  - nested fold
  - fold all
  - unfold all
  - fold to level
  - fold to current
  - unfold current
- Fold toolbar remains available while scrolling long previews.
- Heading gutter markers remain outside the text column; expanded markers stay
  hidden until hover/focus, while collapsed markers remain visible.
- Empty heading sections have no fold marker and are ignored by bulk fold
  actions.
- Fixture tests pass.
- `node --check custom.js` passes.
- `./test.sh` passes.
- The final report states whether validation was fixture-only or included live Cursor.

---

# Deferred Work

- True Command Palette commands:
  - only after a stable command-registration bridge is found
  - not via blind minified-bundle surgery
- Persistent fold state:
  - only after stable heading identity is proven
- Keyboard shortcuts:
  - only after controls do not interfere with editing
- Accessibility polish:
  - only after the safe visual model is proven

---

# Codex Operating Notes

- Use `rg`, `sed`, `git status`, and `git diff --stat` for read-only investigation.
- Use `apply_patch` for repo edits.
- Keep changes scoped to this repo.
- Prefer fixture validation through `./test.sh`.
- Do not run live `./patch`, `./rollback`, or `./verify-auto-reapply` unless explicitly asked.
- When live validation is approved:
  - state that the live Cursor app will be modified
  - apply through the existing backup-aware scripts
  - verify behavior
  - report rollback command
- If a regression appears after a live apply:
  - roll back immediately through `./rollback`
  - report the exact failing behavior
  - preserve fixture evidence for the next attempt
