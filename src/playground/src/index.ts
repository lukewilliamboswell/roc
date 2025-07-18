import {
  createEditorView,
  setDocumentContent,
  getDocumentContent,
} from "./editor/cm6-setup";
import { createTypeHintTooltip } from "./editor/type-hints";
import { initializeWasm } from "./wasm/roc-wasm";
import "./styles/main.css";
import "./styles/editor.css";
import "./styles/tooltips.css";

// Interfaces
interface Example {
  name: string;
  description: string;
  code: string;
}

interface Diagnostic {
  severity: "error" | "warning" | "info";
  message: string;
  location: string;
  code?: string;
}

interface WasmInterface {
  compile: (code: string) => Promise<any>;
  tokenize: () => Promise<any>;
  parse: () => Promise<any>;
  canonicalize: () => Promise<any>;
  getTypes: () => Promise<any>;
  getTypeInfo: (identifier: string, line: number, ch: number) => Promise<any>;
  isReady: () => boolean;
  getMemoryUsage: () => number;
  sendMessage: (message: any) => Promise<any>;
}

// Global state variables (keeping same structure as app.js)
let wasmInterface: WasmInterface | null = null;
let currentState: "INIT" | "READY" | "LOADED" = "INIT";
let currentView: "PROBLEMS" | "TOKENS" | "AST" | "CIR" | "TYPES" = "PROBLEMS";
let lastDiagnostics: Diagnostic[] = [];
let activeExample: number | null = null;
let lastCompileTime: number | null = null;

let codeMirrorEditor: any = null;

// Examples data (from app.js)
const examples: Example[] = [
  {
    name: "Hello World",
    description: "A simple hello world program",
    code: `main! = |_|
    Stdout.line! "Hello, World!"`,
  },
  {
    name: "Basic Types",
    description: "Numbers, strings, and booleans",
    code: `module [name, age, height, isActive]

name : Str
name = "Alice"

age : I32
age = 25

height : Dec
height = 5.8

isActive : Bool
isActive = Bool.True`,
  },
  {
    name: "Types & Functions",
    description: "Custom types, functions, and conditionals",
    code: `# Custom types and functions
Color : [Red, Green, Blue]

colorToHex : Color ->{ pf: platform \"../basic-cli/platform.roc\" }

import pf.Stdout

main! = |_| Stdout.line!(\"Hello, world!\")`,
  },
  {
    name: "Basic Types",
    description: "Numbers, strings, and booleans",
    code: `module [name, age, height, isActive]

name : Str
name = "Alice"

age : I32
age = 25

height : Dec
height = 5.8

isActive : Bool
isActive = Bool.True`,
  },
];

// Main playground class
class RocPlayground {
  private compileTimeout: ReturnType<typeof setTimeout> | null = null;
  private compileStartTime: number | null = null;
  private isResizing: boolean = false;
  private startX: number = 0;
  private startWidthLeft: number = 0;
  private startWidthRight: number = 0;
  private lastCompileResult: any = null;
  private updateUrlTimeout: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    this.compileTimeout = null;
    this.compileStartTime = null;
    this.isResizing = false;
    this.startX = 0;
    this.startWidthLeft = 0;
    this.startWidthRight = 0;
    this.lastCompileResult = null;
  }

  async initialize(): Promise<void> {
    try {
      console.log("Initializing Roc Playground...");

      // Initialize WASM first
      await this.initializeWasm();

      // Setup editor
      this.setupEditor();

      // Setup UI components
      this.setupExamples();
      this.setupAutoCompile();
      this.setupUrlSharing();
      this.setupResizeHandle();
      this.initTheme();

      // Restore from URL if present
      await this.restoreFromHash();

      currentState = "READY";
      console.log("Playground initialized successfully");
    } catch (error) {
      console.error("Failed to initialize playground:", error);
      this.showError(`Failed to initialize playground: ${error.message}`);
    }
  }

  async initializeWasm(): Promise<void> {
    try {
      console.log("Loading WASM module...");
      wasmInterface = await initializeWasm();

      const outputContent = document.getElementById("outputContent");
      if (!outputContent) {
        throw new Error("Output content element not found");
      }
      outputContent.innerHTML = "Ready to compile!";
      outputContent.classList.add("status-text");

      console.log("WASM module loaded successfully");
    } catch (error) {
      console.error("Error loading WASM:", error);
      throw error;
    }
  }

  setupEditor(): void {
    const editorContainer = document.getElementById("editor");
    if (!editorContainer) {
      throw new Error("Editor container not found");
    }
    const themeAttr = document.documentElement.getAttribute("data-theme");
    const theme: "light" | "dark" = themeAttr === "dark" ? "dark" : "light";

    codeMirrorEditor = createEditorView(editorContainer, {
      doc: "# Select an example or write Roc code here...",
      theme: theme,
      hoverTooltip: createTypeHintTooltip(wasmInterface),
      onChange: (content: string) => {
        this.handleCodeChange(content);
      },
    });

    console.log("Editor setup complete");
  }

  handleCodeChange(content: string): void {
    // Auto-compile with debouncing
    if (this.compileTimeout) {
      clearTimeout(this.compileTimeout);
    }

    this.compileTimeout = setTimeout(() => {
      this.compileCode(content);
    }, 500);
  }

  async compileCode(code?: string): Promise<void> {
    if (!wasmInterface) {
      this.showError("WASM module not loaded");
      return;
    }

    try {
      this.compileStartTime = Date.now();
      this.setStatus("Compiling...");

      const result = await wasmInterface.compile(
        code || getDocumentContent(codeMirrorEditor),
      );

      lastCompileTime = Date.now() - this.compileStartTime;

      if (result.status === "SUCCESS") {
        // Parse diagnostics from the result
        lastDiagnostics = this.parseDiagnostics(result);
        this.updateDiagnosticSummary();

        // Store the full result for other views
        this.lastCompileResult = result;
      } else {
        // Handle error response
        lastDiagnostics = [
          {
            severity: "error",
            message: result.message || "Compilation failed",
            location: "unknown",
          },
        ];
        this.updateDiagnosticSummary();
        this.lastCompileResult = null;
      }

      // Show current view
      this.showCurrentView();

      // Update URL with compressed content
      this.updateUrlWithCompressedContent();
    } catch (error) {
      console.error("Compilation error:", error);
      this.showError(`Compilation failed: ${error.message}`);
    }
  }

  setupExamples(): void {
    const examplesList = document.getElementById("examplesList");

    examples.forEach((example, index) => {
      const exampleItem = document.createElement("div");
      exampleItem.className = "example-item";
      exampleItem.innerHTML = `
        <div class="example-title">${example.name}</div>
        <div class="example-description">${example.description}</div>
      `;

      exampleItem.addEventListener("click", () => {
        this.loadExample(index);
      });

      examplesList?.appendChild(exampleItem);
    });
  }

  async loadExample(index: number): Promise<void> {
    const example = examples[index];
    if (!example) return;

    // Update active example
    if (activeExample !== null) {
      document
        .querySelectorAll(".example-item")
        [activeExample].classList.remove("active");
    }

    activeExample = index;
    document.querySelectorAll(".example-item")[index].classList.add("active");

    // Set editor content
    setDocumentContent(codeMirrorEditor, example.code);

    // Compile the new code
    await this.compileCode(example.code);
  }

  setupAutoCompile(): void {
    // Auto-compile is handled in handleCodeChange
  }

  showCurrentView(): void {
    switch (currentView) {
      case "PROBLEMS":
        this.showDiagnostics();
        break;
      case "TOKENS":
        this.showTokens();
        break;
      case "AST":
        this.showParseAst();
        break;
      case "CIR":
        this.showCanCir();
        break;
      case "TYPES":
        this.showTypes();
        break;
    }
  }

  async showDiagnostics(): Promise<void> {
    currentView = "PROBLEMS";
    this.updateStageButtons();

    const outputContent = document.getElementById("outputContent");

    if (lastDiagnostics.length === 0) {
      if (outputContent) {
        outputContent.innerHTML = `<div class="success-message">No problems found!</div>`;
      }
      return;
    }

    // Use pre-formatted HTML from WASM if available
    if (this.lastCompileResult?.diagnostics?.html) {
      if (outputContent) {
        outputContent.innerHTML = this.lastCompileResult.diagnostics.html;
      }
      return;
    }

    // Fallback to simple diagnostic display
    let html = "";
    lastDiagnostics.forEach((diagnostic) => {
      const severity = diagnostic.severity || "error";
      html += `
        <div class="diagnostic ${severity}">
          <div class="diagnostic-header">
            <span class="diagnostic-severity">${severity.toUpperCase()}</span>
            <span class="diagnostic-location">${diagnostic.location || "unknown"}</span>
          </div>
          <div class="diagnostic-message">${this.escapeHtml(diagnostic.message || "")}</div>
          ${diagnostic.code ? `<div class="diagnostic-code">${this.escapeHtml(diagnostic.code)}</div>` : ""}
        </div>
      `;
    });

    if (outputContent) {
      outputContent.innerHTML = html;
    }
  }

  async showTokens(): Promise<void> {
    currentView = "TOKENS";
    this.updateStageButtons();

    if (!wasmInterface) {
      this.showError("WASM module not loaded");
      return;
    }

    try {
      const result = await wasmInterface.tokenize();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        if (outputContent) {
          outputContent.innerHTML = `<div class="sexp-output">${result.data || "No tokens"}</div>`;
        }
      } else {
        if (outputContent) {
          outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get tokens")}</div>`;
        }
      }
    } catch (error) {
      this.showError(`Failed to get tokens: ${error.message}`);
    }
  }

  async showParseAst(): Promise<void> {
    currentView = "AST";
    this.updateStageButtons();

    if (!wasmInterface) {
      this.showError("WASM module not loaded");
      return;
    }

    try {
      const result = await wasmInterface.parse();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        if (outputContent) {
          outputContent.innerHTML = `<div class="sexp-output">${result.data || "No AST"}</div>`;
        }
      } else {
        if (outputContent) {
          outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get AST")}</div>`;
        }
      }
    } catch (error) {
      this.showError(`Failed to get AST: ${error.message}`);
    }
  }

  async showCanCir(): Promise<void> {
    currentView = "CIR";
    this.updateStageButtons();

    if (!wasmInterface) {
      this.showError("WASM module not loaded");
      return;
    }

    try {
      const result = await wasmInterface.canonicalize();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        if (outputContent) {
          outputContent.innerHTML = `<div class="sexp-output">${result.data || "No CIR"}</div>`;
        }
      } else {
        if (outputContent) {
          outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get CIR")}</div>`;
        }
      }
    } catch (error) {
      this.showError(`Failed to get CIR: ${error.message}`);
    }
  }

  async showTypes(): Promise<void> {
    currentView = "TYPES";
    this.updateStageButtons();

    if (!wasmInterface) {
      this.showError("WASM module not loaded");
      return;
    }

    try {
      const result = await wasmInterface.getTypes();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        if (outputContent) {
          outputContent.innerHTML = `<div class="sexp-output">${result.data || "No types"}</div>`;
        }
      } else {
        if (outputContent) {
          outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get types")}</div>`;
        }
      }
    } catch (error) {
      this.showError(`Failed to get types: ${error.message}`);
    }
  }

  updateStageButtons(): void {
    const buttons = document.querySelectorAll(".stage-button");
    buttons.forEach((button) => {
      button.classList.remove("active");
    });

    const activeButton = document.getElementById(this.getButtonId(currentView));
    if (activeButton) {
      activeButton.classList.add("active");
    }
  }

  getButtonId(view: string): string {
    const mapping: Record<string, string> = {
      PROBLEMS: "diagnosticsBtn",
      TOKENS: "tokensBtn",
      AST: "parseBtn",
      CIR: "canBtn",
      TYPES: "typesBtn",
    };
    return mapping[view] || "diagnosticsBtn";
  }

  updateDiagnosticSummary(): void {
    const editorHeader = document.querySelector(".editor-header");

    // Remove existing summary
    const existingSummary = editorHeader?.querySelector(".diagnostic-summary");
    if (existingSummary) {
      existingSummary.remove();
    }

    // Always show summary after compilation (when timing info is available)
    if (lastCompileTime !== null) {
      const summaryDiv = document.createElement("div");
      summaryDiv.className = "diagnostic-summary";

      let totalErrors = 0;
      let totalWarnings = 0;

      // Use summary from WASM result if available
      if (
        this.lastCompileResult &&
        this.lastCompileResult.diagnostics &&
        this.lastCompileResult.diagnostics.summary
      ) {
        const diagnosticSummary = this.lastCompileResult.diagnostics.summary;
        totalErrors = diagnosticSummary.errors;
        totalWarnings = diagnosticSummary.warnings;
      } else {
        // Fallback to counting diagnostics
        totalErrors = lastDiagnostics.filter(
          (d) => d.severity === "error",
        ).length;
        totalWarnings = lastDiagnostics.filter(
          (d) => d.severity === "warning",
        ).length;
      }

      let summaryText = "";
      // Always show error/warning count after compilation
      summaryText += `Found ${totalErrors} error(s) and ${totalWarnings} warning(s)`;

      if (lastCompileTime !== null) {
        let timeText;
        if (lastCompileTime < 1000) {
          timeText = `${Math.round(lastCompileTime)}ms`;
        } else {
          timeText = `${(lastCompileTime / 1000).toFixed(1)}s`;
        }
        summaryText += (summaryText ? " " : "") + `⚡ ${timeText}`;
      }

      summaryDiv.innerHTML = summaryText;
      editorHeader?.appendChild(summaryDiv);
    }
  }

  setupResizeHandle(): void {
    const resizeHandle = document.getElementById("resizeHandle");
    const editorContainer = document.querySelector(
      ".editor-container",
    ) as HTMLElement;
    const outputContainer = document.querySelector(
      ".output-container",
    ) as HTMLElement;

    resizeHandle?.addEventListener("mousedown", (e: MouseEvent) => {
      this.isResizing = true;
      this.startX = e.clientX;
      this.startWidthLeft = editorContainer?.offsetWidth || 0;
      this.startWidthRight = outputContainer?.offsetWidth || 0;
      document.addEventListener("mousemove", (e: MouseEvent) =>
        this.handleMouseMove(e),
      );
      document.addEventListener("mouseup", () => this.handleMouseUp());
    });
  }

  handleMouseMove(e: MouseEvent): void {
    if (!this.isResizing) return;

    const deltaX = e.clientX - this.startX;
    const newLeftWidth = this.startWidthLeft + deltaX;
    const newRightWidth = this.startWidthRight - deltaX;

    if (newLeftWidth > 200 && newRightWidth > 200) {
      const editorContainer = document.querySelector(
        ".editor-container",
      ) as HTMLElement;
      const outputContainer = document.querySelector(
        ".output-container",
      ) as HTMLElement;
      if (editorContainer) {
        editorContainer.style.flex = `0 0 ${newLeftWidth}px`;
      }
      if (outputContainer) {
        outputContainer.style.flex = `0 0 ${newRightWidth}px`;
      }
    }
  }

  handleMouseUp(): void {
    this.isResizing = false;
    document.removeEventListener("mousemove", (e: MouseEvent) =>
      this.handleMouseMove(e),
    );
    document.removeEventListener("mouseup", () => this.handleMouseUp());
  }

  setupUrlSharing(): void {
    // URL sharing functionality
    window.addEventListener("hashchange", () => {
      this.restoreFromHash();
    });

    this.addShareButton();
  }

  async updateUrlWithCompressedContent(): Promise<void> {
    if (this.updateUrlTimeout) {
      clearTimeout(this.updateUrlTimeout);
    }

    this.updateUrlTimeout = setTimeout(async () => {
      try {
        const code = getDocumentContent(codeMirrorEditor);

        if (!code || code.length > 10000) {
          // Don't share very large content
          window.history.replaceState(null, "", "");
          return;
        }

        const compressed = await this.compressAndEncode(code);
        window.history.replaceState(null, "", `#content=${compressed}`);
      } catch (error) {
        console.error("Failed to update URL:", error);
      }
    }, 1000);
  }

  async restoreFromHash(): Promise<void> {
    const hash = window.location.hash.slice(1);
    if (hash) {
      try {
        let b64 = hash;

        // Handle old format: #content=base64data
        if (hash.startsWith("content=")) {
          b64 = hash.slice("content=".length);
        }

        // Handle new format: #base64data (no prefix)
        const code = await this.decodeAndDecompress(b64);
        setDocumentContent(codeMirrorEditor, code);

        // Wait for the playground to be ready before compiling
        if (currentState === "READY") {
          await this.compileCode(code);
        } else {
          console.log("Playground not ready, skipping auto-compile");
        }
      } catch (error) {
        console.error("Failed to restore from hash:", error);
      }
    }
  }

  async compressAndEncode(text: string): Promise<string> {
    // Use simple base64 encoding for better browser support
    // TODO: Add compression later with a polyfill
    const encoder = new TextEncoder();
    const data = encoder.encode(text);
    return this.uint8ToBase64(data);
  }

  async decodeAndDecompress(base64: string): Promise<string> {
    // Use simple base64 decoding for better browser support
    // TODO: Add decompression later with a polyfill
    const data = this.base64ToUint8(base64);
    return new TextDecoder().decode(data);
  }

  uint8ToBase64(uint8Array: Uint8Array): string {
    return btoa(String.fromCharCode(...uint8Array));
  }

  base64ToUint8(base64: string): Uint8Array {
    return new Uint8Array(
      atob(base64)
        .split("")
        .map((c) => c.charCodeAt(0)),
    );
  }

  initTheme(): void {
    const themeSwitch = document.getElementById("themeSwitch");
    const prefersDark = window.matchMedia(
      "(prefers-color-scheme: dark)",
    ).matches;

    // Set initial theme
    const savedTheme = localStorage.getItem("theme");
    if (savedTheme) {
      document.documentElement.setAttribute("data-theme", savedTheme);
    } else if (prefersDark) {
      document.documentElement.setAttribute("data-theme", "dark");
    } else {
      document.documentElement.setAttribute("data-theme", "light");
    }

    this.updateThemeLabel();

    // Theme switch event
    themeSwitch?.addEventListener("click", () => {
      this.toggleTheme();
    });

    // System theme change
    window
      .matchMedia("(prefers-color-scheme: dark)")
      .addEventListener("change", (e) => {
        if (!localStorage.getItem("theme")) {
          document.documentElement.setAttribute(
            "data-theme",
            e.matches ? "dark" : "light",
          );
          this.updateThemeLabel();
        }
      });
  }

  toggleTheme(): void {
    const currentTheme = document.documentElement.getAttribute("data-theme");
    const newTheme = currentTheme === "dark" ? "light" : "dark";

    document.documentElement.setAttribute("data-theme", newTheme);
    localStorage.setItem("theme", newTheme);
    this.updateThemeLabel();
  }

  updateThemeLabel(): void {
    const themeLabel = document.querySelector(".theme-label");
    const currentTheme = document.documentElement.getAttribute("data-theme");
    if (themeLabel) {
      themeLabel.textContent = currentTheme === "dark" ? "Dark" : "Light";
    }
  }

  setStatus(message: string): void {
    const outputContent = document.getElementById("outputContent");
    if (outputContent) {
      outputContent.innerHTML = `<div class="status-text">${message}</div>`;
    }
  }

  showError(message: string): void {
    const outputContent = document.getElementById("outputContent");
    if (outputContent) {
      outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(message)}</div>`;
    }
  }

  escapeHtml(text: string): string {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  parseDiagnostics(result: any): Diagnostic[] {
    // Parse diagnostics from WASM result
    const diagnostics: Diagnostic[] = [];

    if (result.diagnostics && result.diagnostics.summary) {
      const summary = result.diagnostics.summary;

      if (summary.errors > 0) {
        diagnostics.push({
          severity: "error" as const,
          message: `${summary.errors} error${summary.errors > 1 ? "s" : ""}`,
          location: "compilation",
        });
      }

      if (summary.warnings > 0) {
        diagnostics.push({
          severity: "warning" as const,
          message: `${summary.warnings} warning${summary.warnings > 1 ? "s" : ""}`,
          location: "compilation",
        });
      }
    }

    // If no specific errors, return empty array (no problems)
    return diagnostics;
  }

  addShareButton(): void {
    const headerStatus = document.querySelector(".header-status");
    if (headerStatus) {
      let shareButton = headerStatus.querySelector(
        ".share-button",
      ) as HTMLButtonElement;
      if (!shareButton) {
        shareButton = document.createElement("button");
        shareButton.className = "share-button";
        shareButton.innerHTML = "share link";
        shareButton.title = "Copy shareable link to clipboard";
        shareButton.onclick = () => this.copyShareLink();
        const themeToggle = headerStatus.querySelector(".theme-toggle");
        headerStatus.insertBefore(shareButton, themeToggle);
      }
    }
  }

  async copyShareLink(): Promise<void> {
    if (codeMirrorEditor) {
      const content = getDocumentContent(codeMirrorEditor).trim();
      if (content) {
        try {
          const b64 = await this.compressAndEncode(content);
          const shareUrl = `${window.location.origin}${window.location.pathname}#content=${b64}`;
          await navigator.clipboard.writeText(shareUrl);

          // Show temporary feedback
          const shareButton = document.querySelector(
            ".share-button",
          ) as HTMLButtonElement;
          const originalText = shareButton.innerHTML;
          shareButton.innerHTML = "copied!";
          shareButton.style.background = "var(--color-success)";

          setTimeout(() => {
            shareButton.innerHTML = originalText;
            shareButton.style.background = "";
          }, 2000);
        } catch (error) {
          console.error("Failed to copy share link:", error);
          alert("Failed to copy link to clipboard");
        }
      } else {
        alert("No content to share");
      }
    }
  }
}

// Global functions for button clicks (maintaining compatibility)
declare global {
  interface Window {
    showDiagnostics: () => void;
    showTokens: () => void;
    showParseAst: () => void;
    showCanCir: () => void;
    showTypes: () => void;
  }
}

// Initialize playground when DOM is ready
let playground: RocPlayground;

document.addEventListener("DOMContentLoaded", () => {
  playground = new RocPlayground();
  playground.initialize();

  // Set up global functions
  window.showDiagnostics = () => playground.showDiagnostics();
  window.showTokens = () => playground.showTokens();
  window.showParseAst = () => playground.showParseAst();
  window.showCanCir = () => playground.showCanCir();
  window.showTypes = () => playground.showTypes();
});
