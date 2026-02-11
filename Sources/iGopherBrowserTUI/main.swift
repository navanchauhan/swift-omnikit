import iGopherBrowserViews
import OmniUINotcursesRenderer
import OmniUITerminalRenderer
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private func _writeToStderr(_ message: String) {
    let bytes = Array(message.utf8)
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        #if os(Linux)
        _ = Glibc.write(STDERR_FILENO, base, raw.count)
        #else
        _ = Darwin.write(STDERR_FILENO, base, raw.count)
        #endif
    }
}

@main
enum iGopherBrowserTUIMain {
    @MainActor
    static func main() async throws {
        let root = iGopherBrowserTUISupport.makeRootView(inMemory: false)
        let args = Set(CommandLine.arguments.dropFirst())
        let forceANSI = args.contains("--ansi")
        let forceNotcurses = args.contains("--notcurses")
        let inTmux = (getenv("TMUX") != nil)

        if forceANSI {
            try await TerminalApp { root }.run()
            return
        }

        // tmux + notcurses currently has unreliable keyboard handling (mouse still works).
        // Default to ANSI in tmux unless notcurses was explicitly requested.
        if inTmux && !forceNotcurses {
            _writeToStderr("TMUX detected; using ANSI renderer by default. Pass --notcurses to force notcurses.\n")
            try await TerminalApp { root }.run()
            return
        }

        // Default to notcurses when available.
        do {
            try await NotcursesApp { root }.run()
        } catch {
            _writeToStderr("Notcurses renderer failed: \(error)\nFalling back to ANSI renderer.\n")
            try await TerminalApp { root }.run()
        }
    }
}
