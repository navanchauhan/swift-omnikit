# SwiftBash Backend

`.swiftBash` runs shell commands in process through SwiftBash. It is intended as a fast local shell for one-shot agent commands, especially on platforms where spawning host processes is unavailable or undesirable.

| Area | `.swiftBash` behavior |
| --- | --- |
| Filesystem | Defaults to `sandboxedWorkspace`, a copy-on-write view rooted at the configured working directory. `realFileSystem` and `inMemory` are explicit opt-in modes. |
| Environment | Defaults to synthetic host metadata and a minimal shell environment. Host environment exposure is opt-in with `useHostEnvironment`. |
| Network | Defaults to disabled. When enabled, URL prefixes must be allow-listed unless `allowFullInternetAccess` is explicitly set. |
| Timeout | `execCommand(timeoutMs:)` returns `timedOut == true` and `exitCode == 124` when the wall-clock timeout wins. |

Good for:

- in-process shell commands
- file inspection inside the selected workspace
- text processing with SwiftBash builtins and registered commands
- lightweight scripts and one-shot transformations

Not for:

- external host binaries
- package managers
- compilers and build tools
- interactive PTY sessions
- long-running dev servers
- full Linux guest behavior

For iAgentSmith and other agent surfaces, present `.swiftBash` as "fast local shell." Use the Blink/container backend for full Linux commands, package installation, compilers, interactive terminal sessions, and long-running services.
