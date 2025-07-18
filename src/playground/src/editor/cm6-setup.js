import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { hoverTooltip, keymap } from "@codemirror/view";
import { search, openSearchPanel } from "@codemirror/search";
import { defaultKeymap, indentMore, indentLess } from "@codemirror/commands";
import { oneDark } from "@codemirror/theme-one-dark";
import { rocStreamLanguage } from "./roc-language.js";

/**
 * Creates a CodeMirror 6 editor view with the specified configuration
 * @param {HTMLElement} parent - The parent element to attach the editor to
 * @param {Object} options - Configuration options
 * @param {string} options.doc - Initial document content
 * @param {string} options.theme - Theme ('light' or 'dark')
 * @param {Function} options.hoverTooltip - Hover tooltip function
 * @param {Function} options.onChange - Change handler
 * @returns {EditorView} The created editor view
 */
export function createEditorView(parent, options = {}) {
  if (!parent) {
    throw new Error("Parent element is required for createEditorView");
  }

  const extensions = [
    basicSetup,
    search(),
    EditorView.lineWrapping,
    rocStreamLanguage(),
    keymap.of([
      ...defaultKeymap,
      { key: "Tab", run: indentMore, preventDefault: true },
      { key: "Shift-Tab", run: indentLess, preventDefault: true },
    ]),
    EditorView.theme({
      "&": {
        fontSize: "14px",
        fontFamily:
          "'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace",
      },
      ".cm-content": {
        padding: "16px",
        minHeight: "200px",
      },
      ".cm-editor": {
        borderRadius: "4px",
      },
      ".cm-scroller": {
        borderRadius: "4px",
      },
    }),
  ];

  // Add theme
  if (options.theme === "dark") {
    extensions.push(oneDark);
  }

  // Add hover tooltip if provided
  if (options.hoverTooltip) {
    extensions.push(hoverTooltip(options.hoverTooltip));
  }

  // Add change handler if provided
  if (options.onChange) {
    extensions.push(
      EditorView.updateListener.of((update) => {
        if (update.docChanged) {
          options.onChange(update.state.doc.toString());
        }
      }),
    );
  }

  const state = EditorState.create({
    doc: options.doc || "",
    extensions,
  });

  return new EditorView({
    state,
    parent,
  });
}

/**
 * Creates a CodeMirror 6 editor state with the specified configuration
 * @param {string} doc - Initial document content
 * @param {Object} options - Configuration options
 * @param {string} options.theme - Theme ('light' or 'dark')
 * @param {Function} options.hoverTooltip - Hover tooltip function
 * @returns {EditorState} The created editor state
 */
export function createEditorState(doc, options = {}) {
  const extensions = [
    basicSetup,
    search(),
    EditorView.lineWrapping,
    rocStreamLanguage(),
    keymap.of([
      ...defaultKeymap,
      { key: "Tab", run: indentMore, preventDefault: true },
      { key: "Shift-Tab", run: indentLess, preventDefault: true },
    ]),
    EditorView.theme({
      "&": {
        fontSize: "14px",
        fontFamily:
          "'SF Mono', 'Monaco', 'Inconsolata', 'Roboto Mono', monospace",
      },
      ".cm-content": {
        padding: "16px",
        minHeight: "200px",
      },
    }),
  ];

  // Add theme
  if (options.theme === "dark") {
    extensions.push(oneDark);
  }

  // Add hover tooltip if provided
  if (options.hoverTooltip) {
    extensions.push(hoverTooltip(options.hoverTooltip));
  }

  return EditorState.create({
    doc: doc || "",
    extensions,
  });
}

/**
 * Opens the search panel in the given editor view
 * @param {EditorView} view - The editor view to open search panel in
 */
export function openSearchPanelInView(view) {
  openSearchPanel(view);
}

/**
 * Gets the current document content from an editor view
 * @param {EditorView} view - The editor view
 * @returns {string} The document content
 */
export function getDocumentContent(view) {
  return view.state.doc.toString();
}

/**
 * Sets the document content in an editor view
 * @param {EditorView} view - The editor view
 * @param {string} content - The new content
 */
export function setDocumentContent(view, content) {
  view.dispatch({
    changes: {
      from: 0,
      to: view.state.doc.length,
      insert: content,
    },
  });
}

/**
 * Gets the current cursor position in an editor view
 * @param {EditorView} view - The editor view
 * @returns {number} The cursor position
 */
export function getCursorPosition(view) {
  return view.state.selection.main.head;
}

/**
 * Sets the cursor position in an editor view
 * @param {EditorView} view - The editor view
 * @param {number} pos - The position to set the cursor to
 */
export function setCursorPosition(view, pos) {
  view.dispatch({
    selection: { anchor: pos, head: pos },
  });
}

// Export the search function for compatibility
export { openSearchPanel };
