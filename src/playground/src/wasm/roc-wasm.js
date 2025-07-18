/**
 * WASM Integration Module for Roc Playground
 * Handles loading, initialization, and communication with the Roc WASM module
 */

let wasmModule = null;
let wasmMemory = null;
let messageQueue = [];
let messageInProgress = false;

/**
 * Initializes the WASM module and returns an interface object
 * @returns {Promise<Object>} WASM interface object
 */
export async function initializeWasm() {
  try {
    console.log("Initializing WASM module...");

    // Load the WASM file
    const response = await fetch("playground.wasm");

    if (!response.ok) {
      throw new Error(
        `Failed to fetch WASM file: ${response.status} ${response.statusText}`,
      );
    }

    const bytes = await response.arrayBuffer();

    if (bytes.byteLength === 0) {
      throw new Error("WASM file is empty");
    }

    console.log(`WASM file loaded: ${bytes.byteLength} bytes`);

    // Instantiate the WASM module
    const module = await WebAssembly.instantiate(bytes, {
      env: {
        // Add any required imports here
      },
    });

    wasmModule = module.instance.exports;
    wasmMemory = wasmModule.memory;

    console.log("WASM module instantiated");
    console.log("Available exports:", Object.keys(wasmModule));

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

    // Initialize the WASM module
    wasmModule.init();
    console.log("WASM module initialized successfully");

    // Initialize the WASM module
    await sendMessageDirect({ type: "INIT" });

    // Return the interface object
    return createWasmInterface();
  } catch (error) {
    console.error("Error initializing WASM:", error);
    throw new Error(`Failed to initialize WASM module: ${error.message}`);
  }
}

/**
 * Creates the WASM interface object that other modules can use
 * @returns {Object} WASM interface with methods
 */
function createWasmInterface() {
  return {
    // Core compilation methods
    compile: async (code) => {
      // Reset to READY state first, then load the source
      try {
        await sendMessageQueued({ type: "RESET" });
      } catch (error) {
        console.warn("Reset failed, continuing anyway:", error);
      }

      // Now load the source
      const loadResult = await sendMessageQueued({
        type: "LOAD_SOURCE",
        source: code,
      });
      return loadResult;
    },
    tokenize: () => sendMessageQueued({ type: "QUERY_TOKENS" }),
    parse: () => sendMessageQueued({ type: "QUERY_AST" }),
    canonicalize: () => sendMessageQueued({ type: "QUERY_CIR" }),
    getTypes: () => sendMessageQueued({ type: "QUERY_TYPES" }),

    // Type information methods
    getTypeInfo: async (word, position) => {
      try {
        const result = await sendMessageQueued({
          type: "GET_TYPE_INFO",
          word,
          position,
        });
        return result;
      } catch (error) {
        console.error("Error getting type info:", error);
        return null;
      }
    },

    // Status methods
    isReady: () => wasmModule !== null,
    getMemoryUsage: () => (wasmMemory ? wasmMemory.buffer.byteLength : 0),

    // Raw message sending for advanced use
    sendMessage: sendMessageQueued,
  };
}

/**
 * Sends a message to the WASM module (queued to handle concurrency)
 * @param {Object} message - The message to send
 * @returns {Promise<Object>} The response from WASM
 */
function sendMessageQueued(message) {
  return new Promise((resolve, reject) => {
    messageQueue.push({ message, resolve, reject });
    processMessageQueue();
  });
}

/**
 * Processes the message queue, ensuring only one message is processed at a time
 */
async function processMessageQueue() {
  if (messageInProgress || messageQueue.length === 0) {
    return;
  }

  messageInProgress = true;

  while (messageQueue.length > 0) {
    const { message, resolve, reject } = messageQueue.shift();

    try {
      const result = await sendMessageDirect(message);
      resolve(result);
    } catch (error) {
      reject(error);
    }
  }

  messageInProgress = false;
}

/**
 * Sends a message directly to the WASM module
 * @param {Object} message - The message to send
 * @returns {Promise<Object>} The response from WASM
 */
async function sendMessageDirect(message) {
  if (!wasmModule) {
    throw new Error("WASM module not loaded");
  }

  let messagePtr = null;
  let responsePtr = null;
  let messageBytes = null;

  try {
    const messageStr = JSON.stringify(message);
    messageBytes = new TextEncoder().encode(messageStr);

    // Allocate memory for message
    messagePtr = wasmModule.allocate(messageBytes.length);
    if (!messagePtr) {
      throw new Error("Failed to allocate message memory");
    }

    const memory = new Uint8Array(wasmMemory.buffer);
    memory.set(messageBytes, messagePtr);

    // Allocate memory for response
    const responseBufferSize = 64 * 1024; // 64KB buffer
    responsePtr = wasmModule.allocate(responseBufferSize);
    if (!responsePtr) {
      throw new Error("Failed to allocate response memory");
    }

    // Process message
    const responseLen = wasmModule.processMessage(
      messagePtr,
      messageBytes.length,
      responsePtr,
      responseBufferSize,
    );

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

    if (!responseStr.trim()) {
      throw new Error("WASM returned empty response string");
    }

    let parsedResponse;
    try {
      parsedResponse = JSON.parse(responseStr);
    } catch (jsonError) {
      throw new Error(
        `Invalid JSON response from WASM: ${responseStr.substring(0, 100)}...`,
      );
    }

    return parsedResponse;
  } catch (error) {
    console.error("Error in sendMessageDirect:", error);
    throw error;
  } finally {
    // Clean up memory
    if (messagePtr && wasmModule.deallocate && messageBytes) {
      wasmModule.deallocate(messagePtr, messageBytes.length);
    }
    if (responsePtr && wasmModule.deallocate) {
      wasmModule.deallocate(responsePtr, 64 * 1024);
    }
  }
}

/**
 * Utility function to check if WASM is ready
 * @returns {boolean} True if WASM is loaded and ready
 */
export function isWasmReady() {
  return wasmModule !== null;
}

/**
 * Gets the current memory usage of the WASM module
 * @returns {number} Memory usage in bytes
 */
export function getWasmMemoryUsage() {
  return wasmMemory ? wasmMemory.buffer.byteLength : 0;
}

/**
 * Resets the WASM module state (for testing or recovery)
 */
export function resetWasm() {
  wasmModule = null;
  wasmMemory = null;
  messageQueue = [];
  messageInProgress = false;
}
