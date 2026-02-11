# OmniKit

Personal Swift package (Swift 6 language mode, strict concurrency).

## Modules

- `OmniHTTP`: lightweight HTTP abstraction + SSE parser.
  - `URLSessionHTTPTransport` works on Apple platforms and on Linux via `FoundationNetworking`.
- `OmniHTTPNIO`: `NIOHTTPTransport` built on `swift-nio` + `async-http-client` (uses `swift-nio-transport-services` on Apple platforms when available).
- `OmniAICore`: unified multi-provider LLM client built on `OmniHTTP`.
  - OpenAI: Responses API (`/v1/responses`)
  - Anthropic: Messages API (`/v1/messages`)
  - Gemini: GenerateContent / StreamGenerateContent (`/v1beta/...:generateContent`)

## OmniAICore

### Environment Variables

- `OPENAI_API_KEY` (optional: `OPENAI_ORG_ID`, `OPENAI_PROJECT_ID`)
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY` (or `GOOGLE_API_KEY`)

### Quickstart

```swift
import OmniAICore

let client = try Client.fromEnv()

let result = try await generate(
    model: "gpt-5-nano-2025-08-07",
    prompt: "Return exactly the word hello.",
    provider: "openai",
    client: client
)

print(result.text)
```

### Use SwiftNIO Transport

```swift
import OmniAICore
import OmniHTTPNIO

let client = try Client.fromEnv(transport: NIOHTTPTransport())
```

### Tool Calling

```swift
import OmniAICore

let schema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "a": .object(["type": .string("integer")]),
        "b": .object(["type": .string("integer")]),
    ]),
    "required": .array([.string("a"), .string("b")]),
    "additionalProperties": .bool(false),
])

let add = try Tool(name: "add", description: "Add two integers", parameters: schema) { args, _ in
    let a = Int(args["a"]?.doubleValue ?? 0)
    let b = Int(args["b"]?.doubleValue ?? 0)
    return .number(Double(a + b))
}

let result = try await generate(
    model: "claude-haiku-4-5",
    prompt: "Use the add tool to compute 2+2. Then reply with just the number.",
    provider: "anthropic",
    tools: [add],
    toolChoice: ToolChoice(mode: .named, toolName: "add"),
    maxToolRounds: 3,
    client: client
)

print(result.text)
```

## Tests

- Unit tests: `swift test`
- Live integration smoke tests (reads `.env` if present):
  - `RUN_OMNIAI_INTEGRATION_TESTS=1 swift test --filter IntegrationSmokeTests`
  - Select providers: `OMNIAI_INTEGRATION_PROVIDERS=openai,anthropic`
  - Override models: `OPENAI_INTEGRATION_MODEL`, `ANTHROPIC_INTEGRATION_MODEL`, `GEMINI_INTEGRATION_MODEL`
  - Use catalog "latest": `OMNIAI_INTEGRATION_USE_LATEST=1`
