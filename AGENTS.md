# Agent Notes

This repo patches Cursor's installed app bundle so its native editable Markdown
preview can use custom CSS, a small JavaScript frontmatter renderer, and visual
heading folding.

For user-facing purpose, usage, caveats, file inventory, rollback behavior, and
version notes, read `README.md`. Keep this file focused on how agents should work
in the repo.

## Source Of Truth

- `README.md` is the canonical project documentation.
- `patch`, `rollback`, `ensure-patched`, `install-auto-reapply`,
  `verify-auto-reapply`, `custom.css`, `custom.js`, `runner/`, `launchd/`,
  `tests/`, and `test.sh` are the live implementation surface.
- `ARCHIVE-2026-05-14-frontmatter-rendering-postmortem.md` is historical
  context only.
- `AUTO-REAPPLY.md` is the auto-reapply design and verification runbook.

## Safety Boundaries

- Treat `/Applications/Cursor.app` and `~/Library/Application Support/Cursor` as
  live local state, not normal repo fixtures.
- Do not run `./patch`, `./rollback`, or `./verify-auto-reapply` against the
  real Cursor app unless the user explicitly asks for a live apply, restore, or
  auto-reapply verification. `./verify-auto-reapply` intentionally rolls back
  live Cursor before proving that automation restores the patch.
- Prefer fixture-based validation through `./test.sh`; it uses
  `CURSOR_WORKBENCH_HTML` and temporary directories.
- If live Cursor inspection is needed, separate read-only app-bundle checks from
  write operations.
- Preserve the stable wrapper names documented in `README.md`:
  `cursor-inline-markdown-preview-patch` and
  `cursor-inline-markdown-preview-rollback`.
- Do not rebuild or reinstall the auto-reapply runner after App Management is
  granted unless the user is prepared to re-enable the permission.

## Change Guidance

- Keep `custom.css` valid standalone CSS; Cursor may open and validate it
  directly.
- Keep `custom.js` as a same-origin asset loaded from `workbench.html`; Cursor's
  CSP blocks inline script injection.
- Avoid mutating Cursor's ProseMirror document nodes. The intended model is:
  detect frontmatter and headings, insert generated UI outside the editable
  subtree, and use CSS for visual folding.
- Heading-folding controls and generated styles should stay outside
  `.tiptap.ProseMirror`; the toolbar may be promoted into Cursor's surrounding
  `Preview | Markdown` host when that non-scrolling host is detected.
- Keep `patch` and `rollback` idempotent and backup-aware.
- Update fixture tests when changing markers, injected asset names, backup
  behavior, font-size rendering, frontmatter detection, heading-folding ranges,
  or heading-folding toolbar placement.
- Update `./verify-auto-reapply` when changing LaunchAgent labels, runner app
  paths, managed markers, or the auto-reapply install flow.

## Verification

- Run `./test.sh` after code changes.
- Run `./verify-auto-reapply` only when live auto-reapply behavior needs to be
  proven; report clearly that it modified and restored the live Cursor app.
- For shell-only edits, at minimum run:
  ```bash
  bash -n patch
  bash -n rollback
  bash -n ensure-patched
  bash -n install-auto-reapply
  bash -n verify-auto-reapply
  ```
- For JavaScript edits, run:
  ```bash
  node --check custom.js
  ```
- Report whether verification touched only fixtures or also modified the live
  Cursor app.
