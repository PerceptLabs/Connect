# Connect: The Collaborative AI Workspace

Connect is a local-first, offline-capable project management workspace where users collaborate with multiple AI "Peers" (Local & Cloud models) to evolve complex plans.

## Features

*   **Single Binary**: Runs entirely as a single executable (`connect.com`). No installation required.
*   **Repo Bridge**: Syncs your plans to the local file system (`./repo/`). Edit with VS Code, and Connect sees the changes instantly.
*   **Smart Context (FTS5)**: Uses deterministic search to ensure LLMs see exactly what you want.
    *   *Note*: Optimized for the **Purpose-Built Redbean** binary with FTS5 enabled.
    *   *Fallback*: If run on standard Redbean, automatically falls back to a "Shim" (Basic Search) to ensure stability.
*   **Multi-Peer**: Talk to Ollama (Local), NanoGPT Cloud, or OpenAI/Anthropic.
*   **Production Hardened**: Encrypted API keys, Conflict Resolution (3-way diff), and Auto-Summarization.

## Getting Started

1.  **Build & Run**:
    The repository handles the binary setup automatically.
    ```bash
    ./verify.sh
    ```
    This script packages the application using the included high-performance binary (if available in `bin/`) or downloads a fallback.

2.  **Manual Start**:
    If you have already built `connect.com`:
    ```bash
    ./connect.com -p 8080
    ```
3.  **Open**: `http://localhost:8080` in your browser.

## Configuration

Connect loads `peers.json` from the binary (default) or from the current directory if you extract it.

### Setting up NanoGPT Cloud
1.  Get your API Key from [NanoGPT](https://nano-gpt.com).
2.  Set the environment variable:
    ```bash
    export NANOGPT_API_KEY="your-key-here"
    ./connect.com -p 8080
    ```
3.  Select "NanoGPT Cloud" in the Chat interface.

### Setting up Local Ollama
1.  Install [Ollama](https://ollama.com).
2.  Run `ollama serve`.
3.  Connect will talk to `http://localhost:11434`.

## Development

### Prerequisites
*   Node.js (for frontend)
*   Zip (for packing)
*   Redbean (Target binary)

### Build
1.  **Frontend**:
    ```bash
    cd frontend
    npm install
    npm run build
    cd ..
    ```
2.  **Pack**:
    ```bash
    # Ensure you have your 'redbean.com' (Purpose-Built preferred) in root
    cp redbean.com connect.com
    chmod +x connect.com
    zip -r connect.com .init.lua src/ peers.json schema.sql
    cd frontend/dist
    zip -r ../../connect.com .
    ```

## Architecture Notes

### FTS5 & The Safeguard Shim
Connect prefers **FTS5** (Full Text Search) for its context engine.
*   On startup, `.init.lua` probes the database capabilities.
*   If `FTS5` is detected (Purpose-Built Redbean), it enables BM25 ranking and advanced queries.
*   If missing (Standard Redbean), it falls back to a standard SQL `LIKE` shim. This ensures the app **never crashes** due to missing dependencies.

### Conflict Resolution
The **Repo Bridge** detects if a file has changed on disk AND in the database simultaneously.
*   A **3-way diff** UI appears, allowing you to Merge, Overwrite, or Accept changes.
*   Uses strict timestamp checking to prevent accidental overwrites.

## License
MIT
