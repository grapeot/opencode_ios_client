//
//  FileContentView.swift
//  OpenCodeClient
//

import SwiftUI

struct FileContentView: View {
    @Bindable var state: AppState
    let filePath: String
    @State private var content: String?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showPreview = true  // true = Markdown preview, false = raw/editor

    private var isMarkdown: Bool {
        filePath.lowercased().hasSuffix(".md") || filePath.lowercased().hasSuffix(".markdown")
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError {
                ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if let text = content {
                contentView(text: text)
            } else {
                ContentUnavailableView("No content", systemImage: "doc.text")
            }
        }
        .navigationTitle(filePath.split(separator: "/").last.map(String.init) ?? filePath)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isMarkdown {
                ToolbarItem(placement: .primaryAction) {
                    Button(showPreview ? "Markdown" : "Preview") {
                        showPreview.toggle()
                    }
                }
            }
        }
        .onAppear {
            loadContent()
        }
        .refreshable {
            loadContent()
        }
    }

    @ViewBuilder
    private func contentView(text: String) -> some View {
        if isMarkdown && showPreview {
            MarkdownPreviewView(text: text)
        } else {
            CodeView(text: text, path: filePath)
        }
    }

    private func loadContent() {
        isLoading = true
        loadError = nil
        print("[FileContentView] loadContent path=\(filePath)")
        Task {
            do {
                let fc = try await state.loadFileContent(path: filePath)
                await MainActor.run {
                    content = fc.text ?? fc.content
                    isLoading = false
                    print("[FileContentView] loaded type=\(fc.type) contentLen=\(content?.count ?? 0)")
                    if content == nil && fc.type == "binary" {
                        loadError = "Binary file"
                    }
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                    print("[FileContentView] load failed: \(error)")
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
            }
        }
    }
}

/// Markdown preview. 
///
/// Apple's AttributedString(markdown:) in SwiftUI Text ignores line breaks regardless
/// of parsing mode (.full, .inlineOnly, etc.). The only reliable workaround is to split
/// the text by newlines and render each line as its own Text(AttributedString) in a VStack.
struct MarkdownPreviewView: View {
    let text: String

    private var lines: [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let result = normalized.components(separatedBy: "\n")
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        // Empty line → render as spacing
                        Spacer().frame(height: 8)
                    } else if let attr = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .full)) {
                        Text(attr)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(line)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .onAppear {
            print("[MarkdownPreview] text length: \(text.count)")
            print("[MarkdownPreview] lines count: \(lines.count)")
            print("[MarkdownPreview] contains \\n: \(text.contains("\n"))")
            print("[MarkdownPreview] contains \\r\\n: \(text.contains("\r\n"))")
            print("[MarkdownPreview] contains literal \\\\n: \(text.contains("\\n"))")
            if text.count > 200 {
                let preview = String(text.prefix(200))
                print("[MarkdownPreview] first 200 chars: \(preview.debugDescription)")
            } else {
                print("[MarkdownPreview] full text: \(text.debugDescription)")
            }
        }
    }
}
