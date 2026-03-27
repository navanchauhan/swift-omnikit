# OmniACP

`OmniACPModel` and `OmniACP` add Agent Client Protocol support to `swift-omnikit`.

## Modules

- `OmniACPModel`
  - Typed JSON-RPC envelopes
  - ACP methods and notifications
  - Session/content/tool/permission/terminal models
  - Stable vs draft schema-status markers
- `OmniACP`
  - Actor-based ACP client runtime
  - `stdio`, WebSocket, HTTP+SSE, and in-memory transports
  - Delegate bridge for agent-initiated permission, filesystem, and terminal requests

## Attractor backend

`OmniAIAttractor` now ships `ACPAgentBackend`, so `AttractorCLI` can run codergen nodes through an ACP-compatible agent over `stdio`, WebSocket, or HTTP+SSE.

### CLI usage

```bash
swift run AttractorCLI run pipeline.dot \
  --backend acp \
  --acp-agent /path/to/agent-binary \
  --acp-arg --stdio
```

Supported ACP CLI flags:

- `--backend acp`
- `--acp-agent <path-or-url>`
- `--acp-arg <value>` (repeatable)
- `--acp-cwd <path>`
- `--acp-timeout <seconds>`
- `--acp-mode <id>`

`--acp-agent` accepts:

- a local executable path for `StdioTransport`
- a `ws://` or `wss://` URL for `WebSocketTransport`
- an `http://` or `https://` URL for `HTTPSSETransport`

For HTTP mode, the default backend uses the same URL for outbound `POST` requests and inbound `GET` Server-Sent Events. If you need split endpoints or custom auth headers, construct `HTTPSSETransport` directly or inject a custom `ACPTransportProvider`.

### Environment variables

CLI and backend config can also come from environment variables:

- `ATTRACTOR_ACP_AGENT_BIN` (local path or remote URL)
- `ATTRACTOR_ACP_AGENT_ARGS` (comma-separated or JSON array)
- `ATTRACTOR_ACP_CWD`
- `ATTRACTOR_ACP_TIMEOUT_SECONDS`
- `ATTRACTOR_ACP_MODE`

### DOT / node attributes

`CodergenHandler` forwards these graph- or node-level attributes into the ACP backend context:

- `acp_agent_path` (local path or remote URL)
- `acp_agent_args`
- `acp_cwd`
- `acp_timeout_seconds`
- `acp_mode`

Node-level attributes override graph-level values.

## Runtime notes

- `ACPAgentBackend` creates one ACP session per codergen node.
- `WebSocketTransport` sends one ACP JSON-RPC message per WebSocket frame (text by default, binary optional in direct library use).
- `HTTPSSETransport` uses `POST` for client → agent messages and Server-Sent Events for agent → client messages. Each SSE `data:` payload must contain one complete ACP JSON-RPC message.
- Prompt streaming is collected from `session/update` notifications.
- ACP plan and tool-call activity is surfaced back into Attractor context keys:
  - `acp.session_id`
  - `acp.stop_reason`
  - `acp.plan`
  - `acp.tool_calls`
  - any structured `context_updates` emitted by the agent status block
- The default delegate constrains filesystem access to the configured working directory root.
- Terminal delegation is supported on macOS and Linux. It is explicitly unavailable on iOS-family platforms.

## Validation

Focused ACP verification commands:

```bash
swift build -c debug --target OmniACPModel
swift build -c debug --target OmniACP
swift build -c debug --target OmniAIAttractor
swift build -c debug --target AttractorCLI
swift test --filter 'OmniACPModelTests|GoldenTests|ClientTests|ACPAgentBackendTests'
```

## Live / env-gated tests

- `swift test --filter live_stdio_agent_test_is_env_gated`
- Set `RUN_OMNIACP_LIVE_STDIO_TESTS=1` and `OMNIACP_LIVE_AGENT_BIN=/path/to/agent`
- Optional args via `OMNIACP_LIVE_AGENT_ARGS`
