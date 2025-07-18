import { Diagnostic, linter, lintGutter } from "@codemirror/lint";
import { EditorView } from "@codemirror/view";
import { StateField, StateEffect } from "@codemirror/state";
import { Text } from "@codemirror/state";

export interface RocDiagnostic {
  severity: "error" | "warning" | "info";
  message: string;
  location: string;
  code?: string;
}

interface ParsedLocation {
  line: number;
  column: number;
  endLine?: number;
  endColumn?: number;
}

/**
 * Parses location strings from Roc compiler diagnostics
 * Expected formats:
 * - "line:column" (e.g., "5:10")
 * - "line:column-endColumn" (e.g., "5:10-15")
 * - "line:column-endLine:endColumn" (e.g., "5:10-7:5")
 */
function parseLocation(location: string): ParsedLocation | null {
  if (!location || typeof location !== "string") {
    return null;
  }

  // Handle different location formats
  const rangeMatch = location.match(/^(\d+):(\d+)-(\d+):(\d+)$/);
  if (rangeMatch) {
    return {
      line: parseInt(rangeMatch[1]!, 10),
      column: parseInt(rangeMatch[2]!, 10),
      endLine: parseInt(rangeMatch[3]!, 10),
      endColumn: parseInt(rangeMatch[4]!, 10),
    };
  }

  const columnRangeMatch = location.match(/^(\d+):(\d+)-(\d+)$/);
  if (columnRangeMatch) {
    return {
      line: parseInt(columnRangeMatch[1]!, 10),
      column: parseInt(columnRangeMatch[2]!, 10),
      endColumn: parseInt(columnRangeMatch[3]!, 10),
    };
  }

  const simpleMatch = location.match(/^(\d+):(\d+)$/);
  if (simpleMatch) {
    return {
      line: parseInt(simpleMatch[1]!, 10),
      column: parseInt(simpleMatch[2]!, 10),
    };
  }

  return null;
}

/**
 * Converts a parsed location to CodeMirror document positions
 */
function locationToPositions(
  location: ParsedLocation,
  doc: Text,
): { from: number; to: number } | null {
  try {
    // CodeMirror uses 0-based indexing, but compiler usually uses 1-based
    const line = Math.max(0, location.line - 1);
    const column = Math.max(0, location.column - 1);

    if (line >= doc.lines) {
      return null;
    }

    const lineObj = doc.line(line + 1);
    const from = lineObj.from + Math.min(column, lineObj.length);

    let to = from;

    if (location.endLine && location.endColumn) {
      const endLine = Math.max(0, location.endLine - 1);
      const endColumn = Math.max(0, location.endColumn - 1);

      if (endLine < doc.lines) {
        const endLineObj = doc.line(endLine + 1);
        to = endLineObj.from + Math.min(endColumn, endLineObj.length);
      }
    } else if (location.endColumn) {
      const endColumn = Math.max(0, location.endColumn - 1);
      to = lineObj.from + Math.min(endColumn, lineObj.length);
    } else {
      // Default to highlighting the whole word or at least one character
      to = Math.min(from + 1, lineObj.to);

      // Try to find the end of the current word
      const text = doc.sliceString(from, lineObj.to);
      const wordMatch = text.match(/^\w+/);
      if (wordMatch) {
        to = from + wordMatch[0].length;
      }
    }

    return { from, to: Math.max(from, to) };
  } catch (error) {
    console.warn("Failed to convert location to positions:", error);
    return null;
  }
}

/**
 * Creates a linter that integrates with Roc compiler diagnostics
 */
export function createRocLinter(getDiagnostics: () => RocDiagnostic[]) {
  return linter((view) => {
    const diagnostics: Diagnostic[] = [];
    const rocDiagnostics = getDiagnostics();

    for (const rocDiag of rocDiagnostics) {
      const parsedLocation = parseLocation(rocDiag.location);
      if (!parsedLocation) {
        console.warn("Could not parse location:", rocDiag.location);
        continue;
      }

      const positions = locationToPositions(parsedLocation, view.state.doc);
      if (!positions) {
        console.warn(
          "Could not convert location to positions:",
          parsedLocation,
        );
        continue;
      }

      diagnostics.push({
        from: positions.from,
        to: positions.to,
        severity: rocDiag.severity,
        message: rocDiag.message,
      });
    }

    return diagnostics;
  });
}

/**
 * State effect to update diagnostics
 */
export const updateDiagnostics = StateEffect.define<RocDiagnostic[]>();

/**
 * State field to store current diagnostics
 */
export const diagnosticsState = StateField.define<RocDiagnostic[]>({
  create: () => [],
  update: (diagnostics, tr) => {
    for (const effect of tr.effects) {
      if (effect.is(updateDiagnostics)) {
        return effect.value;
      }
    }
    return diagnostics;
  },
});

/**
 * Extension that provides diagnostic integration
 */
export function rocDiagnostics() {
  return [
    diagnosticsState,
    lintGutter(),
    createRocLinter(() => {
      // This will be called by the linter to get current diagnostics
      // We'll update this when we integrate with the editor
      return [];
    }),
  ];
}

/**
 * Updates diagnostics in the editor view
 */
export function updateEditorDiagnostics(
  view: EditorView,
  diagnostics: RocDiagnostic[],
): void {
  view.dispatch({
    effects: updateDiagnostics.of(diagnostics),
  });
}

/**
 * Creates a diagnostic-aware linter that uses the state field
 */
export function createStatefulRocLinter() {
  return linter((view) => {
    const diagnostics: Diagnostic[] = [];
    const rocDiagnostics = view.state.field(diagnosticsState, false) || [];

    for (const rocDiag of rocDiagnostics) {
      const parsedLocation = parseLocation(rocDiag.location);
      if (!parsedLocation) {
        continue;
      }

      const positions = locationToPositions(parsedLocation, view.state.doc);
      if (!positions) {
        continue;
      }

      diagnostics.push({
        from: positions.from,
        to: positions.to,
        severity: rocDiag.severity,
        message: rocDiag.message,
      });
    }

    return diagnostics;
  });
}

/**
 * Complete diagnostic extension with state management
 */
export function rocDiagnosticsExtension() {
  return [diagnosticsState, lintGutter(), createStatefulRocLinter()];
}
