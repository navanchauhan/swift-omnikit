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
    static func main() async {
        let root = iGopherBrowserTUISupport.makeRootView(inMemory: false)
        let args = Set(CommandLine.arguments.dropFirst())
        let forceANSI = args.contains("--ansi")
        let forceNotcurses = args.contains("--notcurses")
        let inTmux = (getenv("TMUX") != nil)

        do {
            if forceANSI {
                try await TerminalApp { root }.run()
                return
            }

            // tmux + notcurses is unreliable (frequent blank screen / input issues), so always
            // use ANSI inside tmux even if `--notcurses` was requested.
            if inTmux {
                if forceNotcurses {
                    _writeToStderr("TMUX detected; ignoring --notcurses and using ANSI renderer for stability.\n")
                } else {
                    _writeToStderr("TMUX detected; using ANSI renderer by default.\n")
                }
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
        } catch {
            if let terminalError = error as? OmniUITerminalRendererError, case .notATerminal = terminalError {
                _writeToStderr("ANSI renderer failed: process is not attached to a TTY.\n")
            } else {
                _writeToStderr("Renderer failed: \(error)\n")
            }
            exit(1)
        }
    }
}
