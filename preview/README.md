# Preview customization

This directory is the **customization payload** that the patching scripts install
into Cursor:

- `custom.css` controls the editable preview's typography, frontmatter table,
  heading labels, and fold toolbar.
- `custom.js` renders leading YAML frontmatter and adds visual heading folding.

The installer and lifecycle code lives outside this directory in `../patch`,
`../rollback`, `../ensure-patched`, `../lib/`, and `../auto-reapply/`.

To change the preview, edit these two files, rerun `../patch`, and reload Cursor.
Neither file is a standalone Cursor extension; the patcher injects them into
Cursor's private workbench surface.
