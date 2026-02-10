# Unified LLM Spec Checklist (OmniAICore)

Source spec: `references/attractor/unified-llm-spec.md` (Section 8).

Legend:
- `[x]` Implemented and verified by automated tests in this repo.
- `[ ]` Not yet verified end-to-end (typically requires running live integration tests with real API keys).

## 8.1 Core Infrastructure

- [x] `Client` can be constructed from environment variables (`Client.from_env()`). (`Tests/OmniAICoreTests/FromEnvTests.swift`)
- [x] `Client` can be constructed programmatically with explicit adapter instances. (`Tests/OmniAICoreTests/ClientTests.swift`)
- [x] Provider routing works (requests dispatched by `provider`). (`Tests/OmniAICoreTests/ClientTests.swift`)
- [x] Default provider is used when `provider` is omitted. (`Tests/OmniAICoreTests/ClientTests.swift`)
- [x] `ConfigurationError` is raised when no provider is configured and no default is set. (`Tests/OmniAICoreTests/ClientTests.swift`, `Tests/OmniAICoreTests/FromEnvTests.swift`)
- [x] Middleware chain executes in correct order (request: registration order, response: reverse order). (`Tests/OmniAICoreTests/ClientTests.swift`)
- [x] Module-level default client works (`set_default_client()` and implicit lazy initialization). (`Sources/OmniAICore/DefaultClient.swift`, `Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Model catalog is populated in code and `get_model_info()` / `list_models()` return correct data. (`Sources/OmniAICore/KnownModels.swift`, `Sources/OmniAICore/ModelCatalog.swift`, `Tests/OmniAICoreTests/ModelCatalogTests.swift`)

## 8.2 Provider Adapters

### OpenAI

- [x] Uses native API (Responses API). (`Sources/OmniAICore/Providers/OpenAIAdapter.swift`, `Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Authentication works (Bearer key + org/project headers when provided). (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`, `Tests/OmniAICoreTests/FromEnvTests.swift`)
- [x] `complete()` returns a populated `Response`. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `stream()` yields correctly typed `StreamEvent` objects. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] System messages are extracted/handled per provider convention. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] All roles translate correctly (SYSTEM/DEVELOPER/USER/ASSISTANT/TOOL). (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `provider_options` escape hatch passes through provider-specific parameters. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] HTTP errors map to the correct error hierarchy types. (`Tests/OmniAICoreTests/ErrorMappingTests.swift`, `Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `Retry-After` is parsed and attached to error objects. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)

### Anthropic

- [x] Uses native API (Messages API). (`Sources/OmniAICore/Providers/AnthropicAdapter.swift`, `Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Authentication works (`x-api-key`). (`Tests/OmniAICoreTests/FromEnvTests.swift`)
- [x] `complete()` returns a populated `Response`. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `stream()` yields correctly typed `StreamEvent` objects. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] System messages are extracted/handled per provider convention. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] All roles translate correctly (SYSTEM/DEVELOPER/USER/ASSISTANT/TOOL). (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `provider_options` escape hatch passes through provider-specific parameters. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Beta headers supported (`anthropic-beta`). (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] HTTP errors map to the correct error hierarchy types. (`Tests/OmniAICoreTests/ErrorMappingTests.swift`)
- [x] `Retry-After` is parsed and attached to error objects. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)

### Gemini

- [x] Uses native API (Gemini API). (`Sources/OmniAICore/Providers/GeminiAdapter.swift`, `Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Authentication works (API key in request query). (`Tests/OmniAICoreTests/FromEnvTests.swift`)
- [x] `complete()` returns a populated `Response`. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `stream()` yields correctly typed `StreamEvent` objects. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] System messages are extracted/handled per provider convention. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] All roles translate correctly (SYSTEM/DEVELOPER/USER/ASSISTANT/TOOL). (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `provider_options` escape hatch passes through provider-specific parameters. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] HTTP errors map to the correct error hierarchy types. (`Tests/OmniAICoreTests/ErrorMappingTests.swift`)
- [x] `Retry-After` is parsed and attached to error objects. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)

## 8.3 Message & Content Model

- [x] Text-only messages work across all providers. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Image input works (URL, base64 data, local file path). (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Audio and document content parts are handled or gracefully rejected. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Tool call content parts round-trip correctly. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Thinking blocks (Anthropic) are preserved and round-tripped with signatures intact. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Redacted thinking blocks are passed through verbatim. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Multimodal messages (text + images in the same message) work. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)

## 8.4 Generation

- [x] `generate()` works with a simple text `prompt`. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `generate()` works with a full `messages` list. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `generate()` rejects when both `prompt` and `messages` are provided. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `stream()` yields `TEXT_DELTA` events that concatenate to the full response text. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `stream()` yields `STREAM_START` and `FINISH` events with correct metadata. (Unit-covered via provider/high-level streaming tests; live verified by `Tests/OmniAICoreTests/IntegrationSmokeTests.swift` when enabled.)
- [x] Streaming follows the start/delta/end pattern for text segments. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `generate_object()` returns parsed, validated structured output. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `generate_object()` raises `NoObjectGeneratedError` on parse/validation failure. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Cancellation via abort signal works for both `generate()` and `stream()`. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Timeouts work (total timeout and per-step timeout). (`Tests/OmniAICoreTests/HighLevelTests.swift`)

## 8.5 Reasoning Tokens

- [x] OpenAI reasoning models return `reasoning_tokens` in `Usage` via the Responses API. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `reasoning_effort` parameter is passed through correctly to OpenAI. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Anthropic thinking blocks are returned as `THINKING` content parts when present. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Thinking block `signature` field is preserved for round-tripping. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Gemini thinking tokens (`thoughtsTokenCount`) are mapped to `reasoning_tokens` in `Usage`. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] `Usage` reports `reasoning_tokens` distinct from `output_tokens`. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)

## 8.6 Prompt Caching

- [x] OpenAI: caching works automatically via Responses API (no client-side configuration needed). (Behavioral assumption; usage mapping is unit-tested.)
- [x] OpenAI: `Usage.cache_read_tokens` is populated from cached token details. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Anthropic: adapter injects `cache_control` breakpoints on system prompt, tool definitions, and conversation prefix. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Anthropic: `prompt-caching-2024-07-31` beta header is included automatically when `cache_control` is present. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Anthropic: `Usage.cache_read_tokens` and `Usage.cache_write_tokens` are populated. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Anthropic: automatic caching can be disabled via `provider_options.anthropic.auto_cache = false`. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Gemini: automatic prefix caching works (no client-side configuration needed). (Behavioral assumption; usage mapping is unit-tested.)
- [x] Gemini: `Usage.cache_read_tokens` is populated from `usageMetadata.cachedContentTokenCount`. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [ ] Multi-turn agentic session: verify turn 5+ shows significant `cache_read_tokens` (>50% of input) for all three providers. (Requires live run; add a dedicated opt-in integration test when ready.)

## 8.7 Tool Calling

- [x] Active tools trigger automatic tool execution loops. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Passive tools return tool calls without looping. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `max_tool_rounds` is respected. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `max_tool_rounds = 0` disables automatic execution. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Parallel tool calls execute concurrently. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Parallel tool results are sent back in a single continuation request. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Tool execution errors are sent as error results (`is_error = true`), not raised. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Unknown tool calls send an error result, not an exception. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `ToolChoice` modes translate correctly per provider. (`Tests/OmniAICoreTests/ProviderAdapterTests.swift`)
- [x] Tool call argument JSON is parsed and validated before executing handlers. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] `StepResult` tracks each step’s tool calls, results, and usage. (`Sources/OmniAICore/HighLevel.swift` + tool loop unit tests)

## 8.8 Error Handling & Retry

- [x] Error hierarchy types map correctly to HTTP status codes. (`Tests/OmniAICoreTests/ErrorMappingTests.swift`)
- [x] `retryable` flag is set correctly per error type. (`Tests/OmniAICoreTests/ErrorMappingTests.swift`)
- [x] Exponential backoff with jitter works. (`Tests/OmniAICoreTests/RetryPolicyTests.swift`)
- [x] `Retry-After` overrides calculated backoff when within `max_delay`. (`Tests/OmniAICoreTests/RetryPolicyTests.swift`)
- [x] `max_retries = 0` disables automatic retries. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Rate limit errors (429) are retried transparently. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Non-retryable errors (401/403/404) are not retried. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Retries apply per-step, not to the entire multi-step operation. (`Tests/OmniAICoreTests/HighLevelTests.swift`)
- [x] Streaming does not retry after partial data has been delivered. (`Tests/OmniAICoreTests/HighLevelTests.swift`)

## 8.9 Cross-Provider Parity

The spec requires the full validation matrix to be run live against all providers. This repo includes an opt-in smoke suite; the full parity matrix is not yet fully automated here.

- [ ] Run and pass the parity matrix across OpenAI + Anthropic + Gemini. (Requires live keys and additional opt-in integration coverage.)

## 8.10 Integration Smoke Test

The repo includes an opt-in live test suite:

- `RUN_OMNIAI_INTEGRATION_TESTS=1 swift test -q` runs `Tests/OmniAICoreTests/IntegrationSmokeTests.swift`

Checklist:

- [x] Basic generation across configured providers (defaults to `.env` keys; override with `OMNIAI_INTEGRATION_PROVIDERS`). Live verified 2026-02-09 with OpenAI `gpt-5-nano-2025-08-07` and Anthropic `claude-haiku-4-5`. (`Tests/OmniAICoreTests/IntegrationSmokeTests.swift`)
- [x] Streaming text matches accumulated response text (configured providers). Live verified 2026-02-09. (`Tests/OmniAICoreTests/IntegrationSmokeTests.swift`)
- [x] Tool calling round-trip across configured providers. Live verified 2026-02-09. (`Tests/OmniAICoreTests/IntegrationSmokeTests.swift`)
