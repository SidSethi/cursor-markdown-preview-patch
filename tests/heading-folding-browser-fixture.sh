#!/usr/bin/env bash
# Browser fixture for the injected heading folding runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CHROME_BIN="${CHROME_BIN:-}"
if [[ -z "$CHROME_BIN" ]]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "google-chrome" \
    "chromium"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      CHROME_BIN="$(command -v "$candidate")"
      break
    fi
    if [[ -x "$candidate" ]]; then
      CHROME_BIN="$candidate"
      break
    fi
  done
fi

if [[ -z "$CHROME_BIN" ]]; then
  echo "Skipping heading folding browser fixture: Chrome not found"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

custom_js_url="$(
  node -e 'const { pathToFileURL } = require("url"); process.stdout.write(pathToFileURL(process.argv[1]).href);' \
    "$REPO_DIR/preview/custom.js"
)"
custom_css_url="$(
  node -e 'const { pathToFileURL } = require("url"); process.stdout.write(pathToFileURL(process.argv[1]).href);' \
    "$REPO_DIR/preview/custom.css"
)"
fixture_url="$(
  node -e 'const { pathToFileURL } = require("url"); process.stdout.write(pathToFileURL(process.argv[1]).href);' \
    "$tmp/fixture.html"
)"

cat > "$tmp/fixture.html" <<HTML
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <link rel="stylesheet" href="$custom_css_url">
  <style>
    body {
      background: white;
      color: black;
      font: 14px system-ui, sans-serif;
      margin: 20px;
    }

    .markdown-editor-react__richtext-content {
      border: 1px solid #ddd;
      margin: 20px 0;
      max-width: 760px;
      padding: 16px;
    }

    .tiptap.ProseMirror > * {
      margin: 8px 0;
    }
  </style>
</head>
<body>
  <div id="host">
    <div id="fixture" class="markdown-editor-react__richtext-content">
      <div class="tiptap ProseMirror" contenteditable="true">
        <h1>One</h1>
        <p>Intro</p>
        <h2>Two</h2>
        <p>Two body</p>
        <h3>Three</h3>
        <p>Three body</p>
        <h2>Two</h2>
        <p>Second two body</p>
      </div>
    </div>

    <div id="frontmatter-fixture" class="markdown-editor-react__richtext-content">
      <div class="tiptap ProseMirror" contenteditable="true">
        <hr>
        <h1>name: skill-author<br>description: Create or update skills.</h1>
        <h1>Actual Heading</h1>
        <p>Body after frontmatter</p>
      </div>
    </div>

    <div id="non-leading-frontmatter-fixture" class="markdown-editor-react__richtext-content">
      <div class="tiptap ProseMirror" contenteditable="true">
        <h1>Body Heading</h1>
        <p>Intro before metadata-like content</p>
        <hr>
        <h1>name: not-frontmatter<br>description: Body metadata.</h1>
        <p>Body after metadata-like content</p>
      </div>
    </div>

    <div id="empty-heading-fixture" class="markdown-editor-react__richtext-content">
      <div class="tiptap ProseMirror" contenteditable="true">
        <h1>Empty Test</h1>
        <p>Intro</p>
        <h2>Empty Child</h2>
        <h2>Full Child</h2>
        <p>Full child body</p>
      </div>
    </div>

    <div id="same-tag-fixture" class="markdown-editor-react__richtext-content">
      <div class="tiptap ProseMirror" contenteditable="true">
        <h1 aria-level="1" style="font-size: 32px">Visual One</h1>
        <p>Visual intro</p>
        <h1 aria-level="1" style="font-size: 24px">Visual Two</h1>
        <p>Visual two body</p>
        <h1 aria-level="1" style="font-size: 20px">Visual Three</h1>
        <p>Visual three body</p>
        <h1 aria-level="1" style="font-size: 24px">Visual Two Peer</h1>
        <p>Visual peer body</p>
      </div>
    </div>

    <div id="cursor-mode-host-fixture">
      <button type="button">Preview</button>
      <button type="button">Markdown</button>
      <div id="cursor-scroll-host-fixture">
        <div id="promoted-toolbar-fixture" class="markdown-editor-react__richtext-content">
          <div class="tiptap ProseMirror" contenteditable="true">
            <h1>Promoted One</h1>
            <p>Promoted intro</p>
            <h2>Promoted Two</h2>
            <p>Promoted body</p>
          </div>
        </div>
      </div>
    </div>

    <div id="fallback-fixture">
      <div class="tiptap ProseMirror" contenteditable="true">
        <h1>Fallback One</h1>
        <p>Fallback intro</p>
        <h2>Fallback Two</h2>
        <p>Fallback body</p>
      </div>
    </div>
  </div>

  <script>
    window.__cursorMarkdownPreviewPatchEnableTestHooks = true;
    const nativeInnerText =
      Object.getOwnPropertyDescriptor(HTMLElement.prototype, "innerText");
    Object.defineProperty(HTMLElement.prototype, "innerText", {
      configurable: true,
      get() {
        const text = nativeInnerText?.get
          ? nativeInnerText.get.call(this)
          : this.textContent;
        if (!/^H[1-6]$/.test(this.tagName || "")) {
          return text;
        }

        const content = window.getComputedStyle(this, "::before").content;
        const marker =
          content && content !== "none" && content !== '""'
            ? content.replace(/^"(.*)"$/, "\$1")
            : "";
        return marker ? marker + "\\n" + text : text;
      },
      set(value) {
        if (nativeInnerText?.set) {
          nativeInnerText.set.call(this, value);
          return;
        }

        this.textContent = value;
      },
    });
    window.__beforePatchSnapshots = {};
    for (const id of [
      "fixture",
      "frontmatter-fixture",
      "non-leading-frontmatter-fixture",
      "empty-heading-fixture",
      "same-tag-fixture",
      "promoted-toolbar-fixture",
      "fallback-fixture",
    ]) {
      const root = document.querySelector("#" + id + " .tiptap.ProseMirror");
      window.__beforePatchSnapshots[id] = Array.from(root.children).map((node) => ({
        tag: node.tagName,
        className: node.getAttribute("class"),
        style: node.getAttribute("style"),
        ariaHidden: node.getAttribute("aria-hidden"),
        contenteditable: node.getAttribute("contenteditable"),
      }));
    }
  </script>
  <script src="$custom_js_url"></script>
  <script>
    (() => {
      const results = [];
      const pass = (message) => results.push("PASS " + message);
      const fail = (message) => results.push("FAIL " + message);
      const assert = (condition, message) =>
        condition ? pass(message) : fail(message);

      const snapshotChildren = (root) =>
        Array.from(root.children).map((node) => ({
          tag: node.tagName,
          className: node.getAttribute("class"),
          style: node.getAttribute("style"),
          ariaHidden: node.getAttribute("aria-hidden"),
          contenteditable: node.getAttribute("contenteditable"),
        }));

      const assertChildrenUnmutated = (id) => {
        const root = document.querySelector("#" + id + " .tiptap.ProseMirror");
        assert(
          JSON.stringify(snapshotChildren(root)) ===
            JSON.stringify(window.__beforePatchSnapshots[id]),
          id + " ProseMirror direct children were not mutated"
        );
      };

      const getOwnedToolbar = (container) => {
        const rootId = container.getAttribute("data-cursor-md-fold-root");
        return document.querySelector(
          '.cursor-md-heading-fold-toolbar[data-cursor-md-fold-toolbar-for="' +
            rootId +
            '"]'
        );
      };

      const getOwnedStyle = (container) => {
        const rootId = container.getAttribute("data-cursor-md-fold-root");
        return document.querySelector(
          '.cursor-md-heading-fold-style[data-cursor-md-fold-style-for="' +
            rootId +
            '"]'
        );
      };

      const clickHeadingGutter = (heading, xOffset = 8) => {
        const rect = heading.getBoundingClientRect();
        const clickTarget = heading.parentElement || heading;
        const eventOptions = {
          bubbles: true,
          cancelable: true,
          clientX: rect.left + xOffset,
          clientY: rect.top + Math.max(4, Math.min(12, rect.height / 2)),
        };

        for (const eventName of ["mousedown", "mouseup", "click"]) {
          clickTarget.dispatchEvent(
            new MouseEvent(eventName, {
              ...eventOptions,
            })
          );
        }
      };
      const legacyClickHeadingGutter = (heading, xOffset = 8) => {
        const rect = heading.getBoundingClientRect();
        const clickTarget = heading.parentElement || heading;
        clickTarget.dispatchEvent(
          new MouseEvent("click", {
            bubbles: true,
            cancelable: true,
            clientX: rect.left + xOffset,
            clientY: rect.top + Math.max(4, Math.min(12, rect.height / 2)),
          })
        );
      };

      const finish = () => {
        const failed = results.some((entry) => entry.startsWith("FAIL "));
        document.body.setAttribute("data-test-result", failed ? "FAIL" : "PASS");
        const output = document.createElement("pre");
        output.id = "heading-folding-test-result";
        output.textContent = results.join("\\n");
        document.body.append(output);
      };

      const runTests = () => {
        try {
          const hooks = window.__cursorMarkdownPreviewPatchTest;
          assert(!!hooks, "test hooks exposed");
          document.dispatchEvent(new Event("DOMContentLoaded"));
          hooks.renderAll();

          const container = document.getElementById("fixture");
          const root = container.querySelector(".tiptap.ProseMirror");
          const sections = hooks.getHeadingSections(container);
          assert(sections.length === 4, "four heading sections detected");
          assert(sections[0].contentStartIndex === 1, "H1 content starts after heading");
          assert(sections[0].contentEndIndex === 7, "H1 range reaches document end");
          assert(sections[1].contentEndIndex === 5, "first H2 stops before next H2");
          assert(sections[3].text === "Two", "duplicate heading text remains distinct");

          const toolbar = getOwnedToolbar(container);
          const style = getOwnedStyle(container);
          assert(!!toolbar, "toolbar created");
          assert(!!style, "style created");
          assert(
            window.getComputedStyle(toolbar).position === "sticky",
            "toolbar is sticky"
          );
          assert(
            window.getComputedStyle(toolbar).top === "0px",
            "toolbar is pinned to preview scroll top"
          );
          assert(
            !!toolbar.querySelector(
              'button[data-cursor-md-fold-action="fold-to-current"]'
            ),
            "fold to current toolbar button created"
          );
          assert(
            !!toolbar.querySelector(
              'button[data-cursor-md-fold-action="unfold-current"]'
            ),
            "unfold current toolbar button created"
          );
          assert(
            !style.textContent.includes("padding-left"),
            "heading marker CSS does not shift heading text"
          );
          assert(!root.contains(toolbar), "toolbar outside ProseMirror");
          assert(!root.contains(style), "style outside ProseMirror");
          assertChildrenUnmutated("fixture");

          const directToggleRange = document.createRange();
          directToggleRange.selectNodeContents(root.children[1]);
          directToggleRange.collapse(true);
          const directToggleSelection = window.getSelection();
          directToggleSelection.removeAllRanges();
          directToggleSelection.addRange(directToggleRange);
          clickHeadingGutter(root.children[0]);
          assert(
            !getOwnedStyle(container).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ),
            "clicking H1 gutter skips fold while selection is inside content"
          );
          hooks.renderAll();
          assert(
            !getOwnedStyle(container).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ),
            "selection-protected direct fold remains skipped after rerender"
          );
          assertChildrenUnmutated("fixture");

          directToggleSelection.removeAllRanges();
          clickHeadingGutter(root.children[0]);
          assert(
            getOwnedStyle(container).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ),
            "clicking H1 gutter folds H1 content range when selection is clear"
          );
          hooks.renderAll();
          assert(
            getOwnedStyle(container).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ),
            "H1 fold survives rerender when innerText includes marker content"
          );
          assertChildrenUnmutated("fixture");

          legacyClickHeadingGutter(root.children[0]);
          assert(
            !getOwnedStyle(container).textContent.includes("display: none"),
            "legacy click-only H1 gutter handler still unfolds H1"
          );

          toolbar
            .querySelector(
              'button[data-cursor-md-fold-action="fold-to-level"][data-cursor-md-fold-level="2"]'
            )
            .click();
          const foldToH2Css = getOwnedStyle(container).textContent;
          assert(
            foldToH2Css.includes(":nth-child(n + 4):nth-child(-n + 6)"),
            "fold to H2 folds first H2 section"
          );
          assert(
            foldToH2Css.includes(
              '--cursor-md-heading-fold-marker: "+"; --cursor-md-heading-fold-marker-opacity: 0.85'
            ),
            "collapsed headings keep visible plus marker"
          );

          toolbar
            .querySelector('button[data-cursor-md-fold-action="unfold-all"]')
            .click();
          assert(
            !getOwnedStyle(container).textContent.includes("display: none"),
            "unfold all clears hidden ranges"
          );

          const range = document.createRange();
          range.selectNodeContents(root.children[3]);
          range.collapse(true);
          const selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
          toolbar
            .querySelector('button[data-cursor-md-fold-action="fold-to-current"]')
            .click();
          const foldToCurrentCss = getOwnedStyle(container).textContent;
          assert(
            !foldToCurrentCss.includes(":nth-child(n + 4):nth-child(-n + 6)") &&
              foldToCurrentCss.includes(":nth-child(n + 8):nth-child(-n + 8)"),
            "fold to current uses active parent heading level"
          );

          toolbar
            .querySelector('button[data-cursor-md-fold-action="unfold-all"]')
            .click();

          selection.removeAllRanges();
          toolbar
            .querySelector('button[data-cursor-md-fold-action="fold-all"]')
            .click();
          assert(
            getOwnedStyle(container).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ),
            "fold all collapses top-level section when selection is clear"
          );
          clickHeadingGutter(root.children[0]);
          assert(
            !getOwnedStyle(container).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ) &&
              getOwnedStyle(container).textContent.includes(
                ":nth-child(n + 4):nth-child(-n + 6)"
              ),
            "opening parent section leaves nested headings folded"
          );
          range.selectNodeContents(root.children[1]);
          range.collapse(true);
          selection.removeAllRanges();
          selection.addRange(range);
          toolbar
            .querySelector('button[data-cursor-md-fold-action="unfold-current"]')
            .click();
          assert(
            !getOwnedStyle(container).textContent.includes("display: none"),
            "unfold current clears current section and descendant folds"
          );
          selection.removeAllRanges();

          range.selectNodeContents(root.children[1]);
          range.collapse(true);
          selection.removeAllRanges();
          selection.addRange(range);
          toolbar
            .querySelector('button[data-cursor-md-fold-action="fold-all"]')
            .click();
          assert(
            !getOwnedStyle(container).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ),
            "fold all skips section containing active selection"
          );
          selection.removeAllRanges();

          const frontmatterContainer =
            document.getElementById("frontmatter-fixture");
          const frontmatterRoot =
            frontmatterContainer.querySelector(".tiptap.ProseMirror");
          const frontmatterTable =
            document.querySelector(".cursor-md-frontmatter");
          assert(!!frontmatterTable, "frontmatter table created");
          assert(
            !frontmatterRoot.contains(frontmatterTable),
            "frontmatter table outside ProseMirror"
          );
          const frontmatterSections =
            hooks.getHeadingSections(frontmatterContainer);
          assert(
            frontmatterSections.length === 1 &&
              frontmatterSections[0].text === "Actual Heading",
            "frontmatter source heading excluded from heading folds"
          );
          assertChildrenUnmutated("frontmatter-fixture");

          const nonLeadingFrontmatterContainer =
            document.getElementById("non-leading-frontmatter-fixture");
          const nonLeadingFrontmatterSections =
            hooks.getHeadingSections(nonLeadingFrontmatterContainer);
          assert(
            !nonLeadingFrontmatterContainer.classList.contains(
              "cursor-md-has-frontmatter"
            ),
            "non-leading metadata-like block is not rendered as frontmatter"
          );
          assert(
            nonLeadingFrontmatterSections.length === 2 &&
              nonLeadingFrontmatterSections[0].text === "Body Heading" &&
              nonLeadingFrontmatterSections[1].text.includes(
                "name: not-frontmatter"
              ),
            "non-leading metadata-like heading remains normal document content"
          );
          assertChildrenUnmutated("non-leading-frontmatter-fixture");

          const emptyContainer =
            document.getElementById("empty-heading-fixture");
          const emptyRoot =
            emptyContainer.querySelector(".tiptap.ProseMirror");
          const emptySections = hooks.getHeadingSections(emptyContainer);
          assert(
            emptySections.length === 3,
            "empty-heading fixture detects three heading sections"
          );
          assert(
            emptySections[1].text === "Empty Child" &&
              emptySections[1].hasContent === false,
            "empty heading section is not foldable"
          );
          const emptyToolbar = getOwnedToolbar(emptyContainer);
          const emptyStyle = getOwnedStyle(emptyContainer);
          assert(!!emptyToolbar, "empty-heading toolbar created");
          assert(!!emptyStyle, "empty-heading style created");
          assert(
            !emptyStyle.textContent.includes("> :nth-child(3)"),
            "empty heading has no fold marker rule"
          );
          const beforeEmptyClickCss = emptyStyle.textContent;
          clickHeadingGutter(emptyRoot.children[2]);
          assert(
            getOwnedStyle(emptyContainer).textContent === beforeEmptyClickCss,
            "clicking empty heading gutter does not fold"
          );
          emptyToolbar
            .querySelector(
              'button[data-cursor-md-fold-action="fold-to-level"][data-cursor-md-fold-level="2"]'
            )
            .click();
          const emptyFoldCss = getOwnedStyle(emptyContainer).textContent;
          assert(
            emptyFoldCss.includes(":nth-child(n + 5):nth-child(-n + 5)") &&
              !emptyFoldCss.includes("> :nth-child(3)"),
            "fold to H2 ignores empty heading and folds only contentful peer"
          );
          assertChildrenUnmutated("empty-heading-fixture");

          const sameTagContainer =
            document.getElementById("same-tag-fixture");
          const sameTagRoot =
            sameTagContainer.querySelector(".tiptap.ProseMirror");
          const sameTagSections = hooks.getHeadingSections(sameTagContainer);
          assert(
            sameTagSections.length === 4,
            "same-tag fixture detects four heading sections"
          );
          assert(
            sameTagSections[0].level === 1 &&
              sameTagSections[1].level === 2 &&
              sameTagSections[2].level === 3,
            "same-tag fixture resolves visual heading levels"
          );
          assert(
            sameTagSections[0].contentEndIndex === 7 &&
              sameTagSections[1].contentEndIndex === 5,
            "same-tag fixture computes nested heading ranges"
          );

          const sameTagToolbar = getOwnedToolbar(sameTagContainer);
          const sameTagStyle = getOwnedStyle(sameTagContainer);
          assert(!!sameTagToolbar, "same-tag toolbar created");
          assert(!!sameTagStyle, "same-tag style created");
          assert(!sameTagRoot.contains(sameTagToolbar), "same-tag toolbar outside ProseMirror");
          assert(!sameTagRoot.contains(sameTagStyle), "same-tag style outside ProseMirror");
          clickHeadingGutter(sameTagRoot.children[0]);
          assert(
            getOwnedStyle(sameTagContainer).textContent.includes(
              ":nth-child(n + 2):nth-child(-n + 8)"
            ),
            "same-tag top heading fold hides nested headings too"
          );
          assertChildrenUnmutated("same-tag-fixture");

          const promotedContainer = document.getElementById("promoted-toolbar-fixture");
          const promotedRoot =
            promotedContainer.querySelector(".tiptap.ProseMirror");
          const promotedToolbar = getOwnedToolbar(promotedContainer);
          const promotedScrollHost = document.getElementById(
            "cursor-scroll-host-fixture"
          );
          assert(!!promotedToolbar, "promoted toolbar created");
          assert(
            promotedToolbar.parentElement?.id === "cursor-mode-host-fixture",
            "toolbar promoted below Preview and Markdown controls"
          );
          assert(
            !promotedScrollHost.contains(promotedToolbar),
            "promoted toolbar outside preview scroll host"
          );
          assert(!promotedRoot.contains(promotedToolbar), "promoted toolbar outside ProseMirror");
          assertChildrenUnmutated("promoted-toolbar-fixture");

          const fallbackContainer = document.getElementById("fallback-fixture");
          const fallbackRoot =
            fallbackContainer.querySelector(".tiptap.ProseMirror");
          const fallbackSections = hooks.getHeadingSections(fallbackContainer);
          assert(
            fallbackSections.length === 2 &&
              fallbackSections[0].text === "Fallback One",
            "fallback ProseMirror preview sections detected"
          );

          const fallbackToolbar = getOwnedToolbar(fallbackContainer);
          const fallbackStyle = getOwnedStyle(fallbackContainer);
          assert(!!fallbackToolbar, "fallback toolbar created");
          assert(!!fallbackStyle, "fallback style created");
          assert(!fallbackRoot.contains(fallbackToolbar), "fallback toolbar outside ProseMirror");
          assert(!fallbackRoot.contains(fallbackStyle), "fallback style outside ProseMirror");

          fallbackToolbar
            .querySelector(
              'button[data-cursor-md-fold-action="fold-to-level"][data-cursor-md-fold-level="2"]'
            )
            .click();
          assert(
            getOwnedStyle(fallbackContainer).textContent.includes(
              ":nth-child(n + 4):nth-child(-n + 4)"
            ),
            "fallback fold to H2 folds H2 section"
          );
          assertChildrenUnmutated("fallback-fixture");

          const fallbackRootId = fallbackContainer.getAttribute(
            "data-cursor-md-fold-root"
          );
          fallbackContainer.remove();
          hooks.renderAll();
          assert(
            !document.querySelector(
              '.cursor-md-heading-fold-toolbar[data-cursor-md-fold-toolbar-for="' +
                fallbackRootId +
                '"]'
            ),
            "removed preview container cleans up generated toolbar"
          );
          assert(
            !document.querySelector(
              '.cursor-md-heading-fold-style[data-cursor-md-fold-style-for="' +
                fallbackRootId +
                '"]'
            ),
            "removed preview container cleans up generated style"
          );
        } catch (error) {
          fail(error && error.stack ? error.stack : String(error));
        }

        finish();
      };

      runTests();
    })();
  </script>
</body>
</html>
HTML

"$CHROME_BIN" \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --allow-file-access-from-files \
  --virtual-time-budget=1000 \
  --dump-dom "$fixture_url" > "$tmp/dom.html" 2> "$tmp/chrome.err" || {
    cat "$tmp/chrome.err" >&2
    exit 1
  }

if ! grep -q 'data-test-result="PASS"' "$tmp/dom.html"; then
  cat "$tmp/chrome.err" >&2
  sed -n '/<pre id="heading-folding-test-result"/,/<\/pre>/p' "$tmp/dom.html" >&2
  tail -n 80 "$tmp/dom.html" >&2
  exit 1
fi
