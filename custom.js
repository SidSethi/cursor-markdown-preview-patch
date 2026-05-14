/*
 * Cursor editable rendered Markdown preview frontmatter renderer.
 *
 * The native editable preview renders a leading YAML block as normal Markdown.
 * This script recognizes that rendered shape, hides the raw nodes, and inserts a
 * compact metadata table inspired by GitHub's Markdown preview.
 */
(() => {
  const cursorMarkdownPreviewFrontmatter = {
    contentSelector: ".markdown-editor-react__richtext-content",
    tableClass: "cursor-md-frontmatter",
    signatureAttribute: "data-cursor-md-frontmatter-signature",
  };

  const {
    contentSelector,
    tableClass,
    signatureAttribute,
  } = cursorMarkdownPreviewFrontmatter;

  const normalizeText = (node) =>
    (node?.innerText || node?.textContent || "")
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+\n/g, "\n")
      .trim();

  const isHorizontalRule = (node) => {
    if (!node) {
      return false;
    }

    return node.tagName === "HR" || normalizeText(node) === "---";
  };

  const isHeading = (node) => /^H[1-6]$/.test(node?.tagName || "");

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

  const getRenderHost = (container) => container.parentElement || container;

  const findExistingTable = (container) => {
    const host = getRenderHost(container);
    const tables = Array.from(host.children).filter((child) =>
      child.classList?.contains(tableClass)
    );

    for (const extra of tables.slice(1)) {
      extra.remove();
    }

    return tables[0] || null;
  };

  const findHeadingCandidate = (container) => {
    const headings = Array.from(
      container.querySelectorAll("h1,h2,h3,h4,h5,h6,[role='heading']")
    );

    for (const heading of headings) {
      if (heading.classList?.contains(tableClass)) {
        continue;
      }

      const sourceText = normalizeText(heading);
      if (!sourceText.match(/^name:\s+/) || !sourceText.includes("description:")) {
        continue;
      }

      const rows = parseYamlishFrontmatter(sourceText);
      if (!rows.length) {
        continue;
      }

      const sourceNodes = [heading];
      const previous = heading.previousElementSibling;
      if (isHorizontalRule(previous)) {
        sourceNodes.unshift(previous);
      }

      return {
        rows,
        sourceNodes,
        signature: `heading:${sourceText}`,
      };
    }

    return null;
  };

  const findFrontmatterCandidate = (container) => {
    const headingCandidate = findHeadingCandidate(container);
    if (headingCandidate) {
      return headingCandidate;
    }

    const children = Array.from(container.children).filter(
      (child) => !child.classList?.contains(tableClass)
    );
    const startIndex = children.findIndex((child) => isHorizontalRule(child));

    if (startIndex === -1) {
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

  const renderContainer = (container) => {
    const existing = findExistingTable(container);
    const candidate = findFrontmatterCandidate(container);

    if (!candidate) {
      container.classList.remove("cursor-md-has-frontmatter");
      existing?.remove();
      return;
    }

    container.classList.add("cursor-md-has-frontmatter");

    if (existing?.getAttribute(signatureAttribute) === candidate.signature) {
      return;
    }

    existing?.remove();

    const table = buildTable(candidate.rows, candidate.signature);
    const host = getRenderHost(container);
    host.insertBefore(table, container);
  };

  let scheduled = false;
  const renderAll = () => {
    scheduled = false;
    for (const container of document.querySelectorAll(contentSelector)) {
      renderContainer(container);
    }
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
    observer.observe(document.documentElement, {
      childList: true,
      characterData: true,
      subtree: true,
    });
    scheduleRender();
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start, { once: true });
  } else {
    start();
  }
})();
