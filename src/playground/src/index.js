import {
  createEditorView,
  setDocumentContent,
  getDocumentContent,
} from "./editor/cm6-setup.js";
import { createTypeHintTooltip } from "./editor/type-hints.js";
import { initializeWasm } from "./wasm/roc-wasm.js";
import "./styles/main.css";
import "./styles/editor.css";
import "./styles/tooltips.css";

// Global state variables (keeping same structure as app.js)
let wasmInterface = null;
let currentState = "INIT";
let currentView = "PROBLEMS";
let lastDiagnostics = [];
let activeExample = null;
let lastCompileTime = null;
let updateUrlTimeout = null;
let codeMirrorEditor = null;

// Examples data (from app.js)
const examples = [
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
  constructor() {
    this.compileTimeout = null;
    this.compileStartTime = null;
    this.isResizing = false;
    this.startX = 0;
    this.startWidthLeft = 0;
    this.startWidthRight = 0;
    this.lastCompileResult = null;
  }

  async initialize() {
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

  async initializeWasm() {
    try {
      console.log("Loading WASM module...");
      wasmInterface = await initializeWasm();

      const outputContent = document.getElementById("outputContent");
      outputContent.innerHTML = "Ready to compile!";
      outputContent.classList.add("status-text");

      console.log("WASM module loaded successfully");
    } catch (error) {
      console.error("Error loading WASM:", error);
      throw error;
    }
  }

  setupEditor() {
    const editorContainer = document.getElementById("editor");
    const theme =
      document.documentElement.getAttribute("data-theme") || "light";

    codeMirrorEditor = createEditorView(editorContainer, {
      doc: "# Select an example or write Roc code here...",
      theme: theme,
      hoverTooltip: createTypeHintTooltip(wasmInterface),
      onChange: (content) => {
        this.handleCodeChange(content);
      },
    });

    console.log("Editor setup complete");
  }

  handleCodeChange(content) {
    // Auto-compile with debouncing
    if (this.compileTimeout) {
      clearTimeout(this.compileTimeout);
    }

    this.compileTimeout = setTimeout(() => {
      this.compileCode(content);
    }, 500);
  }

  async compileCode(code) {
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

  setupExamples() {
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

      examplesList.appendChild(exampleItem);
    });
  }

  async loadExample(index) {
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

  setupAutoCompile() {
    // Auto-compile is handled in handleCodeChange
  }

  showCurrentView() {
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

  async showDiagnostics() {
    currentView = "PROBLEMS";
    this.updateStageButtons();

    const outputContent = document.getElementById("outputContent");

    if (lastDiagnostics.length === 0) {
      outputContent.innerHTML = `<div class="success-message">No problems found!</div>`;
      return;
    }

    // If we have HTML diagnostics from WASM, use those
    if (
      this.lastCompileResult &&
      this.lastCompileResult.diagnostics &&
      this.lastCompileResult.diagnostics.html
    ) {
      outputContent.innerHTML = this.lastCompileResult.diagnostics.html;
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

    outputContent.innerHTML = html;
  }

  async showTokens() {
    currentView = "TOKENS";
    this.updateStageButtons();

    try {
      const result = await wasmInterface.tokenize();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        outputContent.innerHTML = `<div class="sexp-output">${result.data || "No tokens"}</div>`;
      } else {
        outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get tokens")}</div>`;
      }
    } catch (error) {
      this.showError(`Failed to get tokens: ${error.message}`);
    }
  }

  async showParseAst() {
    currentView = "AST";
    this.updateStageButtons();

    try {
      const result = await wasmInterface.parse();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        outputContent.innerHTML = `<div class="sexp-output">${result.data || "No AST"}</div>`;
      } else {
        outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get AST")}</div>`;
      }
    } catch (error) {
      this.showError(`Failed to get AST: ${error.message}`);
    }
  }

  async showCanCir() {
    currentView = "CIR";
    this.updateStageButtons();

    try {
      const result = await wasmInterface.canonicalize();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        outputContent.innerHTML = `<div class="sexp-output">${result.data || "No CIR"}</div>`;
      } else {
        outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get CIR")}</div>`;
      }
    } catch (error) {
      this.showError(`Failed to get CIR: ${error.message}`);
    }
  }

  async showTypes() {
    currentView = "TYPES";
    this.updateStageButtons();

    try {
      const result = await wasmInterface.getTypes();

      const outputContent = document.getElementById("outputContent");
      if (result.status === "SUCCESS") {
        outputContent.innerHTML = `<div class="sexp-output">${result.data || "No types"}</div>`;
      } else {
        outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(result.message || "Failed to get types")}</div>`;
      }
    } catch (error) {
      this.showError(`Failed to get types: ${error.message}`);
    }
  }

  updateStageButtons() {
    const buttons = document.querySelectorAll(".stage-button");
    buttons.forEach((button) => {
      button.classList.remove("active");
    });

    const activeButton = document.getElementById(this.getButtonId(currentView));
    if (activeButton) {
      activeButton.classList.add("active");
    }
  }

  getButtonId(view) {
    const mapping = {
      PROBLEMS: "diagnosticsBtn",
      TOKENS: "tokensBtn",
      AST: "parseBtn",
      CIR: "canBtn",
      TYPES: "typesBtn",
    };
    return mapping[view] || "diagnosticsBtn";
  }

  updateDiagnosticSummary() {
    const editorHeader = document.querySelector(".editor-header");
    let summary = editorHeader.querySelector(".diagnostic-summary");

    if (!summary) {
      summary = document.createElement("div");
      summary.className = "diagnostic-summary";
      editorHeader.appendChild(summary);
    }

    // Use summary from WASM result if available
    if (
      this.lastCompileResult &&
      this.lastCompileResult.diagnostics &&
      this.lastCompileResult.diagnostics.summary
    ) {
      const diagnosticSummary = this.lastCompileResult.diagnostics.summary;
      const errorCount = diagnosticSummary.errors;
      const warningCount = diagnosticSummary.warnings;

      if (errorCount === 0 && warningCount === 0) {
        summary.innerHTML =
          '<span class="success-message">✓ No problems</span>';
      } else {
        summary.innerHTML = `
          ${errorCount > 0 ? `<span class="error-count">${errorCount} error${errorCount > 1 ? "s" : ""}</span>` : ""}
          ${warningCount > 0 ? `<span class="warning-count">${warningCount} warning${warningCount > 1 ? "s" : ""}</span>` : ""}
        `;
      }
    } else {
      // Fallback to counting diagnostics
      const errorCount = lastDiagnostics.filter(
        (d) => d.severity === "error",
      ).length;
      const warningCount = lastDiagnostics.filter(
        (d) => d.severity === "warning",
      ).length;

      if (errorCount === 0 && warningCount === 0) {
        summary.innerHTML =
          '<span class="success-message">✓ No problems</span>';
      } else {
        summary.innerHTML = `
          ${errorCount > 0 ? `<span class="error-count">${errorCount} error${errorCount > 1 ? "s" : ""}</span>` : ""}
          ${warningCount > 0 ? `<span class="warning-count">${warningCount} warning${warningCount > 1 ? "s" : ""}</span>` : ""}
        `;
      }
    }
  }

  setupResizeHandle() {
    const resizeHandle = document.getElementById("resizeHandle");
    const editorContainer = document.querySelector(".editor-container");
    const outputContainer = document.querySelector(".output-container");

    resizeHandle.addEventListener("mousedown", (e) => {
      this.isResizing = true;
      this.startX = e.clientX;
      this.startWidthLeft = editorContainer.offsetWidth;
      this.startWidthRight = outputContainer.offsetWidth;

      document.addEventListener("mousemove", this.handleMouseMove.bind(this));
      document.addEventListener("mouseup", this.handleMouseUp.bind(this));
    });
  }

  handleMouseMove(e) {
    if (!this.isResizing) return;

    const deltaX = e.clientX - this.startX;
    const newLeftWidth = this.startWidthLeft + deltaX;
    const newRightWidth = this.startWidthRight - deltaX;

    if (newLeftWidth > 200 && newRightWidth > 200) {
      document.querySelector(".editor-container").style.flex =
        `0 0 ${newLeftWidth}px`;
      document.querySelector(".output-container").style.flex =
        `0 0 ${newRightWidth}px`;
    }
  }

  handleMouseUp() {
    this.isResizing = false;
    document.removeEventListener("mousemove", this.handleMouseMove);
    document.removeEventListener("mouseup", this.handleMouseUp);
  }

  setupUrlSharing() {
    // URL sharing functionality
    window.addEventListener("hashchange", () => {
      this.restoreFromHash();
    });

    this.addShareButton();
  }

  async updateUrlWithCompressedContent() {
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

  async restoreFromHash() {
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

  async compressAndEncode(text) {
    // Use simple base64 encoding for better browser support
    // TODO: Add compression later with a polyfill
    const encoder = new TextEncoder();
    const data = encoder.encode(text);
    return this.uint8ToBase64(data);
  }

  async decodeAndDecompress(base64) {
    // Use simple base64 decoding for better browser support
    // TODO: Add decompression later with a polyfill
    const data = this.base64ToUint8(base64);
    return new TextDecoder().decode(data);
  }

  uint8ToBase64(uint8Array) {
    return btoa(String.fromCharCode(...uint8Array));
  }

  base64ToUint8(base64) {
    return new Uint8Array(
      atob(base64)
        .split("")
        .map((c) => c.charCodeAt(0)),
    );
  }

  initTheme() {
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
    themeSwitch.addEventListener("click", () => {
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

  toggleTheme() {
    const currentTheme = document.documentElement.getAttribute("data-theme");
    const newTheme = currentTheme === "dark" ? "light" : "dark";

    document.documentElement.setAttribute("data-theme", newTheme);
    localStorage.setItem("theme", newTheme);
    this.updateThemeLabel();
  }

  updateThemeLabel() {
    const themeLabel = document.querySelector(".theme-label");
    const currentTheme = document.documentElement.getAttribute("data-theme");
    themeLabel.textContent = currentTheme === "dark" ? "Dark" : "Light";
  }

  setStatus(message) {
    const outputContent = document.getElementById("outputContent");
    outputContent.innerHTML = `<div class="status-text">${message}</div>`;
  }

  showError(message) {
    const outputContent = document.getElementById("outputContent");
    outputContent.innerHTML = `<div class="error-message">${this.escapeHtml(message)}</div>`;
  }

  escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  parseDiagnostics(result) {
    // Parse diagnostics from WASM result
    const diagnostics = [];

    if (result.diagnostics && result.diagnostics.summary) {
      const summary = result.diagnostics.summary;

      if (summary.errors > 0) {
        diagnostics.push({
          severity: "error",
          message: `${summary.errors} error${summary.errors > 1 ? "s" : ""}`,
          location: "compilation",
        });
      }

      if (summary.warnings > 0) {
        diagnostics.push({
          severity: "warning",
          message: `${summary.warnings} warning${summary.warnings > 1 ? "s" : ""}`,
          location: "compilation",
        });
      }
    }

    // If no specific errors, return empty array (no problems)
    return diagnostics;
  }

  addShareButton() {
    const headerStatus = document.querySelector(".header-status");
    if (headerStatus) {
      let shareButton = headerStatus.querySelector(".share-button");
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

  async copyShareLink() {
    if (codeMirrorEditor) {
      const content = getDocumentContent(codeMirrorEditor).trim();
      if (content) {
        try {
          const b64 = await this.compressAndEncode(content);
          const shareUrl = `${window.location.origin}${window.location.pathname}#content=${b64}`;
          await navigator.clipboard.writeText(shareUrl);

          // Show temporary feedback
          const shareButton = document.querySelector(".share-button");
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
window.showDiagnostics = () => playground.showDiagnostics();
window.showTokens = () => playground.showTokens();
window.showParseAst = () => playground.showParseAst();
window.showCanCir = () => playground.showCanCir();
window.showTypes = () => playground.showTypes();

// Initialize playground when DOM is ready
let playground;

document.addEventListener("DOMContentLoaded", () => {
  playground = new RocPlayground();
  playground.initialize();
});
