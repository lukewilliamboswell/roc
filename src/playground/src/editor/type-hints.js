import { hoverTooltip } from "@codemirror/view";

/**
 * Creates a hover tooltip function for type hints
 * @param {Object} wasmInterface - The WASM interface for getting type information
 * @returns {Function} Hover tooltip function for CodeMirror
 */
export function createTypeHintTooltip(wasmInterface) {
  return async (view, pos, side) => {
    if (!wasmInterface) {
      return null;
    }

    // Get the word at the current position
    const wordInfo = getWordAtPosition(view, pos);
    if (!wordInfo || wordInfo.word.length === 0) {
      return null;
    }

    try {
      // Calculate line/column from position
      const line = view.state.doc.lineAt(pos);
      const lineNumber = line.number - 1; // Convert to 0-based
      const column = pos - line.from;

      // Get type information from WASM
      const typeInfo = await getTypeInformation(
        wasmInterface,
        wordInfo.word,
        lineNumber,
        column,
      );
      if (!typeInfo) {
        return null;
      }

      return {
        pos,
        above: true,
        create(view) {
          const dom = createTooltipDOM(wordInfo.word, typeInfo);
          return { dom };
        },
      };
    } catch (error) {
      console.error("Error getting type information:", error);
      return null;
    }
  };
}

/**
 * Gets the word at a specific position in the editor
 * @param {EditorView} view - The editor view
 * @param {number} pos - The position to check
 * @returns {Object|null} Object with word and position info, or null if not found
 */
function getWordAtPosition(view, pos) {
  const line = view.state.doc.lineAt(pos);
  const lineText = line.text;
  const linePos = pos - line.from;

  // Find word boundaries
  let start = linePos;
  let end = linePos;

  // Move start backward to find beginning of word
  while (start > 0 && /\w/.test(lineText[start - 1])) {
    start--;
  }

  // Move end forward to find end of word
  while (end < lineText.length && /\w/.test(lineText[end])) {
    end++;
  }

  if (start === end) {
    return null;
  }

  const word = lineText.slice(start, end);
  return {
    word,
    start: line.from + start,
    end: line.from + end,
    lineNumber: line.number - 1, // 0-based
    column: start,
  };
}

/**
 * Creates the DOM element for the type hint tooltip
 * @param {string} word - The word being hovered over
 * @param {Object} typeInfo - Type information object
 * @returns {HTMLElement} The tooltip DOM element
 */
function createTooltipDOM(word, typeInfo) {
  const tooltip = document.createElement("div");
  tooltip.className = "cm-tooltip-type-hint";

  // Create the main content
  const content = document.createElement("div");
  content.className = "type-hint-content";

  // Word name
  const wordElement = document.createElement("div");
  wordElement.className = "type-hint-word";
  wordElement.textContent = word;
  content.appendChild(wordElement);

  // Type information
  if (typeInfo.type) {
    const typeElement = document.createElement("div");
    typeElement.className = "type-hint-type";
    typeElement.textContent = `: ${typeInfo.type}`;
    content.appendChild(typeElement);
  }

  // Description if available
  if (typeInfo.description) {
    const descElement = document.createElement("div");
    descElement.className = "type-hint-description";
    descElement.textContent = typeInfo.description;
    content.appendChild(descElement);
  }

  tooltip.appendChild(content);

  // Add styles
  tooltip.style.cssText = `
    background: var(--tooltip-bg, #2d3748);
    color: var(--tooltip-text, #e2e8f0);
    border: 1px solid var(--tooltip-border, #4a5568);
    border-radius: 4px;
    padding: 8px 12px;
    font-size: 12px;
    font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
    max-width: 300px;
    z-index: 1000;
  `;

  return tooltip;
}

/**
 * Gets type information for a word at a specific position
 * @param {Object} wasmInterface - The WASM interface
 * @param {string} identifier - The identifier to get type information for
 * @param {number} line - The line number (0-based)
 * @param {number} column - The column number (0-based)
 * @returns {Promise<Object|null>} Type information or null if not found
 */
async function getTypeInformation(wasmInterface, identifier, line, column) {
  try {
    if (!wasmInterface || !wasmInterface.getTypeInfo) {
      console.warn("getTypeInfo not available in WASM interface");
      return null;
    }

    const result = await wasmInterface.getTypeInfo(identifier, line, column);

    if (!result || result.error || result.status !== "SUCCESS") {
      return null;
    }

    // Extract type information from the response
    const typeInfo = result.type_info;
    if (!typeInfo || !typeInfo.type) {
      return null;
    }

    return {
      type: typeInfo.type,
      description: typeInfo.description || null,
    };
  } catch (error) {
    console.error("Error in getTypeInformation:", error);
    return null;
  }
}

/**
 * Utility function to show a type hint tooltip at a specific position
 * @param {EditorView} view - The editor view
 * @param {number} pos - The position to show the tooltip at
 * @param {Object} wasmInterface - The WASM interface
 */
export async function showTypeHintAtPosition(view, pos, wasmInterface) {
  const wordInfo = getWordAtPosition(view, pos);
  if (!wordInfo) return;

  const typeInfo = await getTypeInformation(
    wasmInterface,
    wordInfo.word,
    wordInfo.lineNumber,
    wordInfo.column,
  );
  if (!typeInfo) return;

  // Create and show tooltip
  const tooltip = createTooltipDOM(wordInfo.word, typeInfo);
  document.body.appendChild(tooltip);

  // Position the tooltip
  const coords = view.coordsAtPos(pos);
  if (coords) {
    tooltip.style.position = "fixed";
    tooltip.style.left = coords.left + "px";
    tooltip.style.top = coords.top - 40 + "px";
  }

  // Auto-hide after 3 seconds
  setTimeout(() => {
    if (tooltip.parentNode) {
      tooltip.parentNode.removeChild(tooltip);
    }
  }, 3000);
}

/**
 * Hides any visible type hint tooltips
 */
export function hideTypeHint() {
  const tooltips = document.querySelectorAll(".cm-tooltip-type-hint");
  tooltips.forEach((tooltip) => {
    if (tooltip.parentNode) {
      tooltip.parentNode.removeChild(tooltip);
    }
  });
}
