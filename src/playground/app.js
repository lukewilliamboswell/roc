// Global state
let wasmModule = null;
let wasmMemory = null;
let currentState = "START";
let currentView = "diagnostics";
let lastDiagnostics = null;
let activeExample = null;
let lastCompileTime = null;
let updateUrlTimeout = null;
let codeMirrorEditor = null;

// Example modules
const examples = [
  {
    id: "hello-world",
    title: "Hello World",
    description: "Hello World application example",
    code: `app [main!] { pf: platform \"../basic-cli/platform.roc\" }

import pf.Stdout

main! = |_| Stdout.line!(\"Hello, world!\")`,
  },
  {
    id: "basic-types",
    title: "Basic Types",
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

// Initialize the playground
async function initializePlayground() {
  logInfo("Initializing playground...");
  try {
    logInfo("Loading WASM module...");
    await loadWasm();
    logInfo("WASM module loaded successfully");

    logInfo("Sending INIT message to WASM...");
    const response = await sendMessageQueued({ type: "INIT" });
    logInfo("INIT response:", response);

    if (response.status !== "SUCCESS") {
      throw new Error(
        `WASM initialization failed: ${response.message || "Unknown error"}`,
      );
    }

    logInfo("Initializing CodeMirror...");
    const editorElement = document.getElementById("editor");
    codeMirrorEditor = CodeMirror(editorElement, {
      mode: "roc",
      lineNumbers: true,
      matchBrackets: true,
      indentUnit: 4,
      tabSize: 4,
      lineWrapping: true,
      placeholder:
        "# Select an example from the footer or write your own Roc code here...",
      theme: "default",
    });

    // Setup tooltips after a delay to ensure all CodeMirror addons are loaded
    setTimeout(() => {
      setupTooltips();
    }, 100);

    logInfo("Populating examples...");
    populateExamples();
    logInfo("Updating UI...");
    updateUI();
    clearDiagnosticSummary();
    lastCompileTime = null;
    setupAutoCompile();
    setupUrlSharing();
    currentState = "READY";
    await restoreFromHash();
    logInfo("Playground initialization complete!");
  } catch (error) {
    logError("❌ Failed to initialize playground:", error);
    showError(`Failed to initialize playground: ${error.message}`);
  }
}

// Load WASM module
async function loadWasm() {
  try {
    logInfo("Fetching WASM file...");
    const response = await fetch("playground.wasm");
    logInfo("WASM fetch response status:", response.status);

    if (!response.ok) {
      throw new Error(
        `Failed to fetch WASM file: ${response.status} ${response.statusText}`,
      );
    }

    logInfo("Converting to array buffer...");
    const bytes = await response.arrayBuffer();
    logInfo("WASM file size:", bytes.byteLength, "bytes");

    if (bytes.byteLength === 0) {
      throw new Error("WASM file is empty");
    }

    logInfo("Instantiating WASM module...");
    const module = await WebAssembly.instantiate(bytes, {
      env: {
        // Add any required imports here
      },
    });
    logInfo("WASM module instantiated");

    wasmModule = module.instance.exports;
    wasmMemory = wasmModule.memory;
    logInfo("WASM memory size:", wasmMemory.buffer.byteLength, "bytes");
    logInfo("Available WASM exports:", Object.keys(wasmModule));

    // Verify required exports are present
    const requiredExports = [
      "init",
      "processMessage",
      "allocate",
      "deallocate",
    ];
    for (const exportName of requiredExports) {
      if (typeof wasmModule[exportName] !== "function") {
        throw new Error(`Missing required WASM export: ${exportName}`);
      }
    }

    logInfo("Calling WASM init()...");
    wasmModule.init();
    logInfo("WASM init() completed");

    const outputContent = document.getElementById("outputContent");
    outputContent.innerHTML = "Ready to compile!";
    outputContent.classList.add("status-text");
  } catch (error) {
    logError("Error loading WASM:", error);
    throw new Error(`Failed to load WASM module: ${error.message}`);
  }
}

// Send message to WASM module
async function sendMessage(message) {
  if (!wasmModule) {
    throw new Error("WASM module not loaded");
  }

  logInfo("Sending message to WASM:", message);

  let messagePtr = null;
  let responsePtr = null;
  let messageBytes = null;

  try {
    const messageStr = JSON.stringify(message);
    messageBytes = new TextEncoder().encode(messageStr);
    logInfo("Message size:", messageBytes.length, "bytes");

    // Allocate memory for message
    logInfo("Allocating message memory...");
    messagePtr = wasmModule.allocate(messageBytes.length);
    if (!messagePtr) {
      throw new Error("Failed to allocate message memory");
    }

    const memory = new Uint8Array(wasmMemory.buffer);
    memory.set(messageBytes, messagePtr);
    logInfo("Message pointer:", messagePtr);

    // Allocate memory for response
    logInfo("Allocating response memory...");
    const responseBufferSize = 64 * 1024; // 64KB buffer
    responsePtr = wasmModule.allocate(responseBufferSize);
    if (!responsePtr) {
      throw new Error("Failed to allocate response memory");
    }
    logInfo("Response pointer:", responsePtr);

    // Process message
    logInfo("Processing message in WASM...");
    const responseLen = wasmModule.processMessage(
      messagePtr,
      messageBytes.length,
      responsePtr,
      responseBufferSize,
    );
    logInfo("Response length:", responseLen, "bytes");

    if (responseLen === 0) {
      throw new Error("WASM returned empty response");
    }

    // Read response
    const responseBytes = new Uint8Array(
      wasmMemory.buffer,
      responsePtr,
      responseLen,
    );
    const responseStr = new TextDecoder().decode(responseBytes);
    logInfo("Raw response:", responseStr);

    if (!responseStr.trim()) {
      throw new Error("WASM returned empty response string");
    }

    let parsedResponse;
    try {
      parsedResponse = JSON.parse(responseStr);
    } catch (jsonError) {
      logError("❌ JSON parse error:", jsonError);
      throw new Error(
        `Invalid JSON response from WASM: ${responseStr.substring(0, 100)}...`,
      );
    }

    logInfo("Parsed response:", parsedResponse);
    return parsedResponse;
  } catch (error) {
    logError("Error in sendMessage:", error);
    throw error;
  } finally {
    // Clean up memory
    if (messagePtr && wasmModule.deallocate && messageBytes) {
      wasmModule.deallocate(messagePtr, messageBytes.length);
    }
    if (responsePtr && wasmModule.deallocate) {
      wasmModule.deallocate(responsePtr, 64 * 1024);
    }
    logInfo("Memory cleaned up");
  }
}

// --- BEGIN QUEUED SENDMESSAGE SYSTEM ---
// Queue for serializing sendMessage calls
const sendMessageQueue = [];
let sendMessageInProgress = false;

const sendMessageOriginal = sendMessage;

async function processSendMessageQueue() {
  if (sendMessageInProgress) return;
  if (sendMessageQueue.length === 0) return;
  sendMessageInProgress = true;
  const { message, resolve, reject } = sendMessageQueue.shift();
  try {
    const result = await sendMessageOriginal(message);
    resolve(result);
  } catch (err) {
    reject(err);
  } finally {
    sendMessageInProgress = false;
    processSendMessageQueue();
  }
}

function sendMessageQueued(message) {
  return new Promise((resolve, reject) => {
    sendMessageQueue.push({ message, resolve, reject });
    processSendMessageQueue();
  });
}
// --- END QUEUED SENDMESSAGE SYSTEM ---

// Populate examples list
function populateExamples() {
  const examplesList = document.getElementById("examplesList");
  examplesList.innerHTML = "";

  examples.forEach((example) => {
    const item = document.createElement("div");
    item.className = "example-item";
    item.dataset.exampleId = example.id;
    item.onclick = () => loadExample(example.id);

    item.innerHTML = `
            <div class="example-title">${example.title}</div>
            <div class="example-description">${example.description}</div>
        `;

    examplesList.appendChild(item);
  });
}

// Load an example
async function loadExample(exampleId) {
  logInfo("Loading example:", exampleId);
  // Reset the URL hash when loading an example
  window.location.hash = "";
  const example = examples.find((e) => e.id === exampleId);
  if (!example) {
    logWarn("Example not found:", exampleId);
    return;
  }

  // Update the URL hash to match the loaded example's content
  await updateUrlWithCompressedContent(example.code);

  // Update UI
  logInfo("Updating example selection UI...");
  document.querySelectorAll(".example-item").forEach((item) => {
    item.classList.remove("active");
  });
  const activeItem = document.querySelector(`[data-example-id="${exampleId}"]`);
  if (activeItem) {
  } else {
    logWarn("Could not find example item in DOM");
  }

  // Load code into editor
  logInfo("Loading code into editor...");
  codeMirrorEditor.setValue(example.code);
  activeExample = exampleId;

  // Reset if we're in loaded state
  if (currentState === "LOADED") {
    logInfo("Resetting WASM state...");
    await sendMessageQueued({ type: "RESET" });
  }

  updateUI();
  logInfo("Example loaded successfully");

  // Compile the example immediately
  await compileCode();
}

// Compile code
async function compileCode() {
  logInfo("Starting compilation...");
  const code = codeMirrorEditor.getValue().trim();
  logInfo("Code length:", code.length, "characters");

  if (!code) {
    logWarn("No code to compile");
    showError("Please enter some code to compile");
    return;
  }

  // Start timing if not already set (for manual compile)
  if (!compileStartTime) {
    compileStartTime = performance.now();
  }
  const startTime = compileStartTime;

  try {
    logInfo("Beginning compilation process...");
    setStatus("loading", "Compiling...");

    // Reset if we're already in LOADED state
    if (currentState === "LOADED") {
      logInfo("Resetting WASM state before recompilation...");
      await sendMessageQueued({ type: "RESET" });
    }

    const response = await sendMessageQueued({
      type: "LOAD_SOURCE",
      source: code,
    });

    if (response.status === "SUCCESS") {
      logInfo("Compilation successful");
      currentState = "LOADED";
      lastDiagnostics = response.diagnostics;
      logInfo("Diagnostics:", lastDiagnostics);

      // Set timing before updating diagnostic summary
      lastCompileTime = performance.now() - startTime;
      compileStartTime = null; // Reset for next compilation

      updateDiagnosticSummary();

      // Preserve current view instead of always showing diagnostics
      switch (currentView) {
        case "diagnostics":
          showDiagnostics();
          break;
        case "tokens":
          showTokens();
          break;
        case "parse":
          showParseAst();
          break;
        case "can":
          showCanCir();
          break;
        case "types":
          showTypes();
          break;
        default:
          showDiagnostics();
      }
    } else {
      logError("❌ Compilation failed:", response.message);
      lastCompileTime = performance.now() - startTime;
      compileStartTime = null; // Reset for next compilation
      setStatus("error", "Compilation failed");
      clearDiagnosticSummary();
      showError(`Compilation failed: ${response.message}`);
    }
  } catch (error) {
    logError("Error during compilation:", error);
    const errorMessage = error.message || error.toString() || "Unknown error";
    lastCompileTime = performance.now() - startTime;
    setStatus("error", "Compilation error");
    clearDiagnosticSummary();
    showError(`Error during compilation: ${errorMessage}`);
  } finally {
    updateUI();
    logInfo("Compilation process finished");
  }
}

// Show diagnostics
function showDiagnostics() {
  currentView = "diagnostics";
  updateStageButtons();

  if (!lastDiagnostics) {
    showMessage("Compile code first to view PROBLEMS");
    return;
  }

  const outputContent = document.getElementById("outputContent");

  // Check if we have the new HTML format
  if (lastDiagnostics.html !== undefined) {
    // Use the HTML-rendered diagnostics directly
    if (lastDiagnostics.html.trim() === "") {
      outputContent.innerHTML =
        '<div class="success-message">NIL PROBLEMS</div>';
    } else {
      outputContent.innerHTML = lastDiagnostics.html;
    }
  } else {
    // Fallback to old format for compatibility
    let html = "";
    let totalErrors = 0;
    let totalWarnings = 0;

    // Count total diagnostics
    Object.values(lastDiagnostics).forEach((stageDiagnostics) => {
      stageDiagnostics.forEach((diagnostic) => {
        if (
          diagnostic.severity === "error" ||
          diagnostic.severity === "fatal"
        ) {
          totalErrors++;
        } else if (diagnostic.severity === "warning") {
          totalWarnings++;
        }
      });
    });

    // Show summary
    if (totalErrors === 0 && totalWarnings === 0) {
      html += '<div class="success-message">NIL PROBLEMS</div>';
    } else {
      html += `<div class="diagnostic-summary">
              Found ${totalErrors} error(s) and ${totalWarnings} warning(s)
          </div>`;
    }

    // Show diagnostics by stage
    Object.entries(lastDiagnostics).forEach(([stage, diagnostics]) => {
      if (diagnostics.length > 0) {
        html += `<div class="diagnostic-stage">
                      <div class="diagnostic-stage-title">${stage.toUpperCase()}</div>`;

        diagnostics.forEach((diagnostic) => {
          html += `<div class="diagnostic ${diagnostic.severity}">
                          <div class="diagnostic-severity">${diagnostic.severity.toUpperCase()}</div>
                          <div class="diagnostic-message">${escapeHtml(diagnostic.title)}</div>
                      </div>`;
        });

        html += "</div>";
      }
    });

    outputContent.innerHTML = html;
  }
}

// Show tokens
async function showTokens() {
  currentView = "tokens";
  updateStageButtons();

  if (currentState !== "LOADED") {
    showMessage("Compile code first to view TOKENS");
    return;
  }

  try {
    const response = await sendMessageQueued({
      type: "QUERY_TOKENS",
    });
    if (response.status === "SUCCESS") {
      showSExpression(response.data);
    } else {
      showError(`Failed to get tokens: ${response.message}`);
    }
  } catch (error) {
    logError("❌ Failed to query tokens:", error);
    showError(`Failed to query tokens: ${error.message}`);
  }
}

// Show parse AST
async function showParseAst() {
  currentView = "parse";
  updateStageButtons();

  if (currentState !== "LOADED") {
    showMessage("Compile code first to view AST");
    return;
  }

  try {
    const response = await sendMessageQueued({
      type: "QUERY_AST",
    });
    if (response.status === "SUCCESS") {
      showSExpression(response.data);
    } else {
      showError(`Failed to get AST: ${response.message}`);
    }
  } catch (error) {
    logError("❌ Failed to query AST:", error);
    showError(`Failed to query AST: ${error.message}`);
  }
}

// Show CIR
async function showCanCir() {
  currentView = "can";
  updateStageButtons();

  if (currentState !== "LOADED") {
    showMessage("Compile code first to view CIR");
    return;
  }

  try {
    const response = await sendMessageQueued({
      type: "QUERY_CIR",
    });
    if (response.status === "SUCCESS") {
      showSExpression(response.data);
    } else {
      showError(`Failed to get CIR: ${response.message}`);
    }
  } catch (error) {
    logError("❌ Failed to query CIR:", error);
    showError(`Failed to query CIR: ${error.message}`);
  }
}

// Show types
async function showTypes() {
  currentView = "types";
  updateStageButtons();

  if (currentState !== "LOADED") {
    showMessage("Compile code first to view TYPES");
    return;
  }

  try {
    const response = await sendMessageQueued({
      type: "QUERY_TYPES",
    });
    if (response.status === "SUCCESS") {
      showSExpression(response.data);
    } else {
      showError(`Failed to get types: ${response.message}`);
    }
  } catch (error) {
    logError("❌ Failed to query types:", error);
    showError(`Failed to query types: ${error.message}`);
  }
}

function showSExpression(sexp) {
  const outputContent = document.getElementById("outputContent");

  // Display the HTML S-expression directly
  outputContent.innerHTML = `<pre class="sexp-output">${sexp}</pre>`;
}

// Show error message
function showError(message) {
  const outputContent = document.getElementById("outputContent");
  outputContent.innerHTML = `<div class="error-message">${escapeHtml(message)}</div>`;
}

// Show general message
function showMessage(message) {
  const outputContent = document.getElementById("outputContent");
  outputContent.innerHTML = `<div class="loading">${escapeHtml(message)}</div>`;
}

// Update status indicator
function setStatus(status, text) {
  const statusDot = document.getElementById("statusDot");
  const statusText = document.getElementById("statusText");

  if (statusDot) {
    statusDot.className = `status-dot ${status}`;
  }
  if (statusText) {
    statusText.textContent = text;
  }

  if (status === "loaded") {
    currentState = "LOADED";
  }
}

// Update UI based on current state
function updateUI() {
  updateStageButtons();

  // Update stage buttons based on current state
  if (currentState !== "LOADED") {
    // Disable stage buttons when not loaded
    document.querySelectorAll(".stage-button").forEach((btn) => {
      if (btn.id !== "diagnosticsBtn") {
        btn.disabled = true;
      }
    });
  } else {
    // Enable all stage buttons when loaded
    document.querySelectorAll(".stage-button").forEach((btn) => {
      btn.disabled = false;
    });
  }
}

// Update stage buttons
function updateStageButtons() {
  document.querySelectorAll(".stage-button").forEach((btn) => {
    btn.classList.remove("active");
  });

  const activeBtn = {
    diagnostics: "diagnosticsBtn",
    tokens: "tokensBtn",
    parse: "parseBtn",
    can: "canBtn",
    types: "typesBtn",
  }[currentView];

  if (activeBtn) {
    document.getElementById(activeBtn).classList.add("active");
  }
}

// Clear diagnostic summary from header
function clearDiagnosticSummary() {
  const editorHeader = document.querySelector(".editor-header");
  const existingSummary = editorHeader.querySelector(".diagnostic-summary");
  if (existingSummary) {
    existingSummary.remove();
  }
}

// Update diagnostic summary in header
function updateDiagnosticSummary() {
  const editorHeader = document.querySelector(".editor-header");

  // Remove existing diagnostic summary
  const existingSummary = editorHeader.querySelector(".diagnostic-summary");
  if (existingSummary) {
    existingSummary.remove();
  }

  if (!lastDiagnostics) {
    return;
  }

  let totalErrors = 0;
  let totalWarnings = 0;

  // Check if we have the new format with summary
  if (lastDiagnostics.summary) {
    totalErrors = lastDiagnostics.summary.errors;
    totalWarnings = lastDiagnostics.summary.warnings;
  } else {
    // Fallback to old format counting
    Object.values(lastDiagnostics).forEach((stageDiagnostics) => {
      if (Array.isArray(stageDiagnostics)) {
        stageDiagnostics.forEach((diagnostic) => {
          if (
            diagnostic.severity === "error" ||
            diagnostic.severity === "fatal"
          ) {
            totalErrors++;
          } else if (diagnostic.severity === "warning") {
            totalWarnings++;
          }
        });
      }
    });
  }

  // Always show summary after compilation (when timing info is available)
  if (lastCompileTime !== null) {
    const summaryDiv = document.createElement("div");
    summaryDiv.className = "diagnostic-summary";

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
    editorHeader.appendChild(summaryDiv);
  }
}

// Auto-compile setup
let compileTimeout;
let compileStartTime = null;

function setupAutoCompile() {
  if (codeMirrorEditor) {
    codeMirrorEditor.on("change", () => {
      // Debounce compilation to avoid excessive calls
      clearTimeout(compileTimeout);
      compileStartTime = performance.now(); // Start timing when user stops typing
      compileTimeout = setTimeout(() => {
        if (currentState === "READY" || currentState === "LOADED") {
          compileCode();
        }
      }, 20); // 20ms delay for better responsiveness
    });
  }
}

// URL sharing functionality (gzip + base64 + hash fragment)
async function compressAndEncode(content) {
  // Compress using gzip (CompressionStream)
  const encoder = new TextEncoder();
  const input = encoder.encode(content);
  const cs = new CompressionStream("gzip");
  const compressedStream = new Response(
    new Blob([input]).stream().pipeThrough(cs),
  ).arrayBuffer();
  const compressed = new Uint8Array(await compressedStream);
  return uint8ToBase64(compressed);
}

async function decodeAndDecompress(b64) {
  const compressed = base64ToUint8(b64);
  const ds = new DecompressionStream("gzip");
  const decompressedStream = new Response(
    new Blob([compressed]).stream().pipeThrough(ds),
  ).arrayBuffer();
  const decompressed = new Uint8Array(await decompressedStream);
  const decoder = new TextDecoder();
  return decoder.decode(decompressed);
}

function uint8ToBase64(uint8) {
  // Convert Uint8Array to base64 (browser safe)
  let binary = "";
  for (let i = 0; i < uint8.length; i++) {
    binary += String.fromCharCode(uint8[i]);
  }
  return btoa(binary);
}

function base64ToUint8(b64) {
  const binary = atob(b64);
  const uint8 = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    uint8[i] = binary.charCodeAt(i);
  }
  return uint8;
}

async function updateUrlWithCompressedContent(content) {
  if (!content || content.length > 10000) {
    // Don't share very large content
    window.location.hash = "";
    return;
  }
  const b64 = await compressAndEncode(content);
  window.location.hash = `content=${b64}`;
}

async function restoreFromHash() {
  // Expect hash in the form #content=...
  const hash = window.location.hash.replace(/^#/, "");
  logInfo(`Attempting to restore from hash: ${hash.substring(0, 50)}...`);

  let b64 = null;
  if (hash.startsWith("content=")) {
    b64 = hash.slice("content=".length);
    logInfo(`Extracted base64 content: ${b64.substring(0, 50)}...`);
  }

  if (b64) {
    try {
      const content = await decodeAndDecompress(b64);
      logInfo(`Decompressed content: ${content.substring(0, 100)}...`);

      if (codeMirrorEditor) {
        codeMirrorEditor.setValue(content);
        logInfo("Restored content from hash fragment");

        // Wait for the playground to be ready before compiling
        if (currentState === "READY") {
          await compileCode(); // Automatically compile after restoring
        } else {
          logInfo("Playground not ready, skipping auto-compile");
        }
      } else {
        logError("CodeMirror editor not found");
      }
    } catch (e) {
      logError("Failed to decompress content from hash", e);
    }
  } else {
    logInfo("No content found in hash");
  }
}

function setupUrlSharing() {
  const editor = document.getElementById("editor");
  if (editor) {
    editor.addEventListener("input", () => {
      clearTimeout(updateUrlTimeout);
      updateUrlTimeout = setTimeout(() => {
        updateUrlWithCompressedContent(editor.value);
      }, 1000); // Update URL after 1 second of no typing
    });
  }

  // Listen for hash changes (when someone pastes a new URL)
  window.addEventListener("hashchange", async () => {
    logInfo("Hash changed, attempting to restore content");
    await restoreFromHash();
  });

  addShareButton();
}

function addShareButton() {
  const headerStatus = document.querySelector(".header-status");
  if (headerStatus) {
    let shareButton = headerStatus.querySelector(".share-button");
    if (!shareButton) {
      shareButton = document.createElement("button");
      shareButton.className = "share-button";
      shareButton.innerHTML = "share link";
      shareButton.title = "Copy shareable link to clipboard";
      shareButton.onclick = copyShareLink;
      const themeToggle = headerStatus.querySelector(".theme-toggle");
      headerStatus.insertBefore(shareButton, themeToggle);
    }
  }
}

async function copyShareLink() {
  if (codeMirrorEditor) {
    const content = codeMirrorEditor.getValue().trim();
    if (content) {
      try {
        const b64 = await compressAndEncode(content);
        const shareUrl = `${window.location.origin}${window.location.pathname}#content=${b64}`;
        await navigator.clipboard.writeText(shareUrl);
        // Show temporary feedback
        const shareButton = document.querySelector(".share-button");
        const originalText = shareButton.innerHTML;
        shareButton.innerHTML = "copied";
        setTimeout(() => {
          shareButton.innerHTML = originalText;
        }, 2000);
      } catch (err) {
        console.error("Failed to copy to clipboard:", err);
        alert("Failed to copy link");
      }
    } else {
      alert("No content to share");
    }
  }
}

// Utility functions
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// Handle keyboard shortcuts
document.addEventListener("keydown", function (e) {
  if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
    e.preventDefault();
    compileCode();
  }
});

// Handle resizable panels
let isResizing = false;
let startX = 0;
let startWidthLeft = 0;
let startWidthRight = 0;

const resizeHandle = document.getElementById("resizeHandle");
const editorContainer = document.querySelector(".editor-container");
const outputContainer = document.querySelector(".output-container");

resizeHandle.addEventListener("mousedown", (e) => {
  isResizing = true;
  startX = e.clientX;
  startWidthLeft = editorContainer.offsetWidth;
  startWidthRight = outputContainer.offsetWidth;
  document.body.style.cursor = "col-resize";
  e.preventDefault();
});

document.addEventListener("mousemove", (e) => {
  if (!isResizing) return;

  const diff = e.clientX - startX;
  const newWidthLeft = startWidthLeft + diff;
  const newWidthRight = startWidthRight - diff;

  // Enforce minimum widths
  if (newWidthLeft >= 300 && newWidthRight >= 300) {
    editorContainer.style.flex = `0 0 ${newWidthLeft}px`;
    outputContainer.style.flex = `0 0 ${newWidthRight}px`;
  }
});

document.addEventListener("mouseup", () => {
  if (isResizing) {
    isResizing = false;
    document.body.style.cursor = "default";
  }
});

// Theme handling
function initTheme() {
  const savedTheme = localStorage.getItem("theme");
  const systemPrefersDark = window.matchMedia(
    "(prefers-color-scheme: dark)",
  ).matches;

  // Use saved theme, or fall back to system preference (no data-theme attribute)
  if (savedTheme) {
    document.documentElement.setAttribute("data-theme", savedTheme);
  } else {
    // Remove data-theme attribute to use system preference
    document.documentElement.removeAttribute("data-theme");

    // Listen for system preference changes only if no manual theme is set
    const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    mediaQuery.addEventListener("change", handleSystemThemeChange);
  }

  // Update theme switch state
  const themeSwitch = document.getElementById("themeSwitch");
  const currentTheme = savedTheme || (systemPrefersDark ? "dark" : "light");
  themeSwitch.setAttribute("aria-checked", currentTheme === "dark");

  // Update theme label text
  updateThemeLabel(currentTheme);
}

function toggleTheme() {
  const currentTheme = document.documentElement.getAttribute("data-theme");
  const systemPrefersDark = window.matchMedia(
    "(prefers-color-scheme: dark)",
  ).matches;

  // Determine current effective theme
  const effectiveTheme = currentTheme || (systemPrefersDark ? "dark" : "light");
  const newTheme = effectiveTheme === "dark" ? "light" : "dark";

  // Remove system preference listener since user is now manually setting theme
  const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
  mediaQuery.removeEventListener("change", handleSystemThemeChange);

  document.documentElement.setAttribute("data-theme", newTheme);
  localStorage.setItem("theme", newTheme);

  const themeSwitch = document.getElementById("themeSwitch");
  themeSwitch.setAttribute("aria-checked", newTheme === "dark");

  // Update theme label text
  updateThemeLabel(newTheme);
}

function handleSystemThemeChange(e) {
  // Only respond to system changes if no manual theme is set
  if (!localStorage.getItem("theme")) {
    // Update UI to reflect new system preference
    const themeSwitch = document.getElementById("themeSwitch");
    themeSwitch.setAttribute("aria-checked", e.matches);
    updateThemeLabel(e.matches ? "dark" : "light");
  }
}

function updateThemeLabel(theme) {
  const themeLabel = document.querySelector(".theme-label");
  if (themeLabel) {
    themeLabel.textContent = theme === "dark" ? "Dark" : "Light";
  }
}

function logInfo(...args) {
  console.log("INFO:", ...args);
}

function logWarn(...args) {
  console.warn("WARNING:", ...args);
}

function logError(...args) {
  console.error("ERROR:", ...args);
}

// === TOOLTIP FUNCTIONALITY ===

let tooltipElement = null;
let tooltipTimeout = null;
let isTooltipVisible = false;

function setupTooltips() {
  if (!codeMirrorEditor) {
    logWarn("CodeMirror editor not available for tooltips");
    return;
  }

  logInfo("Setting up tooltips...");

  // Create tooltip element
  tooltipElement = document.createElement("div");
  tooltipElement.className = "CodeMirror-tooltip";
  document.body.appendChild(tooltipElement);

  // Add mouse event listeners
  const editorElement = codeMirrorEditor.getWrapperElement();
  editorElement.addEventListener("mousemove", handleMouseMove);
  editorElement.addEventListener("mouseleave", hideTooltip);

  logInfo("Tooltips setup complete");
}

function handleMouseMove(event) {
  if (!codeMirrorEditor || !tooltipElement) return;

  // Clear any existing timeout
  if (tooltipTimeout) {
    clearTimeout(tooltipTimeout);
    tooltipTimeout = null;
  }

  // Get the position in the editor
  const pos = codeMirrorEditor.coordsChar({
    left: event.clientX,
    top: event.clientY,
  });
  if (!pos) return;

  // Add delay before showing tooltip
  tooltipTimeout = setTimeout(() => {
    showTooltipForPosition(pos, event.clientX, event.clientY);
  }, 300); // 300ms delay
}

async function showTooltipForPosition(pos, clientX, clientY) {
  if (!codeMirrorEditor || !tooltipElement) return;

  try {
    // Get the token at the cursor position
    const token = codeMirrorEditor.getTokenAt(pos);
    if (!token || !token.string || token.string.trim() === "") return;

    // Only show tooltips for identifiers (not keywords, strings, etc.)
    if (
      token.type &&
      (token.type.includes("keyword") ||
        token.type.includes("string") ||
        token.type.includes("number") ||
        token.type.includes("comment"))
    ) {
      return;
    }

    // Also skip if the token is too short or looks like punctuation
    if (token.string.length < 2 || /^[^a-zA-Z_]/.test(token.string)) {
      return;
    }

    // Get type information from WASM
    const typeInfo = await getTypeInformation(token.string, pos);
    if (!typeInfo) return;

    // Show the tooltip
    displayTooltip(typeInfo, clientX, clientY);
  } catch (error) {
    logError("Error showing tooltip:", error);
  }
}

async function getTypeInformation(identifier, pos) {
  if (!wasmModule || !codeMirrorEditor) return null;

  try {
    // Only provide type information if we have compiled code
    if (currentState !== "LOADED") {
      return null;
    }

    // Send GET_TYPE_INFO message to WASM with position information
    const response = await sendMessageQueued({
      type: "GET_TYPE_INFO",
      identifier: identifier,
      line: pos.line,
      ch: pos.ch,
    });

    if (response.status === "SUCCESS" && response.type_info) {
      return response.type_info;
    }
  } catch (error) {
    logError("Error getting type information:", error);
  }

  return null;
}

function displayTooltip(typeInfo, clientX, clientY) {
  if (!tooltipElement) return;

  // Format the tooltip content
  let content = "";
  if (typeInfo.type) {
    content += `<span class="type-info">${escapeHtml(typeInfo.type)}</span>`;
  }
  if (typeInfo.error) {
    content += `<span class="error-info">${escapeHtml(typeInfo.error)}</span>`;
  }
  if (typeInfo.description) {
    content += `\n${escapeHtml(typeInfo.description)}`;
  }

  if (!content) return;

  tooltipElement.innerHTML = content;

  // Position the tooltip
  const tooltipRect = tooltipElement.getBoundingClientRect();
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  let left = clientX + 10;
  let top = clientY - 10;

  // Adjust position if tooltip would go off screen
  if (left + tooltipRect.width > viewportWidth) {
    left = clientX - tooltipRect.width - 10;
  }
  if (top + tooltipRect.height > viewportHeight) {
    top = clientY - tooltipRect.height - 10;
  }

  tooltipElement.style.left = Math.max(0, left) + "px";
  tooltipElement.style.top = Math.max(0, top) + "px";

  // Show the tooltip
  tooltipElement.classList.add("show");
  isTooltipVisible = true;
}

function hideTooltip() {
  if (tooltipTimeout) {
    clearTimeout(tooltipTimeout);
    tooltipTimeout = null;
  }

  if (tooltipElement && isTooltipVisible) {
    tooltipElement.classList.remove("show");
    isTooltipVisible = false;
  }
}

// Initialize theme on page load
initTheme();

// Theme switch event listener
document.getElementById("themeSwitch").addEventListener("click", toggleTheme);
document.getElementById("themeSwitch").addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    toggleTheme();
  }
});

// Initialize when page loads
logInfo("Page loaded, setting up initialization...");

window.addEventListener("load", initializePlayground);
