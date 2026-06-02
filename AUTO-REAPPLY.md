# Cursor Patch Auto-Reapply Notes

> Findings and recommendation for keeping the Cursor editable Markdown preview
> patch applied after Cursor updates replace the app bundle.

---

# Current State

- Patch target:
  - Cursor's `electron-sandbox` or `electron-browser` workbench path under
    `/Applications/Cursor.app` or `~/Applications/Cursor.app`
  - same workbench directory receives `cursor-markdown-preview-patch.js`
- Patch implementation:
  - `patch` injects a managed CSS/JS block before `</html>`
  - `patch` copies `custom.js` into Cursor's workbench directory
  - `patch` removes an older managed block before reinjecting
  - `patch` repairs known Cursor Trusted Types policy names in stale clean
    workbench bases before injecting
  - `patch` backs up the original `workbench.html`
  - `patch` verifies markers, both installed JS feature tokens, and repaired
    Trusted Types policies before reporting success
- Rollback implementation:
  - `rollback` restores the newest clean backup by default
  - backups containing the managed patch are skipped by default
- Stable local wrapper:
  - `cursor-inline-markdown-preview-patch`
  - wraps `~/code/cursor-markdown-preview-patch/patch`
- Auto-reapply implementation:
  - `ensure-patched`
  - `install-auto-reapply`
  - `verify-auto-reapply`
  - `runner/CursorMarkdownPreviewPatchEnsure.swift`
  - `launchd/com.example.cursor-markdown-preview-patch.ensure.plist`
  - `test.sh` fixture coverage for patched, unpatched, and locked runs
- Current machine evidence checked on 2026-05-26:
  - Cursor bundle id: `com.todesktop.230313mzl4w4u92`
  - Cursor version: `3.5.33`
  - ShipIt update cache: `~/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt`
  - ShipIt logs show successful bundle replacement into `/Applications/Cursor.app`
  - `./verify-auto-reapply` passed end-to-end after the runner received App
    Management permission
  - current `workbench.html` contains the managed patch markers and JS asset
- Current machine evidence checked on 2026-06-02:
  - `./verify-auto-reapply` passed end-to-end after a live rollback
  - LaunchAgent runs advanced from `51` to `54`
  - LaunchAgent state returned to `not running`
  - LaunchAgent last exit was `0`
  - current `workbench.html` contains the managed patch markers, JS asset, and
    repaired Trusted Types policies
  - ShipIt update-cache workbenches were also patched during the run

---

# Recommendation

Use a small local runner app plus a per-user macOS `LaunchAgent`. The
LaunchAgent runs the executable inside the runner app bundle when Cursor's
app/update footprint changes; the runner app runs the guarded `ensure-patched`
script.

Primary trigger:

- `WatchPaths`
  - `~/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt`
  - `/Applications/Cursor.app`

Catch-up trigger:

- `RunAtLoad`
  - catches missed updates after login or after loading the agent
  - cheap because the wrapper exits immediately when the patch is already present

Do not use hourly cron as the default. Cursor updates already leave filesystem
signals, and `launchd` has native file-change triggers.

Do not use a raw script LaunchAgent as the final implementation. On this
machine, the raw LaunchAgent fired correctly but failed to write into
`/Applications/Cursor.app` with `Operation not permitted`. The same patch command
worked manually from Codex, which has App Management permission. The practical
difference is macOS permission attribution: the background job needs its own
grantable app identity.

Do not watch only `workbench.html` as the primary trigger. The patch script writes
that file, so a direct watch can self-trigger. It can be made safe with locks and
presence checks, but watching the app bundle and ShipIt directory is cleaner.

---

# Why This Is The Clear Choice

- Matches the actual failure mode:
  - Cursor updates replace the app bundle
  - replacement removes the injected `workbench.html` block and JS asset
- Uses existing strengths:
  - `patch` is already idempotent
  - `patch` already backs up, cleans old markers, writes assets, and verifies
- Keeps moving parts small:
  - one shell wrapper
  - one local runner app
  - one per-user LaunchAgent plist
  - no daemon process
  - no third-party file watcher
  - no high-frequency polling
- Fits macOS:
  - `launchd.plist` supports `WatchPaths`
  - `StandardOutPath` and `StandardErrorPath` give a durable audit trail
  - user agent avoids system LaunchDaemon scope

---

# Guarded Wrapper

The runner app runs `ensure-patched`, not `patch` directly.

Responsibilities:

- acquire a lock
- sleep briefly to let ShipIt finish replacing the bundle
- locate `workbench.html`
- exit if the patch markers, JS asset, feature tokens, and Trusted Types policy
  repairs are already present
- run the patch command only when the patch is missing
- log all output
- avoid UI scripting by default

Default behavior:

```bash
./ensure-patched
```

Notes:

- `sleep 20` handles `WatchPaths` firing while ShipIt is still writing.
- The lock prevents duplicate runs from simultaneous app and ShipIt events.
- The presence check prevents loops and unnecessary backups.
- The default patch command is this repo's `./patch`.
- `CURSOR_MARKDOWN_PREVIEW_PATCH_CMD` can point at a stable wrapper such as
  `cursor-inline-markdown-preview-patch`.
- UI reload should stay separate unless explicitly desired. Automatic App
  Management and Accessibility permissions are a larger trust surface than
  simply ensuring the files are patched.

---

# Runner App

Installed path:

- `~/Applications/Cursor Markdown Preview Patch Ensure.app`

Source:

- `runner/CursorMarkdownPreviewPatchEnsure.swift`

Installer:

- `install-auto-reapply`

The runner is intentionally small:

- read repo/log paths from its `Info.plist`
- append a log header
- run `ensure-patched`
- write stdout/stderr to `~/Library/Logs/cursor-markdown-preview-patch/`
- exit with `ensure-patched`'s status

Grant this app App Management permission once:

- `System Settings > Privacy & Security > App Management`
- enable `~/Applications/Cursor Markdown Preview Patch Ensure.app`
- if it is not listed yet, run `./verify-auto-reapply` once so macOS blocks the
  write and adds the runner as a disabled App Management entry; the verifier
  restores the patch manually before failing
- do not rebuild or reinstall the runner after granting permission unless you
  are prepared to re-enable App Management; this local runner is ad-hoc signed,
  and changing its executable can change the code identity macOS uses for
  privacy decisions

Because the LaunchAgent invokes the runner executable directly, `launchctl`
reports the runner's actual exit status. Treat the runner logs as the detailed
patch result source of truth:

- `~/Library/Logs/cursor-markdown-preview-patch/ensure.log`
- `~/Library/Logs/cursor-markdown-preview-patch/ensure.err.log`

---

# LaunchAgent Shape

Live label on this machine:

- `com.sidsethi.cursor-markdown-preview-patch.ensure`

Example plist:

- `launchd/com.example.cursor-markdown-preview-patch.ensure.plist`

Install location:

- `~/Library/LaunchAgents/com.example.cursor-markdown-preview-patch.ensure.plist`

Before loading the example manually:

- replace `/ABSOLUTE/PATH/TO/HOME`
- update the Cursor bundle id in the ShipIt path if needed
- prefer `./install-auto-reapply` for the live machine-specific plist

Current example shape:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.cursor-markdown-preview-patch.ensure</string>

  <key>ProgramArguments</key>
  <array>
    <string>/ABSOLUTE/PATH/TO/HOME/Applications/Cursor Markdown Preview Patch Ensure.app/Contents/MacOS/CursorMarkdownPreviewPatchEnsure</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>WatchPaths</key>
  <array>
    <string>/ABSOLUTE/PATH/TO/HOME/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt</string>
    <string>/Applications/Cursor.app</string>
  </array>

  <key>StandardOutPath</key>
  <string>/ABSOLUTE/PATH/TO/HOME/Library/Logs/cursor-markdown-preview-patch/launchd.log</string>

  <key>StandardErrorPath</key>
  <string>/ABSOLUTE/PATH/TO/HOME/Library/Logs/cursor-markdown-preview-patch/launchd.err.log</string>

  <key>ThrottleInterval</key>
  <integer>60</integer>
</dict>
</plist>
```

Install flow:

```bash
./install-auto-reapply
launchctl print "gui/$(id -u)/com.sidsethi.cursor-markdown-preview-patch.ensure"
```

Uninstall flow:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.sidsethi.cursor-markdown-preview-patch.ensure.plist"
```

---

# Alternatives Considered

**Hourly or frequent cron**

- Pros:
  - simplest mental model
  - independent of Cursor's updater internals
- Cons:
  - wasteful
  - slower to repair after updates unless run frequently
  - not aligned with the user preference to avoid dumb polling
- Verdict:
  - avoid as primary mechanism

**Low-frequency `StartInterval` fallback**

- Pros:
  - can catch a missed `WatchPaths` event
  - still lower noise than hourly cron if set to once or twice daily
- Cons:
  - not necessary until a missed update is observed
  - makes the design less event-driven
- Verdict:
  - optional later fallback, not part of the first implementation

**Watch `workbench.html` directly**

- Pros:
  - detects the exact file becoming unpatched
- Cons:
  - patching rewrites that same file
  - needs lock/debounce/presence checks to avoid self-trigger noise
  - path may briefly disappear during bundle replacement
- Verdict:
  - usable as a secondary signal only if needed

**Run patch on every Cursor launch**

- Pros:
  - conceptually close to when the user needs the patch
- Cons:
  - no simple supported macOS trigger for arbitrary app launch without another
    watcher
  - launch-time UI scripting adds permission surface
- Verdict:
  - not worth the complexity

**Third-party file watcher such as `fswatch`**

- Pros:
  - flexible
- Cons:
  - extra dependency
  - usually needs a long-running process
  - redundant with launchd for this case
- Verdict:
  - avoid

**Cursor extension or supported Markdown settings**

- Pros:
  - would be cleaner if supported
- Cons:
  - current repo exists because the editable `Preview | Markdown` surface does
    not expose a supported styling/frontmatter API
  - VS Code-style Markdown preview settings do not affect this editable surface
- Verdict:
  - not a replacement for this patch today

---

# Implemented

1. `ensure-patched`
   - read-only presence check first
   - atomic lock directory
   - short debounce sleep
   - calls this repo's `./patch` by default
   - supports `CURSOR_MARKDOWN_PREVIEW_PATCH_CMD` for wrapper commands
   - no Cursor reload or UI scripting

2. `launchd/com.example.cursor-markdown-preview-patch.ensure.plist`
   - public example with placeholder absolute paths
   - runs the local runner app executable directly
   - logs launchd's own output under `~/Library/Logs/cursor-markdown-preview-patch/`

3. `runner/CursorMarkdownPreviewPatchEnsure.swift`
   - small LSUIElement app runner
   - launches `ensure-patched`
   - writes durable logs
   - provides a grantable App Management identity

4. `install-auto-reapply`
   - builds the runner app with `swiftc`
   - ad-hoc signs the app when `codesign` is available
   - backs up an existing live plist before replacing it
   - bootstraps the per-user LaunchAgent

5. `verify-auto-reapply`
   - rolls back the live patch to simulate an update
   - triggers the LaunchAgent
   - waits for the runner to finish
   - verifies markers, JS asset, feature tokens, and Trusted Types policies were
     restored
   - restores the patch manually before exiting if auto-reapply fails

6. `test.sh`
   - patched fixture exits without running patch
   - unpatched fixture calls a fake patch command
   - real patch fixture verifies a second run does not create another backup
   - lock held exits cleanly
   - Swift runner parse is checked when `swiftc` is available
   - plist syntax is checked with `plutil` when available
   - shell scripts pass ShellCheck on this machine

7. Install with `./install-auto-reapply`.
   - live plist is backed up if present
   - generated plist is checked with `plutil -lint`
   - runner app is checked with `codesign --verify`
   - verify with `launchctl print`
   - trigger once with `launchctl kickstart`

8. Confirm behavior with `./verify-auto-reapply`.
   - inspect logs if it fails
   - verify `workbench.html` has managed markers
   - verify `cursor-markdown-preview-patch.js` exists

Controlled test on 2026-05-26:

- `./rollback` removed the managed markers and JS asset
- app-backed LaunchAgent ran through the runner
- runner log showed `Operation not permitted`
- current implementation now reports that runner failure through `launchctl`
- `workbench.html` remained unpatched
- manual `CURSOR_MARKDOWN_PREVIEW_PATCH_DEBOUNCE_SECONDS=0 ./ensure-patched`
  restored the patch successfully

Interpretation:

- WatchPaths and runner launch are working
- the failed test was caused by missing App Management for the runner app
- after granting permission, `./verify-auto-reapply` became the required
  end-to-end proof

Final verified test on 2026-05-26:

- `./verify-auto-reapply` rolled back the live patch
- LaunchAgent runs advanced during the verifier run
- LaunchAgent state returned to `not running`
- LaunchAgent last exit was `0`
- `workbench.html` regained the managed markers
- `cursor-markdown-preview-patch.js` existed and contained the frontmatter token

Live hardening test on 2026-06-02:

- `./verify-auto-reapply` rolled back the live patch
- app-backed LaunchAgent ran through the runner
- LaunchAgent runs advanced from `51` to `54`
- LaunchAgent state returned to `not running`
- LaunchAgent last exit was `0`
- `workbench.html` regained the managed markers
- `cursor-markdown-preview-patch.js` existed and contained the frontmatter and
  heading-folding feature tokens
- `workbench.html` contained `streamingMarkdownPolicy`, `mermaidDiagram2`, and
  `mermaidDiagramOuter`
- Cursor opened successfully after the repair
- During this run, Cursor downloaded an update and the runner patched both the
  ShipIt update cache workbenches and `/Applications/Cursor.app`

---

# Multi-Machine Notes

- Keep the patch repo and wrapper path configurable:
  - `CURSOR_INLINE_MARKDOWN_PREVIEW_REPO`
  - `CURSOR_WORKBENCH_PATCH_BACKUP_ROOT`
- Discover Cursor's bundle id from:
  - `/Applications/Cursor.app/Contents/Info.plist`
- Derive ShipIt path from bundle id:
  - `~/Library/Caches/<bundle-id>.ShipIt`
- Keep installation per-user:
  - each Mac gets its own `~/Library/LaunchAgents` plist
  - each Mac gets its own App Management permission prompt/history
- For dotfiles/Stow:
  - template the plist if absolute usernames differ
  - still run `stow -n -v` before installing live files
- For non-macOS:
  - replace `launchd` with the native user service manager
  - Linux likely means a `systemd --user` path unit
  - Windows likely means Task Scheduler or a startup task watching app update
    state

---

# Decision

Implement `ensure-patched` plus an app-backed per-user LaunchAgent using
`WatchPaths` on Cursor's ShipIt directory and `/Applications/Cursor.app`.

Skip cron, skip third-party watchers, and keep Cursor reload manual for the first
version. That gives fast repair after updates with the smallest durable macOS
surface area while preserving a real App Management permission target.
