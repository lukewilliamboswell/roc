import { EditorView, basicSetup } from "codemirror";
import { EditorState, Extension } from "@codemirror/state";
import { hoverTooltip, keymap } from "@codemirror/view";
import { search, openSearchPanel } from "@codemirror/search";
import { defaultKeymap, indentMore, indentLess } from "@codemirror/commands";
import { oneDark } from "@codemirror/theme-one-dark";
import { rocStreamLanguage } from "./roc-language";

interface EditorViewOptions {
  doc?: string;
  theme?: "light" | "dark";
  hoverTooltip?: (view: EditorView, pos: number, side: number) => Promise<any>;
  onChange?: (content: string) => void;
}

/**
 * Creates a CodeMirror 6 editor view with the specified configuration
 */
export function createEditorView(
  parent: HTMLElement,
  options: EditorViewOptions = {},
): EditorView {
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

interface EditorStateOptions {
  theme?: "light" | "dark";
  hoverTooltip?: (view: EditorView, pos: number, side: number) => Promise<any>;
}

/**
 * Creates a CodeMirror 6 editor state with the specified configuration
 */
export function createEditorState(
  doc: string,
  options: EditorStateOptions = {},
): EditorState {
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
 */
export function openSearchPanelInView(view: EditorView): void {
  openSearchPanel(view);
}

/**
 * Gets the current document content from an editor view
 */
export function getDocumentContent(view: EditorView): string {
  return view.state.doc.toString();
}

/**
 * Sets the document content in an editor view
 */
export function setDocumentContent(view: EditorView, content: string): void {
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
 */
export function getCursorPosition(view: EditorView): number {
  return view.state.selection.main.head;
}

/**
 * Sets the cursor position in an editor view
 */
export function setCursorPosition(view: EditorView, pos: number): void {
  view.dispatch({
    selection: { anchor: pos, head: pos },
  });
}

// Export the search function for compatibility
export { openSearchPanel };
