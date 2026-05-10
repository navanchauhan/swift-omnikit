#if os(Linux)
import Foundation
import OmniUICore

public struct macOSToolbarView<BackwardStack: Collection, ForwardStack: Collection>: View {
    @Binding private var url: String
    private var isURLFocused: FocusState<Bool>.Binding
    private let homeURL: URL
    private let shareThroughProxy: Bool
    private let backwardStack: BackwardStack
    private let forwardStack: ForwardStack
    private let currentHost: String
    @Binding private var showAddBookmark: Bool
    @Binding private var showBookmarks: Bool
    @Binding private var showPreferences: Bool
    private let onGo: () -> Void
    private let onHome: () -> Void
    private let onBack: () -> Void
    private let onForward: () -> Void
    @Binding private var showHomeTooltip: Bool
    private let homeTooltipMessage: String
    private let onHomeTooltipAutoDismiss: () -> Void

    public init(
        url: Binding<String>,
        isURLFocused: FocusState<Bool>.Binding,
        homeURL: URL,
        shareThroughProxy: Bool,
        backwardStack: BackwardStack,
        forwardStack: ForwardStack,
        currentHost: String,
        showAddBookmark: Binding<Bool>,
        showBookmarks: Binding<Bool>,
        showPreferences: Binding<Bool>,
        onGo: @escaping () -> Void,
        onHome: @escaping () -> Void,
        onBack: @escaping () -> Void,
        onForward: @escaping () -> Void,
        showHomeTooltip: Binding<Bool>,
        homeTooltipMessage: String,
        onHomeTooltipAutoDismiss: @escaping () -> Void
    ) {
        self._url = url
        self.isURLFocused = isURLFocused
        self.homeURL = homeURL
        self.shareThroughProxy = shareThroughProxy
        self.backwardStack = backwardStack
        self.forwardStack = forwardStack
        self.currentHost = currentHost
        self._showAddBookmark = showAddBookmark
        self._showBookmarks = showBookmarks
        self._showPreferences = showPreferences
        self.onGo = onGo
        self.onHome = onHome
        self.onBack = onBack
        self.onForward = onForward
        self._showHomeTooltip = showHomeTooltip
        self.homeTooltipMessage = homeTooltipMessage
        self.onHomeTooltipAutoDismiss = onHomeTooltipAutoDismiss
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onHome) {
                Label("Home", systemImage: "house")
                    .labelStyle(.iconOnly)
            }
            .disabled(url == homeURL.absoluteString)
            .accessibilityIdentifier("home-button")

            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .disabled(backwardStack.count < 2)
            .accessibilityIdentifier("back-button")

            Button(action: onForward) {
                Label("Forward", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(forwardStack.isEmpty)
            .accessibilityIdentifier("forward-button")

            TextField("Enter a URL", text: $url)
                .focused(isURLFocused)
                .padding(10)
                .frame(minWidth: 560)
                .accessibilityIdentifier("url-field")

            Button(action: { showAddBookmark = true }) {
                Label("Add Bookmark", systemImage: "bookmark.fill")
                    .labelStyle(.iconOnly)
            }
            .disabled(currentHost.isEmpty)
            .accessibilityIdentifier("add-bookmark-button")

            Button(action: { showBookmarks = true }) {
                Label("Bookmarks", systemImage: "book")
                    .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("bookmarks-history-button")

            Button(action: {}) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .accessibilityIdentifier("share-button")

            Button("Go", action: onGo)
                .accessibilityIdentifier("go-button")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
#endif
