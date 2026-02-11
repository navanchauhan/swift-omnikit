import iGopherBrowserViews
import OmniUINotcursesRenderer
import OmniUITerminalRenderer

@main
enum iGopherBrowserTUIMain {
    @MainActor
    static func main() async throws {
        let root = iGopherBrowserTUISupport.makeRootView(inMemory: false)

        if CommandLine.arguments.contains("--ansi") {
            try await TerminalApp { root }.run()
            return
        }

        // Default to notcurses when available.
        try await NotcursesApp { root }.run()
    }
}

