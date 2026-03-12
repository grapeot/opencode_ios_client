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
    private static let markdownMaxLineLength = 1500
    private static let markdownMaxTotalLength = 60_000

    private func useRawTextForMarkdown(_ text: String) -> Bool {
        if text.count > Self.markdownMaxTotalLength { return true }
        let maxLine = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(\.count).max() ?? 0
        return maxLine > Self.markdownMaxLineLength
    }

    @ViewBuilder
    private func contentView(text: String) -> some View {
        let useRaw = isMarkdown ? useRawTextForMarkdown(text) : false
        if isMarkdown {
            if showPreview && !useRaw {
                MarkdownPreviewView(text: text)
            } else {
                RawTextView(text: text, monospaced: !showPreview)
            }
        } else {
            CodeView(text: text, path: filePath)
        }
    }

    private func loadContent() {
        print("[FileContentView] loadContent: path=\(filePath)")
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
                        print("[FileContentView] loaded text: len=\(text.count) isMarkdown=\(isMarkdown)")
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
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
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
                .padding(.vertical, 8)
                .frame(minWidth: 400, alignment: .leading)
            }
        }
    }
}

/// Markdown preview using MarkdownUI library for full GFM rendering.
/// Parent FileContentView skips this for large content; this is a secondary fallback.
struct MarkdownPreviewView: View {
    let text: String

    private static let maxLineLength = 1500
    private static let maxTotalLength = 60_000

    private var useRawTextFallback: Bool {
        if text.count > Self.maxTotalLength { return true }
        let maxLine = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(\.count).max() ?? 0
        return maxLine > Self.maxLineLength
    }

    var body: some View {
        ScrollView {
            Group {
                if useRawTextFallback {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Markdown(text)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .onAppear {
            let fallback = useRawTextFallback
            print("[MarkdownPreviewView] onAppear len=\(text.count) useRawTextFallback=\(fallback)")
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
