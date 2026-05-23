//
//  FileContentView.swift
//  OpenCodeClient
//

import SwiftUI
import MarkdownUI

enum ImageFileUtils {
    static let extensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif", "ico", "svg",
    ]

    static func isImage(_ path: String) -> Bool {
        let ext = path.lowercased().split(separator: ".").last.map(String.init) ?? ""
        return extensions.contains(ext)
    }
}

struct FileContentView: View {
    @Bindable var state: AppState
    let filePath: String
    @State private var content: String?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showPreview = true

    private var isImage: Bool {
        ImageFileUtils.isImage(filePath)
    }

    private var isMarkdown: Bool {
        filePath.lowercased().hasSuffix(".md") || filePath.lowercased().hasSuffix(".markdown")
    }

    private var fileName: String {
        filePath.split(separator: "/").last.map(String.init) ?? filePath
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let content {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: content, subject: Text(fileName)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        if let imageData, let uiImage = UIImage(data: imageData) {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: Image(uiImage: uiImage),
                    preview: SharePreview(fileName, image: Image(uiImage: uiImage))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        if isMarkdown {
            ToolbarItem(placement: .primaryAction) {
                Button(showPreview ? "Markdown" : "Preview") {
                    showPreview.toggle()
                }
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let data = imageData, let uiImage = UIImage(data: data) {
                ImageView(uiImage: uiImage)
            } else if let text = content {
                contentView(text: text)
            } else {
                ContentUnavailableView("No content", systemImage: "doc.text")
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear {
            loadContent()
        }
        .refreshable {
            loadContent()
        }
    }

    /// MarkdownUI crashes/freezes on long lines or large content. Skip it entirely for problematic files.
    private static let markdownMaxLineLength = 5000
    private static let markdownMaxTotalLength = 60_000

    private func useRawTextForMarkdown(_ text: String) -> Bool {
        let stats = MarkdownPreviewView.diagnostics(for: text)
        return text.count > Self.markdownMaxTotalLength || stats.maxLineLength > Self.markdownMaxLineLength
    }

    @ViewBuilder
    private func contentView(text: String) -> some View {
        let useRaw = isMarkdown ? useRawTextForMarkdown(text) : false
        if isMarkdown {
            if showPreview && !useRaw {
                MarkdownPreviewView(
                    text: text,
                    state: state,
                    markdownFilePath: filePath,
                    workspaceDirectory: state.currentSession?.directory
                )
            } else {
                RawTextView(text: text, monospaced: !showPreview)
            }
        } else {
            CodeView(text: text, path: filePath)
        }
    }

    private func loadContent() {
        isLoading = true
        loadError = nil
        imageData = nil
        content = nil
        Task {
            do {
                let fc = try await state.loadFileContent(path: filePath)
                await MainActor.run {
                    if isImage {
                        if let rawContent = fc.content {
                            if let data = Data(base64Encoded: rawContent), UIImage(data: data) != nil {
                                imageData = data
                            } else {
                                let cleaned = rawContent
                                    .replacingOccurrences(of: "\n", with: "")
                                    .replacingOccurrences(of: "\r", with: "")
                                    .replacingOccurrences(of: " ", with: "")
                                if let data = Data(base64Encoded: cleaned), UIImage(data: data) != nil {
                                    imageData = data
                                } else {
                                    loadError = "Failed to decode image"
                                }
                            }
                        } else {
                            loadError = "No image data"
                        }
                    } else if let text = fc.text {
                        content = text
                    } else if fc.content != nil, fc.type == "binary" {
                        loadError = "Binary file"
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

/// Simple code view with line numbers
struct CodeView: View {
    let text: String
    let path: String

    private var lines: [String] {
        text.components(separatedBy: .newlines)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        HStack(alignment: .top, spacing: DesignSpacing.sm) {
                            Text("\(i + 1)")
                                .font(DesignTypography.microMono)
                                .foregroundStyle(DesignColors.Neutral.textSecondary)
                                .frame(width: 36, alignment: .trailing)
                            Text(line)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, DesignSpacing.sm)
                .frame(minWidth: 400, alignment: .leading)
            }
        }
    }
}

/// Markdown preview using MarkdownUI library for full GFM rendering.
/// Parent FileContentView skips this for large content; this is a secondary fallback.
struct MarkdownPreviewView: View {
    let text: String
    let state: AppState
    let markdownFilePath: String?
    let workspaceDirectory: String?
    @State private var resolvedPreviewText: String?

    private static let maxLineLength = 5000
    private static let maxTotalLength = 60_000

    struct Diagnostics {
        let lineCount: Int
        let maxLineLength: Int
        let markdownImageCount: Int
        let htmlImageCount: Int
        let htmlFigureCount: Int
        let dataURLCount: Int
        let httpURLCount: Int
        let firstImageReference: String?
    }

    static func diagnostics(for text: String) -> Diagnostics {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let maxLine = lines.map(\.count).max() ?? 0
        return Diagnostics(
            lineCount: lines.count,
            maxLineLength: maxLine,
            markdownImageCount: countOccurrences(of: "![", in: text),
            htmlImageCount: countOccurrences(of: "<img", in: text),
            htmlFigureCount: countOccurrences(of: "<figure", in: text),
            dataURLCount: countOccurrences(of: "data:image", in: text),
            httpURLCount: countOccurrences(of: "http://", in: text) + countOccurrences(of: "https://", in: text),
            firstImageReference: firstImageReference(in: text)
        )
    }

    private static func countOccurrences(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var searchStart = text.startIndex
        while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func firstImageReference(in text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("![") || trimmed.hasPrefix("<img") || trimmed.hasPrefix("<figure") || trimmed.hasPrefix("<a ") {
                return String(trimmed.prefix(240))
            }
        }
        return nil
    }

    private var useRawTextFallback: Bool {
        let stats = Self.diagnostics(for: text)
        return text.count > Self.maxTotalLength || stats.maxLineLength > Self.maxLineLength
    }

    static func normalizeStandaloneImageBlocks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }

        var normalized: [String] = []
        normalized.reserveCapacity(lines.count)

        for index in lines.indices {
            let line = lines[index]
            normalized.append(line)

            guard isStandaloneMarkdownImageLine(line) else { continue }
            guard index + 1 < lines.count else { continue }

            let nextLine = lines[index + 1]
            if !nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
                normalized.append("")
            }
        }

        return normalized.joined(separator: "\n")
    }

    private static func isStandaloneMarkdownImageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("!["), trimmed.hasSuffix(")") else { return false }
        guard let closeAlt = trimmed.firstIndex(of: "]") else { return false }
        let afterAlt = trimmed[trimmed.index(after: closeAlt)...]
        return afterAlt.hasPrefix("(") && !afterAlt.dropFirst().isEmpty
    }

    var body: some View {
        let previewText = Self.normalizeStandaloneImageBlocks(text)
        let displayText = resolvedPreviewText ?? previewText
        ScrollView {
            Group {
                if useRawTextFallback {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if resolvedPreviewText == nil {
                    ProgressView("Loading preview...")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Markdown(
                        displayText,
                        imageBaseURL: WorkspaceMarkdownImageProvider.imageBaseURL(markdownFilePath: markdownFilePath)
                    )
                        .markdownImageProvider(
                            WorkspaceMarkdownImageProvider(
                                loadFileContent: { pathBytes in try await state.loadFileContent(pathBytes: pathBytes) },
                                workspaceDirectory: workspaceDirectory
                            )
                        )
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .task(id: "\(markdownFilePath ?? ""):\(previewText.hashValue)") {
            guard !useRawTextFallback else { return }
            resolvedPreviewText = nil
            let sourceText = previewText
            let resolved = await MarkdownImageResolver.resolveImages(
                in: sourceText,
                markdownFilePath: markdownFilePath,
                workspaceDirectory: workspaceDirectory,
                fetchContent: { path in try await state.loadFileContent(path: path) }
            )
            guard !Task.isCancelled, sourceText == Self.normalizeStandaloneImageBlocks(text) else { return }
            resolvedPreviewText = resolved
        }
    }
}

/// Raw text view for Markdown source (wraps to fill available width).
struct RawTextView: View {
    let text: String
    var monospaced: Bool = false

    var body: some View {
        ScrollView {
            Text(text)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }
}

struct ImageView: View {
    let uiImage: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let fittedSize = fittedImageSize(in: geometry.size)
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: fittedSize.width, height: fittedSize.height)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 0.5), 5.0)
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.2)) {
                                if scale < 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    lastScale = scale
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                if scale > 1.01 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    let native = nativeScale(in: geometry.size)
                                    scale = min(max(native, 2.0), 5.0)
                                    lastScale = scale
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                )
        }
    }

    private func fittedImageSize(in geoSize: CGSize) -> CGSize {
        let imageSize = uiImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return geoSize }
        let ratio = min(geoSize.width / imageSize.width, geoSize.height / imageSize.height)
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }

    private func nativeScale(in geoSize: CGSize) -> CGFloat {
        let imageSize = uiImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return 2.0 }
        let fitRatio = min(geoSize.width / imageSize.width, geoSize.height / imageSize.height)
        return 1.0 / fitRatio
    }
}
