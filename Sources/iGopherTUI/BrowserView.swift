//
//  BrowserView.swift
//  iGopherBrowser
//
//  Created by Navan Chauhan on 12/16/23.
//
//  Adapted for TUI: removed TelemetryDeck, AppKit/UIKit, ShareLink, platform splits.
//  Uses a single unified toolbar.

import SwiftData
import SwiftUI

func openURL(url: URL) {
    // No-op in TUI mode
}

struct BrowserView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("homeURL") var homeURL: URL = URL(string: "gopher://gopher.navan.dev:70/")!
    @AppStorage("accentColour", store: .standard) var accentColour: Color = Color(.blue)
    @AppStorage("linkColour", store: .standard) var linkColour: Color = Color(.white)
    @AppStorage("shareThroughProxy", store: .standard) var shareThroughProxy: Bool = true
    @AppStorage("crtMode") var crtMode: Bool = false
    @AppStorage("crtPhosphorColor") var crtPhosphorColorRaw: String = CRTPhosphorColor.green.rawValue
    @AppStorage("hasFinishedFirstRunTips") var hasFinishedFirstRunTips: Bool = false
    @AppStorage("lastSeenWhatsNewVersion") var lastSeenWhatsNewVersion: String = ""

    // CRT-aware colors
    private var crtPhosphorColor: Color {
        (CRTPhosphorColor(rawValue: crtPhosphorColorRaw) ?? .green).color
    }

    private var effectiveLinkColor: Color {
        crtMode ? crtPhosphorColor : linkColour
    }

    private var effectiveTextColor: Color {
        crtMode ? crtPhosphorColor : .primary
    }

    @State var homeURLString = "gopher://gopher.navan.dev:70/"

    @State var url: String = ""
    @State private var gopherItems: [gopherItem] = []

    @Binding public var hosts: [GopherNode]
    @Binding var selectedNode: GopherNode?

    @State private var backwardStack: [GopherNode] = []
    @State private var forwardStack: [GopherNode] = []

    @State private var searchText: String = ""
    @State private var showSearchInput = false
    @State var selectedSearchItem: Int?
    @State private var directSearchContext: (host: String, port: Int, selector: String)? = nil

    @State private var showPreferences = false
    @State private var showBookmarks = false
    @State private var showAddBookmark = false
    @State private var currentHost: String = ""
    @State private var currentPort: Int = 70
    @State private var currentSelector: String = ""

    @Namespace var topID
    @State private var scrollToTop: Bool = false

    @State private var showHomeTooltip: Bool = false

    @FocusState private var isURLFocused: Bool

    // Find in page
    @State private var showFindInPage = false
    @State private var findText: String = ""
    @State private var currentFindIndex: Int = 0
    @FocusState private var isFindFocused: Bool

    private let homeTooltipMessage = "Tap Home to visit your first Gopherhole."

    private var findMatches: [Int] {
        guard !findText.isEmpty else { return [] }
        return gopherItems.enumerated().compactMap { idx, item in
            item.message.localizedCaseInsensitiveContains(findText) ? idx : nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if gopherItems.count >= 1 {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(Array(gopherItems.enumerated()), id: \.offset) { idx, item in
                                Group {
                                    if item.parsedItemType == .info {
                                        Text(item.message)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(effectiveTextColor)
                                            .frame(height: 20)
                                            .listRowSeparator(.hidden)
                                            .padding(.vertical, -8)
                                            .id(idx)
                                    } else if item.parsedItemType == .directory {
                                        Button(action: {
                                            performGopherRequest(
                                                host: item.host, port: item.port,
                                                selector: item.selector)
                                        }) {
                                            HStack {
                                                Text(Image(systemName: "folder"))
                                                Text(item.message)
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                            .foregroundStyle(effectiveLinkColor)
                                        }.buttonStyle(PlainButtonStyle())
                                            .id(idx)
                                    } else if item.parsedItemType == .search {
                                        Button(action: {
                                            self.selectedSearchItem = idx
                                            self.showSearchInput = true
                                        }) {
                                            HStack {
                                                Text(Image(systemName: "magnifyingglass"))
                                                Text(item.message)
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                            .foregroundStyle(effectiveLinkColor)
                                        }.buttonStyle(PlainButtonStyle())
                                            .id(idx)
                                    } else if item.parsedItemType == .text {
                                        NavigationLink(destination: FileView(item: item)) {
                                            HStack {
                                                Text(Image(systemName: "doc.plaintext"))
                                                Text(item.message)
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                            .foregroundStyle(effectiveLinkColor)
                                        }
                                        .id(idx)
                                    } else if item.selector.hasPrefix("URL:") {
                                        if let linkURL = URL(
                                            string: item.selector.replacingOccurrences(
                                                of: "URL:", with: ""))
                                        {
                                            Button(action: {
                                                openURL(url: linkURL)
                                            }) {
                                                HStack {
                                                    Image(systemName: "link")
                                                    Text(item.message)
                                                    Spacer()
                                                }
                                                .contentShape(Rectangle())
                                                .foregroundStyle(effectiveLinkColor)
                                            }.buttonStyle(PlainButtonStyle())
                                                .id(idx)
                                        }
                                    } else if [.doc, .image, .gif, .movie, .sound, .bitmap, .binary].contains(
                                        item.parsedItemType)
                                    {
                                        NavigationLink(destination: FileView(item: item)) {
                                            HStack {
                                                Text(Image(systemName: itemToImageType(item)))
                                                Text(item.message)
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                            .foregroundStyle(effectiveLinkColor)
                                        }
                                        .id(idx)
                                    } else {
                                        Button(action: {
                                            performGopherRequest(
                                                host: item.host, port: item.port,
                                                selector: item.selector)
                                        }) {
                                            HStack {
                                                Text(Image(systemName: "questionmark.app.dashed"))
                                                Text(item.message)
                                                Spacer()
                                            }
                                            .contentShape(Rectangle())
                                            .foregroundStyle(effectiveLinkColor)
                                        }.buttonStyle(PlainButtonStyle())
                                            .id(idx)
                                    }
                                }
                                .listRowBackground(rowBackgroundColor(for: idx))
                            }
                        }
                        .scrollContentBackground(crtMode ? .hidden : .automatic)
                        .background(crtMode ? Color.clear : Color.clear)
                        .cornerRadius(10)
                        .onChange(of: scrollToTop) { _, _ in
                            proxy.scrollTo(0, anchor: .top)
                        }
                        .onChange(of: selectedSearchItem) { _, newValue in
                            if newValue != nil {
                                self.showSearchInput = true
                            }
                        }
                        .onChange(of: currentFindIndex) { _, newIndex in
                            if !findMatches.isEmpty && newIndex < findMatches.count {
                                withAnimation {
                                    proxy.scrollTo(findMatches[newIndex], anchor: .center)
                                }
                            }
                        }
                        .onChange(of: findText) { _, _ in
                            currentFindIndex = 0
                            if !findMatches.isEmpty {
                                withAnimation {
                                    proxy.scrollTo(findMatches[0], anchor: .center)
                                }
                            }
                        }
                        .safeAreaInset(edge: .top) {
                            if showFindInPage {
                                FindInPageBar(
                                    findText: $findText,
                                    currentIndex: $currentFindIndex,
                                    totalMatches: findMatches.count,
                                    isFocused: $isFindFocused,
                                    onDismiss: {
                                        showFindInPage = false
                                        findText = ""
                                    }
                                )
                            }
                        }
                    }
                    .sheet(isPresented: $showSearchInput, onDismiss: {
                        self.selectedSearchItem = nil
                        self.directSearchContext = nil
                    }) {
                        if let index = selectedSearchItem, gopherItems.indices.contains(index) {
                            let searchItem = gopherItems[index]
                            SearchInputView(
                                host: searchItem.host,
                                port: searchItem.port,
                                selector: searchItem.selector,
                                searchText: $searchText,
                                onSearch: { query in
                                    performGopherRequest(
                                        host: searchItem.host, port: searchItem.port,
                                        selector: "\(searchItem.selector)\t\(query)")
                                    showSearchInput = false
                                }
                            )
                        } else if let ctx = directSearchContext {
                            SearchInputView(
                                host: ctx.host,
                                port: ctx.port,
                                selector: ctx.selector,
                                searchText: $searchText,
                                onSearch: { query in
                                    performGopherRequest(
                                        host: ctx.host, port: ctx.port,
                                        selector: "\(ctx.selector)\t\(query)")
                                    showSearchInput = false
                                }
                            )
                        } else {
                            VStack {
                                Text("Weird bug. Please Dismiss -> Press Go -> Try Again")
                                Button("Dismiss") {
                                    self.showSearchInput = false
                                }
                            }
                        }
                    }
                } else {
                    Spacer()
                    Text("Welcome to iGopher Browser")
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
                // Unified TUI toolbar
                tuiToolbarView
            }
        }
        .onChange(of: selectedNode) { _, newValue in
            if let node = newValue {
                performGopherRequest(host: node.host, port: node.port, selector: node.selector)
            }
        }
        .sheet(
            isPresented: $showPreferences,
            onDismiss: {
                if let url = URL(string: homeURLString) {
                    self.homeURL = url
                }
            }
        ) {
            SettingsView()
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksHistoryView { host, port, selector in
                performGopherRequest(host: host, port: port, selector: selector)
            }
        }
        .sheet(isPresented: $showAddBookmark) {
            AddBookmarkView(
                host: currentHost,
                port: currentPort,
                selector: currentSelector
            )
        }
        .accentColor(accentColour)
        .onAppear {
            if !hasFinishedFirstRunTips && !showHomeTooltip {
                withAnimation(.spring()) {
                    showHomeTooltip = true
                }
            }
        }
        .background {
            Button("") {
                if !gopherItems.isEmpty {
                    showFindInPage = true
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()
        }
    }

    // MARK: - TUI Toolbar

    private var tuiToolbarView: some View {
        HStack(spacing: 8) {
            Button(action: onHome) {
                Label("Home", systemImage: "house")
            }
            .keyboardShortcut("r", modifiers: [.command])

            Button(action: goBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(backwardStack.count < 2)

            Button(action: goForward) {
                Label("Forward", systemImage: "chevron.right")
            }
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(forwardStack.isEmpty)

            TextField("Enter a URL", text: $url)
                .focused($isURLFocused)
                .textFieldStyle(.roundedBorder)

            Button(action: { showAddBookmark = true }) {
                Label("Add Bookmark", systemImage: "bookmark.fill")
            }
            .disabled(currentHost.isEmpty)

            Button(action: { showBookmarks = true }) {
                Label("Bookmarks", systemImage: "book")
            }

            Button(action: { showPreferences = true }) {
                Label("Settings", systemImage: "gear")
            }

            Button("Go", action: onGo)
                .buttonStyle(.liquidGlass)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func onGo() {
        performGopherRequest(clearForward: false)
    }

    private func onHome() {
        if showHomeTooltip {
            withAnimation(.spring()) {
                showHomeTooltip = false
            }
        }
        completeFirstRunExperience()
        performGopherRequest(
            host: homeURL.host ?? "gopher.navan.dev",
            port: homeURL.port ?? 70,
            selector: homeURL.path)
    }

    private func goBack() {
        if let curNode = backwardStack.popLast() {
            forwardStack.append(curNode)
            if let prevNode = backwardStack.popLast() {
                performGopherRequest(
                    host: prevNode.host, port: prevNode.port,
                    selector: prevNode.selector,
                    clearForward: false)
            }
        }
    }

    private func goForward() {
        if let nextNode = forwardStack.popLast() {
            performGopherRequest(
                host: nextNode.host, port: nextNode.port,
                selector: nextNode.selector,
                clearForward: false)
        }
    }

    private func completeFirstRunExperience() {
        guard !hasFinishedFirstRunTips else { return }
        hasFinishedFirstRunTips = true
        lastSeenWhatsNewVersion = WhatsNewConfig.currentVersion
    }

    private func performGopherRequest(
        host: String = "", port: Int = -1, selector: String = "", clearForward: Bool = true
    ) {
        var res = getHostAndPort(from: self.url)

        if host != "" {
            res.host = host
            if selector != "" {
                res.selector = selector
            } else {
                res.selector = ""
            }
        }

        if port != -1 {
            res.port = port
        }

        var finalSelector = res.selector
        if let decoded = finalSelector.removingPercentEncoding {
            finalSelector = decoded
        }

        if finalSelector.hasPrefix("/search") {
            if finalSelector.contains("\t") {
                res.selector = finalSelector
            } else {
                self.searchText = ""
                self.selectedSearchItem = nil
                self.directSearchContext = (host: res.host, port: res.port, selector: "/search")
                self.showSearchInput = true
                return
            }
        }

        self.url = "\(res.host):\(res.port)\(res.selector)"

        self.currentHost = res.host
        self.currentPort = res.port
        self.currentSelector = res.selector

        let myHost = res.host
        let myPort = res.port
        let mySelector = res.selector

        // Stub: return sample gopher menu for showcase.
        let resp = GopherClient.sampleMenu(host: myHost, port: myPort)

        var newNode = GopherNode(
            host: myHost, port: myPort, selector: mySelector, item: nil,
            children: convertToHostNodes(resp))

        backwardStack.append(newNode)
        if clearForward {
            forwardStack.removeAll()
        }

        if let index = self.hosts.firstIndex(where: {
            $0.host == myHost && $0.port == myPort
        }) {
            hosts[index].children = hosts[index].children?.map { child in
                if child.selector == newNode.selector {
                    newNode.message = child.message
                    return newNode
                } else {
                    return child
                }
            }
        } else {
            newNode.selector = "/"
            hosts.append(newNode)
        }

        self.gopherItems = resp
        scrollToTop.toggle()

        let historyItem = HistoryItem(
            title: "\(myHost)\(mySelector)",
            host: myHost,
            port: myPort,
            selector: mySelector
        )
        modelContext.insert(historyItem)
    }

    private func rowBackgroundColor(for idx: Int) -> Color? {
        if findMatches.contains(idx) {
            if crtMode {
                if findMatches.firstIndex(of: idx) == currentFindIndex {
                    return crtPhosphorColor.opacity(0.3)
                }
                return crtPhosphorColor.opacity(0.15)
            } else {
                if findMatches.firstIndex(of: idx) == currentFindIndex {
                    return Color.yellow.opacity(0.5)
                }
                return Color.yellow.opacity(0.2)
            }
        }

        return crtMode ? CRTTheme.screenBackground : nil
    }

    private func convertToHostNodes(_ responseItems: [gopherItem]) -> [GopherNode] {
        var returnItems: [GopherNode] = []
        responseItems.forEach { item in
            if item.parsedItemType != .info {
                returnItems.append(
                    GopherNode(
                        host: item.host, port: item.port, selector: item.selector,
                        message: item.message,
                        item: item, children: nil))
            }
        }
        return returnItems
    }
}

// MARK: - Home Tooltip

struct HomeButtonTooltipWrapper<Content: View>: View {
    @Binding var isVisible: Bool
    let message: String
    let onAutoDismiss: () -> Void
    private let content: () -> Content
    @State private var didScheduleDismiss = false

    init(
        isVisible: Binding<Bool>,
        message: String,
        onAutoDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isVisible = isVisible
        self.message = message
        self.onAutoDismiss = onAutoDismiss
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            content()

            if isVisible {
                HomeTooltipCard(message: message)
                    .offset(y: -72)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        scheduleAutoDismiss()
                    }
            }
        }
    }

    private func scheduleAutoDismiss() {
        guard !didScheduleDismiss else { return }
        didScheduleDismiss = true
        // Auto-dismiss is a visual nicety; skip in TUI stub to avoid concurrency issues.
    }
}

private struct HomeTooltipCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tip")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption)
                .multilineTextAlignment(.leading)
        }
        .padding(12)
        .frame(maxWidth: 220)
    }
}

// MARK: - Find in Page Bar

struct FindInPageBar: View {
    @Binding var findText: String
    @Binding var currentIndex: Int
    let totalMatches: Int
    var isFocused: FocusState<Bool>.Binding
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Find in page", text: $findText)
                    .textFieldStyle(.plain)
                    .focused(isFocused)

                if !findText.isEmpty {
                    Text("\(totalMatches > 0 ? currentIndex + 1 : 0)/\(totalMatches)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .cornerRadius(8)

            if !findText.isEmpty {
                Button {
                    if totalMatches > 0 {
                        currentIndex = (currentIndex - 1 + totalMatches) % totalMatches
                    }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(totalMatches == 0)

                Button {
                    if totalMatches > 0 {
                        currentIndex = (currentIndex + 1) % totalMatches
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(totalMatches == 0)
            }

            Button("Done", action: onDismiss)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            isFocused.wrappedValue = true
        }
    }
}
