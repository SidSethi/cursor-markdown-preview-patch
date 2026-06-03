/*
 * Cursor editable rendered Markdown preview enhancements.
 *
 * The native editable preview renders a leading YAML block as normal Markdown.
 * This script recognizes that rendered shape, hides the raw nodes, and inserts a
 * compact metadata table inspired by GitHub's Markdown preview.
 *
 * It also adds conservative heading folding for the same editable preview. Fold
 * controls and generated styles live outside the editable ProseMirror subtree.
 */
(() => {
  const cursorMarkdownPreviewPatch = {
    contentSelector: ".markdown-editor-react__richtext-content",
    editorRootSelector: ".tiptap.ProseMirror",
    frontmatter: {
      tableClass: "cursor-md-frontmatter",
      signatureAttribute: "data-cursor-md-frontmatter-signature",
    },
    headingFolding: {
      toolbarClass: "cursor-md-heading-fold-toolbar",
      styleClass: "cursor-md-heading-fold-style",
      hasFoldsClass: "cursor-md-has-heading-folds",
      rootAttribute: "data-cursor-md-fold-root",
      toolbarForAttribute: "data-cursor-md-fold-toolbar-for",
      styleForAttribute: "data-cursor-md-fold-style-for",
      actionAttribute: "data-cursor-md-fold-action",
      levelAttribute: "data-cursor-md-fold-level",
    },
  };

  const cursorMarkdownPreviewFrontmatter =
    cursorMarkdownPreviewPatch.frontmatter;
  const cursorMarkdownPreviewHeadingFolds =
    cursorMarkdownPreviewPatch.headingFolding;

  const { contentSelector, editorRootSelector } = cursorMarkdownPreviewPatch;
  const { tableClass, signatureAttribute } = cursorMarkdownPreviewFrontmatter;
  const {
    actionAttribute,
    hasFoldsClass,
    levelAttribute,
    rootAttribute,
    styleClass,
    styleForAttribute,
    toolbarClass,
    toolbarForAttribute,
  } = cursorMarkdownPreviewHeadingFolds;

  const frontmatterSourcesByContainer = new WeakMap();
  const foldStatesByContainer = new WeakMap();
  const containersByFoldRootId = new Map();
  const selectionSectionKeysByContainer = new Map();
  let nextFoldRootId = 1;
  let suppressNextHeadingClick = false;

  const normalizeString = (value) =>
    (value || "")
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+\n/g, "\n")
      .trim();

  const normalizeText = (node) =>
    normalizeString(node?.innerText || node?.textContent || "");

  const normalizeDomText = (node) => normalizeString(node?.textContent || "");

  const isHorizontalRule = (node) => {
    if (!node) {
      return false;
    }

    return node.tagName === "HR" || normalizeText(node) === "---";
  };

  const headingSelector = "h1,h2,h3,h4,h5,h6,[role='heading']";

  const readHeadingLevelAttribute = (node) => {
    const attributeNames = [
      "aria-level",
      "data-level",
      "data-heading-level",
      "data-heading",
      "level",
    ];

    for (const name of attributeNames) {
      const value = Number(node?.getAttribute?.(name));
      if (Number.isInteger(value) && value >= 1 && value <= 6) {
        return value;
      }
    }

    return 0;
  };

  const readHeadingLevelClass = (node) => {
    const classText = Array.from(node?.classList || []).join(" ");
    const match = classText.match(
      /(?:^|[\s:_-])(?:h|heading|header|level|cm-header)([1-6])(?:$|[\s:_-])/i
    );
    return match ? Number(match[1]) : 0;
  };

  const headingTagLevel = (node) => {
    const match = (node?.tagName || "").match(/^H([1-6])$/i);
    return match ? Number(match[1]) : 0;
  };

  const explicitHeadingLevel = (node) =>
    readHeadingLevelAttribute(node) || readHeadingLevelClass(node);

  const isHeading = (node) =>
    !!node &&
    (headingTagLevel(node) > 0 ||
      node.getAttribute?.("role") === "heading" ||
      explicitHeadingLevel(node) > 0);

  const getVisualHeadingLevels = (headings) => {
    const fontSizes = headings.map((heading) => {
      const fontSize =
        parseFloat(window.getComputedStyle?.(heading)?.fontSize || "0") || 0;
      return Math.round(fontSize * 100) / 100;
    });
    const uniqueSizes = Array.from(new Set(fontSizes.filter((size) => size > 0)))
      .sort((left, right) => right - left)
      .slice(0, 6);

    if (uniqueSizes.length <= 1) {
      return new Map();
    }

    return new Map(
      headings.map((heading, index) => [
        heading,
        Math.max(1, uniqueSizes.indexOf(fontSizes[index]) + 1),
      ])
    );
  };

  const getHeadingLevelResolver = (children, frontmatterSources) => {
    const headings = children.filter(
      (child) => isHeading(child) && !frontmatterSources.has(child)
    );
    const explicitLevels = new Map();

    for (const heading of headings) {
      const level = explicitHeadingLevel(heading);
      if (level) {
        explicitLevels.set(heading, level);
      }
    }

    const uniqueExplicitLevels = new Set(explicitLevels.values());
    const tagLevels = new Set(
      headings.map(headingTagLevel).filter((level) => level > 0)
    );
    const visualLevels =
      tagLevels.size <= 1 ? getVisualHeadingLevels(headings) : new Map();

    if (uniqueExplicitLevels.size > 1) {
      return (heading) =>
        explicitLevels.get(heading) || headingTagLevel(heading) || 6;
    }

    if (tagLevels.size > 1) {
      return (heading) =>
        headingTagLevel(heading) || explicitLevels.get(heading) || 6;
    }

    if (visualLevels.size > 0) {
      return (heading) =>
        visualLevels.get(heading) ||
        explicitLevels.get(heading) ||
        headingTagLevel(heading) ||
        6;
    }

    return (heading) => explicitLevels.get(heading) || headingTagLevel(heading) || 6;
  };

  const getRenderHost = (container) => container.parentElement || container;

  const hasPreviewMarkdownModeButtons = (element) => {
    if (!element) {
      return false;
    }

    const buttonTexts = Array.from(element.querySelectorAll("button")).map(
      (button) => normalizeDomText(button)
    );
    return buttonTexts.includes("Preview") && buttonTexts.includes("Markdown");
  };

  const getHeadingFoldToolbarHost = (container) => {
    const renderHost = getRenderHost(container);
    const parent = renderHost.parentElement;

    if (parent && parent !== document.body && hasPreviewMarkdownModeButtons(parent)) {
      return parent;
    }

    return renderHost;
  };

  const getHeadingFoldToolbarReference = (container, toolbarHost) => {
    const renderHost = getRenderHost(container);
    return toolbarHost === renderHost ? container : renderHost;
  };

  const getEditorRoot = (container) => {
    if (container?.classList?.contains("ProseMirror")) {
      return container;
    }

    return container?.querySelector?.(editorRootSelector) || null;
  };

  const getEditorChildren = (container) => {
    const editorRoot = getEditorRoot(container);
    return editorRoot ? Array.from(editorRoot.children) : [];
  };

  const hasMarkdownPreviewShape = (container) => {
    const editorRoot = getEditorRoot(container);
    if (!editorRoot) {
      return false;
    }

    return Array.from(editorRoot.children).some(
      (child) => isHeading(child) || isHorizontalRule(child)
    );
  };

  const getContainerForEditorRoot = (editorRoot) =>
    editorRoot.closest(contentSelector) || editorRoot.parentElement || editorRoot;

  const getPreviewContainer = (node) => {
    const contentContainer = node?.closest?.(contentSelector);
    if (contentContainer) {
      return contentContainer;
    }

    const editorRoot = node?.closest?.(editorRootSelector);
    if (!editorRoot) {
      return null;
    }

    const container = getContainerForEditorRoot(editorRoot);
    return hasMarkdownPreviewShape(container) ? container : null;
  };

  const stripQuotes = (value) => {
    const trimmed = value.trim();
    const first = trimmed[0];
    const last = trimmed[trimmed.length - 1];

    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return trimmed.slice(1, -1);
    }

    return trimmed;
  };

  const parseYamlishFrontmatter = (text) => {
    const rows = [];
    const stack = [];
    let lastRow = null;
    const normalizedText = text.replace(/\u00a0/g, " ").trim();

    if (!normalizedText.includes("\n")) {
      return parseFlattenedFrontmatter(normalizedText);
    }

    for (const rawLine of normalizedText.split(/\r?\n/)) {
      if (!rawLine.trim() || rawLine.trim() === "---") {
        continue;
      }

      const match = rawLine.match(/^(\s*)([A-Za-z0-9_-]+):(?:\s*(.*))?$/);
      if (!match) {
        if (lastRow) {
          lastRow.value = `${lastRow.value} ${rawLine.trim()}`.trim();
        }
        continue;
      }

      const indent = match[1].length;
      const key = match[2];
      const rawValue = match[3] || "";

      while (stack.length && stack[stack.length - 1].indent >= indent) {
        stack.pop();
      }

      if (!rawValue) {
        stack.push({ indent, key });
        lastRow = null;
        continue;
      }

      const prefix = stack.map((entry) => entry.key);
      const row = {
        key: [...prefix, key].join("."),
        value: stripQuotes(rawValue),
      };
      rows.push(row);
      lastRow = row;
    }

    if (rows.some((row) => row.value.match(/[A-Za-z0-9_-]+:\s*/))) {
      return parseFlattenedFrontmatter(normalizedText);
    }

    return rows;
  };

  const flattenedBoundaryKeys = [
    "short-description",
    "description",
    "metadata",
    "title",
    "name",
    "date",
    "tags",
  ];

  const getFlattenedMatches = (text) => {
    const tokenPattern = /([A-Za-z0-9_-]+):\s*/g;
    const matches = [];

    for (const match of text.matchAll(tokenPattern)) {
      let key = match[1];
      let index = match.index;
      let fullMatch = match[0];

      if (!flattenedBoundaryKeys.includes(key)) {
        for (const boundaryKey of flattenedBoundaryKeys) {
          if (!key.endsWith(boundaryKey)) {
            continue;
          }

          const prefix = key.slice(0, -boundaryKey.length);
          if (!prefix) {
            continue;
          }

          index += prefix.length;
          key = boundaryKey;
          fullMatch = text.slice(index, match.index + match[0].length);
          break;
        }
      }

      matches.push({
        0: fullMatch,
        1: key,
        index,
      });
    }

    return matches.sort((left, right) => left.index - right.index);
  };

  const parseFlattenedFrontmatter = (text) => {
    const matches = getFlattenedMatches(text);
    const rows = [];
    let pendingPrefix = "";

    for (let index = 0; index < matches.length; index += 1) {
      const match = matches[index];
      const next = matches[index + 1];
      const key = match[1];
      const valueStart = match.index + match[0].length;
      const valueEnd = next ? next.index : text.length;
      const value = stripQuotes(text.slice(valueStart, valueEnd).trim());

      if (!value) {
        pendingPrefix = key;
        continue;
      }

      rows.push({
        key: pendingPrefix ? `${pendingPrefix}.${key}` : key,
        value,
      });
      pendingPrefix = "";
    }

    return rows;
  };

  const findExistingTable = (container) => {
    const tables = [];
    let sibling = container.previousElementSibling;

    while (
      sibling &&
      (sibling.classList?.contains(tableClass) ||
        sibling.classList?.contains(toolbarClass) ||
        sibling.classList?.contains(styleClass))
    ) {
      if (sibling.classList?.contains(tableClass)) {
        tables.push(sibling);
      }
      sibling = sibling.previousElementSibling;
    }

    for (const extra of tables.slice(1)) {
      extra.remove();
    }

    return tables[0] || null;
  };

  const findHeadingCandidate = (container) => {
    const children = getEditorChildren(container);
    const openingRule = children[0];
    const heading = children[1];

    if (!isHorizontalRule(openingRule) || !isHeading(heading)) {
      return null;
    }

    const sourceText = normalizeText(heading);
    if (!sourceText.match(/^name:\s+/) || !sourceText.includes("description:")) {
      return null;
    }

    const rows = parseYamlishFrontmatter(sourceText);
    if (!rows.length) {
      return null;
    }

    return {
      rows,
      sourceNodes: [openingRule, heading],
      signature: `heading:${sourceText}`,
    };
  };

  const findFrontmatterCandidate = (container) => {
    const headingCandidate = findHeadingCandidate(container);
    if (headingCandidate) {
      return headingCandidate;
    }

    const children = getEditorChildren(container).filter(
      (child) => !child.classList?.contains(tableClass)
    );
    const startIndex = 0;

    if (!isHorizontalRule(children[startIndex])) {
      return null;
    }

    const sourceNodes = [children[startIndex]];
    const textNodes = [];
    let foundEnd = false;

    for (const child of children.slice(startIndex + 1, startIndex + 18)) {
      if (isHeading(child) && textNodes.length === 0) {
        const sourceText = normalizeText(child);
        const rows = parseYamlishFrontmatter(sourceText);

        if (rows.length) {
          sourceNodes.push(child);
          return {
            rows,
            sourceNodes,
            signature: `setext:${sourceText}`,
          };
        }

        break;
      }

      if (isHorizontalRule(child)) {
        sourceNodes.push(child);
        foundEnd = true;
        break;
      }

      if (isHeading(child)) {
        break;
      }

      const text = normalizeText(child);
      if (text) {
        textNodes.push(text);
      }
      sourceNodes.push(child);
    }

    const sourceText = textNodes.join("\n");
    if (!sourceText.match(/(^|\n)[A-Za-z0-9_-]+:\s+/)) {
      return null;
    }

    const rows = parseYamlishFrontmatter(sourceText);
    if (!rows.length) {
      return null;
    }

    return {
      rows,
      sourceNodes,
      signature: `${foundEnd ? "closed" : "open"}:${sourceText}`,
    };
  };

  const buildTable = (rows, signature) => {
    const section = document.createElement("section");
    section.className = tableClass;
    section.setAttribute("aria-label", "Markdown frontmatter");
    section.setAttribute("contenteditable", "false");
    section.setAttribute(signatureAttribute, signature);

    const table = document.createElement("table");
    const tbody = document.createElement("tbody");

    for (const row of rows) {
      const tr = document.createElement("tr");
      const th = document.createElement("th");
      const td = document.createElement("td");

      th.scope = "row";
      th.textContent = row.key;
      td.textContent = row.value;

      tr.append(th, td);
      tbody.append(tr);
    }

    table.append(tbody);
    section.append(table);
    return section;
  };

  const renderFrontmatter = (container) => {
    const existing = findExistingTable(container);
    const candidate = findFrontmatterCandidate(container);

    if (!candidate) {
      container.classList.remove("cursor-md-has-frontmatter");
      existing?.remove();
      frontmatterSourcesByContainer.delete(container);
      return;
    }

    container.classList.add("cursor-md-has-frontmatter");
    frontmatterSourcesByContainer.set(container, new Set(candidate.sourceNodes));

    if (existing?.getAttribute(signatureAttribute) === candidate.signature) {
      return;
    }

    existing?.remove();

    const table = buildTable(candidate.rows, candidate.signature);
    const host = getRenderHost(container);
    host.insertBefore(table, container);
  };

  const getFoldState = (container) => {
    let state = foldStatesByContainer.get(container);

    if (!state) {
      state = {
        rootId: `cursor-md-fold-${nextFoldRootId}`,
        signature: "",
        collapsed: new Set(),
        cssText: "",
      };
      nextFoldRootId += 1;
      foldStatesByContainer.set(container, state);
    }

    return state;
  };

  const getHeadingSections = (container) => {
    const editorRoot = getEditorRoot(container);
    if (!editorRoot) {
      return [];
    }

    const children = Array.from(editorRoot.children);
    const frontmatterSources =
      frontmatterSourcesByContainer.get(container) || new Set();
    const sections = [];
    const resolveHeadingLevel = getHeadingLevelResolver(
      children,
      frontmatterSources
    );

    for (let index = 0; index < children.length; index += 1) {
      const heading = children[index];
      if (!isHeading(heading) || frontmatterSources.has(heading)) {
        continue;
      }

      const level = resolveHeadingLevel(heading);
      let endChildIndex = children.length - 1;

      for (let nextIndex = index + 1; nextIndex < children.length; nextIndex += 1) {
        const candidate = children[nextIndex];
        if (
          isHeading(candidate) &&
          !frontmatterSources.has(candidate) &&
          resolveHeadingLevel(candidate) <= level
        ) {
          endChildIndex = nextIndex - 1;
          break;
        }
      }

      const text = normalizeDomText(heading);
      sections.push({
        key: `${index}:${level}:${text}`,
        heading,
        level,
        text,
        headingChildIndex: index,
        headingChildNumber: index + 1,
        contentStartIndex: index + 1,
        contentEndIndex: endChildIndex,
        hasContent: endChildIndex > index,
      });
    }

    return sections;
  };

  const getHeadingSignature = (sections) =>
    sections
      .map(
        (section) =>
          `${section.headingChildIndex}:${section.contentEndIndex}:${section.level}:${section.text}`
      )
      .join("\n");

  const findGeneratedElementInHost = (host, className, attribute, value) => {
    const elements = Array.from(host.children).filter(
      (child) =>
        child.classList?.contains(className) &&
        child.getAttribute(attribute) === value
    );

    for (const extra of elements.slice(1)) {
      extra.remove();
    }

    return elements[0] || null;
  };

  const findGeneratedElement = (container, className, attribute, value) =>
    findGeneratedElementInHost(getRenderHost(container), className, attribute, value);

  const findGeneratedToolbar = (container, state) => {
    const primaryHost = getHeadingFoldToolbarHost(container);
    const fallbackHost = getRenderHost(container);
    const hosts =
      primaryHost === fallbackHost ? [primaryHost] : [primaryHost, fallbackHost];
    const toolbars = hosts
      .flatMap((host) => Array.from(host.children))
      .filter(
        (child) =>
          child.classList?.contains(toolbarClass) &&
          child.getAttribute(toolbarForAttribute) === state.rootId
      );

    for (const extra of toolbars.slice(1)) {
      extra.remove();
    }

    const toolbar = toolbars[0] || null;
    if (toolbar && toolbar.parentElement !== primaryHost) {
      toolbar.remove();
      return null;
    }

    return toolbar;
  };

  const removeGeneratedToolbar = (container, state) => {
    findGeneratedToolbar(container, state)?.remove();
  };

  const removeGeneratedElements = (container, state) => {
    if (!state) {
      return;
    }

    for (const element of document.querySelectorAll(
      `.${toolbarClass}[${toolbarForAttribute}="${state.rootId}"], .${styleClass}[${styleForAttribute}="${state.rootId}"]`
    )) {
      element.remove();
    }

    const renderHost = getRenderHost(container);
    const toolbarHost = getHeadingFoldToolbarHost(container);
    const hosts = toolbarHost === renderHost ? [renderHost] : [renderHost, toolbarHost];

    for (const child of hosts.flatMap((host) => Array.from(host.children))) {
      if (
        (child.classList?.contains(toolbarClass) &&
          child.getAttribute(toolbarForAttribute) === state.rootId) ||
        (child.classList?.contains(styleClass) &&
          child.getAttribute(styleForAttribute) === state.rootId)
      ) {
        child.remove();
      }
    }
  };

  const cleanupHeadingFolds = (container) => {
    const state = foldStatesByContainer.get(container);
    removeGeneratedElements(container, state);

    if (state) {
      containersByFoldRootId.delete(state.rootId);
    }

    selectionSectionKeysByContainer.delete(container);
    container.classList.remove(hasFoldsClass);
    container.removeAttribute(rootAttribute);
    foldStatesByContainer.delete(container);
  };

  const getRootCssSelectors = (rootId) => [
    `${contentSelector}[${rootAttribute}="${rootId}"] ${editorRootSelector}`,
    `[${rootAttribute}="${rootId}"] > ${editorRootSelector}`,
    `${editorRootSelector}[${rootAttribute}="${rootId}"]`,
  ];

  const buildRuleSelector = (rootSelectors, childSelector) =>
    rootSelectors.map((rootSelector) => `${rootSelector} ${childSelector}`).join(", ");

  const buildHeadingFoldCss = (state, sections) => {
    const rootSelectors = getRootCssSelectors(state.rootId);
    const lines = [];

    for (const section of sections) {
      const isCollapsed = state.collapsed.has(section.key);
      const marker = isCollapsed ? "+" : "-";
      const markerOpacity = isCollapsed ? "0.85" : "0";
      const foldMarkerCss = section.hasContent
        ? ` --cursor-md-heading-fold-marker: "${marker}"; --cursor-md-heading-fold-marker-opacity: ${markerOpacity};`
        : "";
      lines.push(
        `${buildRuleSelector(
          rootSelectors,
          `> :nth-child(${section.headingChildNumber})`
        )} { --cursor-md-heading-level-label: "H${section.level}";${foldMarkerCss} }`
      );

      if (section.hasContent && isCollapsed) {
        lines.push(
          `${buildRuleSelector(
            rootSelectors,
            `> :nth-child(n + ${section.contentStartIndex + 1}):nth-child(-n + ${
              section.contentEndIndex + 1
            })`
          )} { display: none !important; }`
        );
      }
    }

    return lines.join("\n");
  };

  const renderHeadingFoldStyle = (container, state, sections) => {
    const cssText = buildHeadingFoldCss(state, sections);
    if (state.cssText === cssText) {
      return;
    }

    state.cssText = cssText;
    let style = findGeneratedElement(
      container,
      styleClass,
      styleForAttribute,
      state.rootId
    );

    if (!style) {
      style = document.createElement("style");
      style.className = styleClass;
      style.setAttribute(styleForAttribute, state.rootId);
      getRenderHost(container).insertBefore(style, container);
    }

    style.textContent = cssText;
  };

  const buildHeadingFoldToolbar = (state) => {
    const section = document.createElement("section");
    section.className = toolbarClass;
    section.setAttribute("aria-label", "Markdown heading folds");
    section.setAttribute("contenteditable", "false");
    section.setAttribute(toolbarForAttribute, state.rootId);

    const actions = [
      ["fold-all", "", "Fold all"],
      ["unfold-all", "", "Unfold all"],
      ["fold-to-current", "", "Fold to current"],
      ["unfold-current", "", "Unfold current"],
      ["fold-to-level", "2", "Fold to H2"],
      ["fold-to-level", "3", "Fold to H3"],
      ["fold-to-level", "4", "Fold to H4"],
    ];

    for (const [action, level, label] of actions) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = label;
      button.setAttribute(actionAttribute, action);
      if (level) {
        button.setAttribute(levelAttribute, level);
      }
      section.append(button);
    }

    return section;
  };

  const renderHeadingFoldToolbar = (container, state) => {
    const existing = findGeneratedToolbar(container, state);

    if (existing) {
      return;
    }

    const toolbar = buildHeadingFoldToolbar(state);
    const toolbarHost = getHeadingFoldToolbarHost(container);
    toolbarHost.insertBefore(
      toolbar,
      getHeadingFoldToolbarReference(container, toolbarHost)
    );
  };

  const selectionIntersectsNode = (selection, node) => {
    if (!selection || selection.rangeCount === 0) {
      return false;
    }

    if (node.contains?.(selection.anchorNode) || node.contains?.(selection.focusNode)) {
      return true;
    }

    for (let index = 0; index < selection.rangeCount; index += 1) {
      const range = selection.getRangeAt(index);
      try {
        if (range.intersectsNode(node)) {
          return true;
        }
      } catch {
        // Some Range implementations reject non-text nodes. The anchor/focus
        // check above still catches collapsed selections inside the node.
      }
    }

    return false;
  };

  const selectionIntersectsSectionContent = (container, section) => {
    if (selectionSectionKeysByContainer.get(container)?.has(section.key)) {
      return true;
    }

    const selection = window.getSelection?.();
    if (!selection || selection.rangeCount === 0 || !section.hasContent) {
      return false;
    }

    const children = getEditorChildren(container);
    for (
      let index = section.contentStartIndex;
      index <= section.contentEndIndex;
      index += 1
    ) {
      if (selectionIntersectsNode(selection, children[index])) {
        return true;
      }
    }

    return false;
  };

  const getSelectionSectionKeys = (container, sections) => {
    const selection = window.getSelection?.();
    const editorRoot = getEditorRoot(container);
    const keys = new Set();

    if (!selection || selection.rangeCount === 0 || !editorRoot) {
      return keys;
    }

    const candidateNodes = [selection.focusNode, selection.anchorNode].filter(
      Boolean
    );
    const selectionTouchesEditor =
      candidateNodes.some((node) => editorRoot.contains(node)) ||
      selectionIntersectsNode(selection, editorRoot);

    if (!selectionTouchesEditor) {
      return keys;
    }

    const children = getEditorChildren(container);
    for (const section of sections.filter((entry) => entry.hasContent)) {
      for (
        let index = section.contentStartIndex;
        index <= section.contentEndIndex;
        index += 1
      ) {
        const child = children[index];
        if (child && selectionIntersectsNode(selection, child)) {
          keys.add(section.key);
          break;
        }
      }
    }

    return keys;
  };

  const rememberSelectionContext = (container, sections) => {
    const keys = getSelectionSectionKeys(container, sections);

    if (keys.size) {
      selectionSectionKeysByContainer.set(container, keys);
    } else {
      selectionSectionKeysByContainer.delete(container);
    }

    return keys;
  };

  const getDirectEditorChildForNode = (editorRoot, node) => {
    let current =
      node?.nodeType === Node.ELEMENT_NODE ? node : node?.parentElement || null;

    while (current && current.parentElement !== editorRoot) {
      current = current.parentElement;
    }

    return current?.parentElement === editorRoot ? current : null;
  };

  const getSelectionChildIndex = (container) => {
    const selection = window.getSelection?.();
    const editorRoot = getEditorRoot(container);
    if (!selection || selection.rangeCount === 0 || !editorRoot) {
      return -1;
    }

    const children = Array.from(editorRoot.children);
    const candidateNodes = [selection.focusNode, selection.anchorNode];

    for (const node of candidateNodes) {
      const child = getDirectEditorChildForNode(editorRoot, node);
      const childIndex = child ? children.indexOf(child) : -1;
      if (childIndex >= 0) {
        return childIndex;
      }
    }

    const range = selection.getRangeAt(0);
    if (
      range.startContainer === editorRoot &&
      range.startOffset >= 0 &&
      range.startOffset < children.length
    ) {
      return range.startOffset;
    }

    return -1;
  };

  const getCurrentHeadingSection = (container, sections) => {
    const childIndex = getSelectionChildIndex(container);
    if (childIndex < 0) {
      return null;
    }

    let currentSection = null;
    for (const section of sections) {
      if (
        childIndex >= section.headingChildIndex &&
        childIndex <= section.contentEndIndex &&
        (!currentSection ||
          section.headingChildIndex > currentSection.headingChildIndex)
      ) {
        currentSection = section;
      }
    }

    return currentSection;
  };

  const reconcileFoldState = (state, sections) => {
    const nextKeys = new Set(sections.map((section) => section.key));
    state.collapsed = new Set(
      Array.from(state.collapsed).filter((key) => nextKeys.has(key))
    );
  };

  const renderHeadingFolds = (container) => {
    const sections = getHeadingSections(container);
    const foldableSections = sections.filter((section) => section.hasContent);

    if (!sections.length) {
      cleanupHeadingFolds(container);
      return;
    }

    const state = getFoldState(container);
    const signature = getHeadingSignature(sections);

    if (state.signature !== signature) {
      state.signature = signature;
      reconcileFoldState(state, sections);
      state.cssText = "";
    }

    container.classList.add(hasFoldsClass);
    container.setAttribute(rootAttribute, state.rootId);
    containersByFoldRootId.set(state.rootId, container);

    if (foldableSections.length) {
      renderHeadingFoldToolbar(container, state);
    } else {
      removeGeneratedToolbar(container, state);
    }
    renderHeadingFoldStyle(container, state, sections);
  };

  const updateHeadingFolds = (container, sections, state) => {
    reconcileFoldState(state, sections);
    state.cssText = "";
    renderHeadingFoldStyle(container, state, sections);
  };

  const applyFoldAction = (container, action, level) => {
    const sections = getHeadingSections(container);
    const foldableSections = sections.filter((section) => section.hasContent);
    const state = getFoldState(container);

    if (action === "unfold-all") {
      state.collapsed.clear();
      updateHeadingFolds(container, sections, state);
      return;
    }

    if (action === "fold-all") {
      state.collapsed.clear();
      for (const section of foldableSections) {
        if (!selectionIntersectsSectionContent(container, section)) {
          state.collapsed.add(section.key);
        }
      }
      updateHeadingFolds(container, sections, state);
      return;
    }

    if (action === "unfold-current") {
      const currentSection = getCurrentHeadingSection(container, sections);
      if (!currentSection) {
        return;
      }

      state.collapsed.delete(currentSection.key);
      for (const section of sections) {
        if (
          section.headingChildIndex > currentSection.headingChildIndex &&
          section.headingChildIndex <= currentSection.contentEndIndex
        ) {
          state.collapsed.delete(section.key);
        }
      }
      updateHeadingFolds(container, sections, state);
      return;
    }

    if (action === "fold-to-current") {
      const currentSection = getCurrentHeadingSection(container, sections);
      if (!currentSection) {
        return;
      }

      state.collapsed.clear();
      for (const section of foldableSections) {
        if (
          section.key !== currentSection.key &&
          section.level >= currentSection.level &&
          !selectionIntersectsSectionContent(container, section)
        ) {
          state.collapsed.add(section.key);
        }
      }
      updateHeadingFolds(container, sections, state);
      return;
    }

    if (action === "fold-to-level" && Number.isInteger(level)) {
      state.collapsed.clear();
      for (const section of foldableSections) {
        if (
          section.level >= level &&
          !selectionIntersectsSectionContent(container, section)
        ) {
          state.collapsed.add(section.key);
        }
      }
      updateHeadingFolds(container, sections, state);
    }
  };

  const toggleHeadingFold = (container, heading) => {
    const sections = getHeadingSections(container);
    const section = sections.find((entry) => entry.heading === heading);

    if (!section?.hasContent) {
      return;
    }

    const state = getFoldState(container);

    if (state.collapsed.has(section.key)) {
      state.collapsed.delete(section.key);
    } else {
      if (selectionIntersectsSectionContent(container, section)) {
        return;
      }

      state.collapsed.add(section.key);
    }

    updateHeadingFolds(container, sections, state);
  };

  const handleToolbarClick = (event) => {
    const button = event.target?.closest?.(
      `.${toolbarClass} button[${actionAttribute}]`
    );
    if (!button) {
      return false;
    }

    const toolbar = button.closest(`.${toolbarClass}`);
    const rootId = toolbar?.getAttribute(toolbarForAttribute);
    const container = rootId ? containersByFoldRootId.get(rootId) : null;
    if (!container) {
      return false;
    }

    event.preventDefault();
    event.stopPropagation();

    const action = button.getAttribute(actionAttribute);
    const levelValue = button.getAttribute(levelAttribute);
    const level = levelValue ? Number(levelValue) : undefined;
    applyFoldAction(container, action, level);
    return true;
  };

  const clickIsInHeadingGutter = (event, heading) => {
    const rect = heading.getBoundingClientRect?.();
    if (!rect || event.clientX < rect.left || event.clientY < rect.top) {
      return false;
    }

    if (event.clientY > rect.bottom) {
      return false;
    }

    const paddingLeft =
      parseFloat(window.getComputedStyle?.(heading)?.paddingLeft || "0") || 0;
    const gutterWidth = Math.min(128, Math.max(18, paddingLeft));
    return event.clientX <= rect.left + gutterWidth;
  };

  const findHeadingForGutterClickInContainer = (event, container) => {
    const editorRoot = getEditorRoot(container);
    if (!container || !editorRoot) {
      return null;
    }

    return (
      Array.from(editorRoot.children).find(
        (child) => isHeading(child) && clickIsInHeadingGutter(event, child)
      ) || null
    );
  };

  const findHeadingForGutterClick = (event) => {
    const targetHeading = event.target?.closest?.(headingSelector);
    if (targetHeading && clickIsInHeadingGutter(event, targetHeading)) {
      return targetHeading;
    }

    const targetContainer = getPreviewContainer(event.target);
    const targetContainerHeading = findHeadingForGutterClickInContainer(
      event,
      targetContainer
    );
    if (targetContainerHeading) {
      return targetContainerHeading;
    }

    return null;
  };

  const handleHeadingClick = (event) => {
    const heading = findHeadingForGutterClick(event);
    if (!heading) {
      return false;
    }

    const container = getPreviewContainer(heading);
    const editorRoot = getEditorRoot(container);
    if (!container || !editorRoot || heading.parentElement !== editorRoot) {
      return false;
    }

    event.preventDefault();
    event.stopPropagation();
    toggleHeadingFold(container, heading);
    return true;
  };

  const handleHeadingMouseDown = (event) => {
    const heading = findHeadingForGutterClick(event);
    if (!heading) {
      return false;
    }

    const container = getPreviewContainer(heading);
    const editorRoot = getEditorRoot(container);
    if (!container || !editorRoot || heading.parentElement !== editorRoot) {
      return false;
    }

    event.preventDefault();
    event.stopPropagation();
    suppressNextHeadingClick = true;
    toggleHeadingFold(container, heading);
    return true;
  };

  const handleDocumentMouseDown = (event) => {
    if (handleHeadingMouseDown(event)) {
      return;
    }

    window.setTimeout(handleSelectionChange, 0);
  };

  const handleDocumentClick = (event) => {
    if (suppressNextHeadingClick) {
      suppressNextHeadingClick = false;
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    if (handleToolbarClick(event)) {
      return;
    }

    handleHeadingClick(event);
  };

  const renderContainer = (container) => {
    renderFrontmatter(container);
    renderHeadingFolds(container);
  };

  const cleanupDetachedHeadingFoldContainers = (activeContainers) => {
    for (const [, container] of Array.from(containersByFoldRootId.entries())) {
      if (
        !activeContainers.has(container) ||
        !document.documentElement.contains(container)
      ) {
        cleanupHeadingFolds(container);
      }
    }
  };

  const getPreviewContainers = () => {
    const containers = [];
    const seenContainers = new Set();
    const seenEditorRoots = new Set();

    for (const container of document.querySelectorAll(contentSelector)) {
      const editorRoot = getEditorRoot(container);
      if (!editorRoot || seenEditorRoots.has(editorRoot)) {
        continue;
      }

      containers.push(container);
      seenContainers.add(container);
      seenEditorRoots.add(editorRoot);
    }

    for (const editorRoot of document.querySelectorAll(editorRootSelector)) {
      if (seenEditorRoots.has(editorRoot)) {
        continue;
      }

      const container = getContainerForEditorRoot(editorRoot);
      if (seenContainers.has(container) || !hasMarkdownPreviewShape(container)) {
        continue;
      }

      containers.push(container);
      seenContainers.add(container);
      seenEditorRoots.add(editorRoot);
    }

    return containers;
  };

  const handleSelectionChange = () => {
    for (const container of getPreviewContainers()) {
      rememberSelectionContext(container, getHeadingSections(container));
    }
  };

  let scheduled = false;
  const renderAll = () => {
    scheduled = false;
    const containers = getPreviewContainers();
    const activeContainers = new Set(containers);

    for (const container of containers) {
      renderContainer(container);
    }

    cleanupDetachedHeadingFoldContainers(activeContainers);
  };

  const scheduleRender = () => {
    if (scheduled) {
      return;
    }

    scheduled = true;
    window.requestAnimationFrame(renderAll);
  };

  const observer = new MutationObserver(scheduleRender);

  const start = () => {
    document.addEventListener("mousedown", handleDocumentMouseDown, true);
    document.addEventListener("click", handleDocumentClick, true);
    document.addEventListener("keyup", handleSelectionChange, true);
    observer.observe(document.documentElement, {
      childList: true,
      characterData: true,
      subtree: true,
    });
    scheduleRender();
  };

  if (window.__cursorMarkdownPreviewPatchEnableTestHooks) {
    window.__cursorMarkdownPreviewPatchTest = {
      applyFoldAction,
      getCurrentHeadingSection,
      getHeadingSections,
      renderAll,
      renderContainer,
    };
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
