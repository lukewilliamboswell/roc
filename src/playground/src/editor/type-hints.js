import { hoverTooltip } from "@codemirror/view";

/**
 * Creates a hover tooltip extension for type hints
 * @param {Object} wasmInterface - The WASM interface for getting type information
 * @returns {Extension} CodeMirror extension for hover tooltips
 */
export function createTypeHintTooltip(wasmInterface) {
  return hoverTooltip(async (view, pos, side) => {
    if (!wasmInterface) {
      return null;
    }

    // Get the word at the current position
    const word = getWordAtPosition(view, pos);
    if (!word || word.length === 0) {
      return null;
    }

    try {
      // Get type information from WASM
      const typeInfo = await getTypeInformation(wasmInterface, word, pos);
      if (!typeInfo) {
        return null;
      }

      return {
        pos,
        above: true,
        create: () => ({
          dom: createTooltipDOM(word, typeInfo)
        })
      };
    } catch (error) {
      console.error("Error getting type information:", error);
      return null;
    }
  });
}

/**
 * Gets the word at a specific position in the editor
 * @param {EditorView} view - The editor view
 * @param {number} pos - The position to check
 * @returns {string|null} The word at the position, or null if not found
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

  return lineText.slice(start, end);
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
 * @param {string} word - The word to get type information for
 * @param {number} pos - The position in the document
 * @returns {Promise<Object|null>} Type information or null if not found
 */
async function getTypeInformation(wasmInterface, word, pos) {
  try {
    if (!wasmInterface.getTypeInfo) {
      console.warn("getTypeInfo not available in WASM interface");
      return null;
    }

    const result = await wasmInterface.getTypeInfo(word, pos);

    if (!result || result.error) {
      return null;
    }

    return {
      type: result.type || "unknown",
      description: result.description || null
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
  const word = getWordAtPosition(view, pos);
  if (!word) return;

  const typeInfo = await getTypeInformation(wasmInterface, word, pos);
  if (!typeInfo) return;

  // Create and show tooltip
  const tooltip = createTooltipDOM(word, typeInfo);
  document.body.appendChild(tooltip);

  // Position the tooltip
  const coords = view.coordsAtPos(pos);
  if (coords) {
    tooltip.style.position = "fixed";
    tooltip.style.left = coords.left + "px";
    tooltip.style.top = (coords.top - 40) + "px";
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
  tooltips.forEach(tooltip => {
    if (tooltip.parentNode) {
      tooltip.parentNode.removeChild(tooltip);
    }
  });
}
