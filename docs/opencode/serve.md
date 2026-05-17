# opencode serve

`opencode serve` runs a headless HTTP server that exposes an OpenAPI endpoint for clients to interact with OpenCode programmatically.

## Usage

```
opencode serve [--port <number>] [--hostname <string>] [--cors <origin>]
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--port` | Port to listen on | `4096` |
| `--hostname` | Hostname to listen on | `127.0.0.1` |
| `--mdns` | Enable mDNS discovery | `false` |
| `--mdns-domain` | Custom domain name for mDNS service | `opencode.local` |
| `--cors` | Additional browser origins to allow | `[]` |

`--cors` can be passed multiple times:

```
opencode serve --cors http://localhost:5173 --cors https://app.example.com
```

## Authentication

Set `OPENCODE_SERVER_PASSWORD` to protect the server with HTTP basic auth. Username defaults to `opencode`, override with `OPENCODE_SERVER_USERNAME`.

```
OPENCODE_SERVER_PASSWORD=your-password opencode serve
```

## How it works

When you run `opencode` it starts a TUI and a server. The TUI is a client that talks to the server. The server exposes an OpenAPI 3.1 spec endpoint at `http://<hostname>:<port>/doc`.

`opencode serve` starts a standalone server. If the TUI is already running, a new server instance is started.

### Connect to an existing server

Pass `--hostname` and `--port` when starting the TUI to connect to its server. The `/tui` endpoint can drive the TUI through the server (used by IDE plugins).

## OpenAPI Spec

```
http://<hostname>:<port>/doc
```

## API Endpoints

### Global
- `GET /global/health` — Server health and version
- `GET /global/event` — Global events (SSE stream)

### Project
- `GET /project` — List all projects
- `GET /project/current` — Current project

### Path & VCS
- `GET /path` — Current path
- `GET /vcs` — VCS info

### Instance
- `POST /instance/dispose` — Dispose current instance

### Config
- `GET /config` — Get config
- `PATCH /config` — Update config
- `GET /config/providers` — List providers and default models

### Sessions
- `GET /session` — List all sessions
- `POST /session` — Create session
- `GET /session/:id` — Get session details
- `DELETE /session/:id` — Delete session
- `PATCH /session/:id` — Update session title
- `GET /session/:id/children` — Child sessions
- `GET /session/:id/todo` — Todo list
- `POST /session/:id/init` — Analyze app and create AGENTS.md
- `POST /session/:id/fork` — Fork session at message
- `POST /session/:id/abort` — Abort running session
- `POST /session/:id/share` — Share session
- `DELETE /session/:id/share` — Unshare session
- `GET /session/:id/diff` — Get file diff
- `POST /session/:id/summarize` — Summarize session
- `POST /session/:id/revert` — Revert message
- `POST /session/:id/unrevert` — Restore reverted messages
- `POST /session/:id/permissions/:permissionID` — Respond to permission request

### Messages
- `GET /session/:id/message` — List messages
- `POST /session/:id/message` — Send message (wait for response)
- `GET /session/:id/message/:messageID` — Get message details
- `POST /session/:id/prompt_async` — Send message async
- `POST /session/:id/command` — Execute slash command
- `POST /session/:id/shell` — Run shell command

### Files
- `GET /find?pattern=<pat>` — Search text in files
- `GET /find/file?query=<q>` — Find files/directories
- `GET /find/symbol?query=<q>` — Find workspace symbols
- `GET /file?path=<path>` — List files/directories
- `GET /file/content?path=<p>` — Read file
- `GET /file/status` — Tracked file status

### LSP, Formatters & MCP
- `GET /lsp` — LSP server status
- `GET /formatter` — Formatter status
- `GET /mcp` — MCP server status
- `POST /mcp` — Add MCP server dynamically

### TUI
- `POST /tui/append-prompt` — Append text to prompt
- `POST /tui/submit-prompt` — Submit prompt
- `POST /tui/clear-prompt` — Clear prompt
- `POST /tui/execute-command` — Execute command
- `POST /tui/show-toast` — Show toast notification
- `POST /tui/open-help` / `open-sessions` / `open-themes` / `open-models`

### Auth
- `PUT /auth/:id` — Set authentication credentials

### Events
- `GET /event` — SSE event stream

### Docs
- `GET /doc` — OpenAPI 3.1 spec HTML page
