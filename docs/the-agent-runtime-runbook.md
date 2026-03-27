# The Agent Runtime Runbook

Date: 2026-03-24

This runbook covers the implemented Sprint 007 runtime: control plane, Telegram ingress, authenticated HTTP ingress, remote workers, and Attractor-backed worker execution.

## Prerequisites

- Swift toolchain installed on the control-plane and worker hosts
- provider credentials for the root and worker models you intend to use
- optional Telegram bot token
- optional public webhook endpoint if you want Telegram webhook mode instead of polling

## Build

```sh
swift build --product TheAgentControlPlane --product TheAgentWorker
```

## State Root

By default the binaries use the repo-local working-directory state root. To force a specific durable state root:

```sh
export THE_AGENT_STATE_ROOT=/absolute/path/to/.ai/the-agent
```

The control plane and same-host worker can share that directory. Remote workers only need it when they are using local SQLite/file-backed mode instead of the HTTP mesh.

## Control Plane Startup

### Local dev with Telegram polling

```sh
export THE_AGENT_TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN

./.build/debug/TheAgentControlPlane \
  --mesh-host 0.0.0.0 \
  --mesh-port 9078 \
  --http-ingress-host 127.0.0.1 \
  --http-ingress-port 9080 \
  --http-ingress-bearer-token local-dev-token \
  --telegram-polling
```

What this does:

- starts the HTTP mesh on `9078`
- starts authenticated HTTP ingress on `9080`
- disables Telegram webhook mode and uses `getUpdates`
- keeps all ingress paths routed through the same `IngressGateway`

### Production-ish Telegram webhook mode

```sh
export THE_AGENT_TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN

./.build/debug/TheAgentControlPlane \
  --mesh-host 0.0.0.0 \
  --mesh-port 9078 \
  --http-ingress-host 0.0.0.0 \
  --http-ingress-port 9080 \
  --http-ingress-bearer-token prod-api-token \
  --telegram-webhook-url https://YOUR_HOST/telegram/webhook \
  --telegram-webhook-secret YOUR_SECRET
```

Notes:

- `/telegram/webhook` is served by the same HTTP ingress process.
- The handler validates `X-Telegram-Bot-Api-Secret-Token` against `--telegram-webhook-secret`.
- Callback queries are acknowledged immediately, then mission state continues asynchronously.

## Worker Startup

### Same-host local worker

```sh
./.build/debug/TheAgentWorker \
  --capability macOS
```

### Remote HTTP mesh worker

```sh
./.build/debug/TheAgentWorker \
  --mesh-url http://CONTROL_PLANE_HOST:9078 \
  --capability linux \
  --poll-interval 0.5
```

### ACP-backed remote worker

```sh
./.build/debug/TheAgentWorker \
  --mesh-url http://CONTROL_PLANE_HOST:9078 \
  --capability linux \
  --acp-profile codex \
  --acp-agent /absolute/path/to/codex-acp \
  --poll-interval 0.5
```

Useful ACP flags:

- `--acp-model`
- `--acp-reasoning-effort`
- `--acp-arg`
- `--acp-mode`
- `--acp-timeout-seconds`
- `--acp-working-directory`

### Attractor-backed remote worker

```sh
./.build/debug/TheAgentWorker \
  --mesh-url http://CONTROL_PLANE_HOST:9078 \
  --capability linux \
  --attractor \
  --attractor-provider openai \
  --attractor-model gpt-5.2-codex \
  --attractor-working-directory /absolute/path/to/worktree \
  --attractor-human-timeout-seconds 300 \
  --poll-interval 0.5
```

Behavior:

- atomic tasks can stay on the plain local/ACP path
- compound tasks can be routed to the Attractor executor
- Attractor `wait_human` requests flow back to the root inbox instead of prompting locally

## Root Runtime Behavior

Implemented mission behavior:

- direct root handling for small asks
- worker-task dispatch for bounded execution
- Attractor-backed workflow execution for compound tasks

Mission artifacts created by the control plane:

- `mission-contract.json`
- `mission-progress.log`
- `verification-report.txt`

## Telegram Behavior

Current Telegram rules:

- DMs auto-provision a personal workspace.
- Shared groups/topics require explicit mention or reply-context by default.
- Sensitive approvals and blocking questions default to DM delivery.
- If a DM does not exist yet, the request is persisted and the shared chat gets a bootstrap prompt telling the user to start a DM with the bot.
- Long assistant replies are chunked automatically.
- Unsupported media is rejected explicitly instead of silently disappearing.

## Authenticated HTTP/API Ingress

The control plane exposes authenticated HTTP endpoints when `--http-ingress-port` is set.

Available endpoints:

- `POST /api/v1/messages`
- `POST /api/v1/inbox`
- `POST /api/v1/approvals`
- `POST /api/v1/questions`

Bearer auth:

```sh
Authorization: Bearer YOUR_TOKEN
```

This path uses the same runtime contract as Telegram. It is not a second orchestration stack.

## Mesh Artifact Access

The HTTP mesh now supports remote artifact visibility.

That is what allows:

- remote worker outputs to be fetched by the control plane
- mission/task artifacts to survive beyond a single host
- remote validation lanes to inspect outputs without shelling into the worker host

## Recommended Validation Commands

Sprint-targeted validation:

```sh
swift test --skip-build --filter 'IdentityStoreTests|SQLiteStoresTests|WorkspaceSessionRegistryTests|MissionCoordinatorTests|RootOrchestratorTests|HTTPRemoteWorkerTransportTests|ArtifactTransportTests|IngressGatewayTests|TelegramIngressTests|HTTPIngressServerTests|MultiUserRoutingTests|AttractorTaskExecutorTests|NestedDelegationTests'
```

Full package validation:

```sh
swift test --skip-build
```

## Recovery Notes

- Mission, delivery, approval, and question state is durable in SQLite-backed stores.
- Remote workers can reconnect and continue polling the HTTP mesh.
- Telegram duplicate updates are suppressed by the inbound delivery store.
- Workspace runtime ownership is rebuilt lazily by `WorkspaceRuntimeRegistry`.

## What Still Requires External Setup

The remaining non-repo step is a real Telegram proof run.

You still need:

- a valid Telegram bot token
- either polling access or a reachable webhook host
- provider credentials suitable for the chosen root/worker models

Once those exist, the current binaries are ready to run the live path without more code changes.
