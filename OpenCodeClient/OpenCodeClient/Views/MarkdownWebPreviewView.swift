//
//  MarkdownWebPreviewView.swift
//  OpenCodeClient
//
//  WebView-based Markdown preview. Loads a bundled local HTML/JS/CSS shell
//  (preview.html + markdown-it + DOMPurify) into a WKWebView and renders the
//  Markdown via window.renderMarkdown({markdown, theme}). The shell is the
//  gatekeeper: markdown-it parses, DOMPurify sanitizes. No network at render
//  time; all renderer assets ship in the app bundle.
//
//  See docs/Markdown_Web_Preview_RFC.md.
//

import SwiftUI
import WebKit
import MarkdownUI

/// Input payload for the web preview. `markdown` is expected to already have its
/// relative image references resolved to data URIs by the caller (Phase 1 reuses
/// `MarkdownImageResolver`), so the shell does not need filesystem access.
struct MarkdownWebPreviewInput: Equatable {
    let markdown: String
    let colorScheme: ColorScheme
}

/// SwiftUI host for the web preview. Resolves relative image paths to data URIs
/// (reusing `MarkdownImageResolver`, so semantics match Native Preview), manages
/// loading / error / oversize states, and surfaces fallbacks to Native or Source.
struct MarkdownWebPreviewContainer: View {
    let text: String
    let state: AppState
    let markdownFilePath: String?
    let workspaceDirectory: String?
    /// Whether the content exceeds the size the native renderer trusts; the web
    /// renderer can still attempt it, but we warn first to avoid a huge payload.
    var isOversized: Bool = false
    var onSwitchToNative: (() -> Void)?
    var onSwitchToSource: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var resolvedMarkdown: String?
    @State private var renderError: String?
    @State private var linkError: String?
    @State private var proceedDespiteSize = false

    var body: some View {
        Group {
            if isOversized && !proceedDespiteSize {
                oversizeGate
            } else if let error = renderError {
                errorState(error)
            } else if let resolved = resolvedMarkdown {
                MarkdownWebPreviewView(
                    input: MarkdownWebPreviewInput(markdown: resolved, colorScheme: colorScheme),
                    onOpenExternalURL: { url in openURL(url) },
                    onOpenRelativePath: { href in openWorkspacePath(href) },
                    onOpenImage: { _ in /* Phase 3: dedicated image preview */ },
                    onError: { message in renderError = message }
                )
            } else {
                ProgressView(L10n.t(.markdownWebPreviewLoading))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: resolveTaskID) {
            guard !isOversized || proceedDespiteSize else { return }
            renderError = nil
            resolvedMarkdown = nil
            let source = text
            let resolved = await MarkdownImageResolver.resolveImages(
                in: source,
                markdownFilePath: markdownFilePath,
                workspaceDirectory: workspaceDirectory,
                fetchContent: { path in try await state.loadFileContent(path: path, workspaceDirectory: workspaceDirectory) }
            )
            guard !Task.isCancelled, source == text else { return }
            resolvedMarkdown = resolved
        }
        .alert(L10n.t(.appError), isPresented: Binding(
            get: { linkError != nil },
            set: { if !$0 { linkError = nil } }
        )) {
            Button(L10n.t(.commonOk)) { linkError = nil }
        } message: {
            if let linkError { Text(linkError) }
        }
    }

    private var resolveTaskID: String {
        "\(markdownFilePath ?? ""):\(proceedDespiteSize):\(text.hashValue)"
    }

    /// Resolve a workspace-relative link tapped in the preview and route it into
    /// the app's Files preview (same target the Chat→file jump uses). Fragment-only
    /// hrefs are ignored (the WebView scrolls in place).
    private func openWorkspacePath(_ href: String) {
        switch WorkspaceLinkResolver.resolve(href, workspaceDirectory: workspaceDirectory, baseFilePath: markdownFilePath) {
        case .external(let url):
            openURL(url)
        case .file(let path):
            state.fileToOpenInFilesTab = path
            state.fileToOpenInFilesTabWorkspaceDirectory = workspaceDirectory
        case .fragmentOnly:
            return
        case .rejected(let reason):
            linkError = reason
        }
    }

    private var oversizeGate: some View {
        ContentUnavailableView {
            Label(L10n.t(.markdownWebPreviewLargeDocumentTitle), systemImage: "exclamationmark.triangle")
        } description: {
            Text(L10n.t(.markdownWebPreviewLargeDocumentDescription))
        } actions: {
            Button(L10n.t(.markdownWebPreviewRenderAnyway)) { proceedDespiteSize = true }
            Button(L10n.t(.markdownWebPreviewOpenNative)) { onSwitchToNative?() }
            Button(L10n.t(.markdownWebPreviewOpenSource)) { onSwitchToSource?() }
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label(L10n.t(.markdownWebPreviewFailedTitle), systemImage: "xmark.octagon")
        } description: {
            Text(message)
        } actions: {
            Button(L10n.t(.markdownWebPreviewOpenNative)) { onSwitchToNative?() }
            Button(L10n.t(.markdownWebPreviewOpenSource)) { onSwitchToSource?() }
            Button(L10n.t(.commonRetry)) {
                renderError = nil
                resolvedMarkdown = nil
            }
        }
    }
}

/// Bridge message names exposed to the JS shell.
private enum PreviewBridge {
    static let name = "previewBridge"
}

struct MarkdownWebPreviewView: UIViewRepresentable {
    let input: MarkdownWebPreviewInput
    /// Called when the user taps an external (http/https) link in the preview.
    var onOpenExternalURL: ((URL) -> Void)?
    /// Called when the user taps a workspace-relative link in the preview.
    var onOpenRelativePath: ((String) -> Void)?
    /// Called when the user taps an image in the preview.
    var onOpenImage: ((String) -> Void)?
    /// Called when the shell reports a render error or the bundle fails to load.
    var onError: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Non-persistent store: no cookies/localStorage survive across loads.
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: PreviewBridge.name)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.accessibilityIdentifier = "markdown-web-preview-webview"

        context.coordinator.webView = webView
        context.coordinator.loadShell()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(input: input)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: PreviewBridge.name)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebPreviewView
        weak var webView: WKWebView?

        private var shellLoaded = false
        private var pendingInput: MarkdownWebPreviewInput?
        private var lastRenderedInput: MarkdownWebPreviewInput?

        init(parent: MarkdownWebPreviewView) {
            self.parent = parent
        }

        /// Locate the bundled preview.html. Resources may be flattened by the
        /// synchronized-folder build, so try the structured location first and
        /// fall back to a flat lookup.
        private func shellURL() -> URL? {
            let bundle = Bundle.main
            if let url = bundle.url(forResource: "preview", withExtension: "html", subdirectory: "WebPreview") {
                return url
            }
            return bundle.url(forResource: "preview", withExtension: "html")
        }

        func loadShell() {
            guard let webView else { return }
            guard let html = shellURL() else {
                parent.onError?(L10n.t(.markdownWebPreviewAssetsMissing))
                return
            }
            // Grant read access to the shell's directory so relative vendor/css/js
            // (and any sibling assets) resolve from file://.
            let readAccess = html.deletingLastPathComponent()
            webView.loadFileURL(html, allowingReadAccessTo: readAccess)
        }

        /// Render markdown into the shell. If the shell isn't ready yet, stash the
        /// input and render once `didFinish` fires.
        func render(input: MarkdownWebPreviewInput) {
            guard shellLoaded else {
                pendingInput = input
                return
            }
            guard input != lastRenderedInput else { return }
            lastRenderedInput = input
            evaluateRender(input)
        }

        private func evaluateRender(_ input: MarkdownWebPreviewInput) {
            guard let webView else { return }
            let payload: [String: Any] = [
                "markdown": input.markdown,
                "theme": input.colorScheme == .dark ? "dark" : "light",
            ]
            guard
                let data = try? JSONSerialization.data(withJSONObject: payload),
                let json = String(data: data, encoding: .utf8)
            else {
                parent.onError?(L10n.t(.markdownWebPreviewPayloadEncodeFailed))
                return
            }
            // JSON-encode the payload; never string-concatenate raw markdown.
            let js = "window.renderMarkdown(\(json));"
            webView.evaluateJavaScript(js) { [weak self] _, error in
                if let error {
                    self?.parent.onError?(L10n.t(.markdownWebPreviewRenderCallFailed, error.localizedDescription))
                }
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            shellLoaded = true
            if let pending = pendingInput {
                pendingInput = nil
                lastRenderedInput = pending
                evaluateRender(pending)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onError?(L10n.t(.markdownWebPreviewWebViewLoadFailed, error.localizedDescription))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onError?(L10n.t(.markdownWebPreviewWebViewProvisionalLoadFailed, error.localizedDescription))
        }

        /// Block all navigation except the initial local shell load and in-page
        /// fragment anchors. Link taps are routed via the JS bridge instead.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            // Allow the initial file:// shell load.
            if url.isFileURL {
                decisionHandler(.allow)
                return
            }
            // Allow in-page fragment scrolling.
            if navigationAction.navigationType == .other && url.absoluteString == webView.url?.absoluteString {
                decisionHandler(.allow)
                return
            }
            if url.fragment != nil, url.scheme == nil || url.isFileURL {
                decisionHandler(.allow)
                return
            }
            // Everything else (clicked links etc.) is blocked; the JS bridge has
            // already routed the tap to the app.
            decisionHandler(.cancel)
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == PreviewBridge.name,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "link":
                guard let href = body["href"] as? String, !href.isEmpty else { return }
                if let url = URL(string: href), let scheme = url.scheme?.lowercased(),
                   scheme == "http" || scheme == "https" {
                    parent.onOpenExternalURL?(url)
                } else {
                    parent.onOpenRelativePath?(href)
                }
            case "image":
                guard let src = body["src"] as? String, !src.isEmpty else { return }
                parent.onOpenImage?(src)
            case "error":
                let detail = (body["message"] as? String) ?? L10n.t(.markdownWebPreviewUnknownRenderError)
                parent.onError?(detail)
            default:
                break
            }
        }
    }
}

#if DEBUG
/// Test-only host that exercises the 3-mode preview switch (native / web / source)
/// over a self-contained markdown string, mirroring FileContentView's menu and
/// dispatch without needing a live server. Gated by UITEST_WEB_PREVIEW_MODE_FIXTURE.
struct WebPreviewModeFixtureHost: View {
    let markdown: String
    @State private var mode: MarkdownPreviewMode = .web
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            switch mode {
            case .native:
                ScrollView { Markdown(markdown).padding() }
                    .accessibilityIdentifier("fixture-native-preview")
            case .web:
                MarkdownWebPreviewView(
                    input: MarkdownWebPreviewInput(markdown: markdown, colorScheme: colorScheme)
                )
                .accessibilityIdentifier("markdown-web-preview-webview")
            case .source:
                ScrollView {
                    Text(markdown)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .accessibilityIdentifier("fixture-source-view")
            }
        }
        .navigationTitle("Fixture.md")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Preview Mode", selection: $mode) {
                        ForEach(MarkdownPreviewMode.allCases, id: \.self) { m in
                            Label(m.label, systemImage: m.menuSystemImage).tag(m)
                        }
                    }
                } label: {
                    Image(systemName: mode.menuSystemImage)
                }
                .accessibilityIdentifier("markdown-preview-mode-menu")
            }
        }
    }
}
#endif
