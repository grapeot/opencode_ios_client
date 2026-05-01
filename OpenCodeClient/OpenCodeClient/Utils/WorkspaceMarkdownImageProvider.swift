import Foundation
#if !os(visionOS)
import MarkdownUI
import NetworkImage
import SwiftUI

struct WorkspaceMarkdownImageProvider: ImageProvider {
    let loadFileContent: @Sendable (String) async throws -> FileContent
    let workspaceDirectory: String?

    func makeImage(url: URL?) -> some View {
        WorkspaceMarkdownImageView(url: url, loadFileContent: loadFileContent, workspaceDirectory: workspaceDirectory)
    }

    static func imageBaseURL(markdownFilePath: String?) -> URL? {
        guard let markdownFilePath, !markdownFilePath.isEmpty else { return nil }
        let dir = PathNormalizer.normalize((markdownFilePath as NSString).deletingLastPathComponent)
        var components = URLComponents()
        components.scheme = "opencode-workspace"
        components.host = "workspace"
        components.path = "/\(dir)"
        if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        return components.url
    }

    static func workspaceRelativePath(from url: URL?, workspaceDirectory: String? = nil) -> String? {
        guard let url else { return nil }
        if url.scheme == "opencode-workspace" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalized = PathNormalizer.resolveWorkspaceRelativePath(path, workspaceDirectory: workspaceDirectory)
            return normalized.isEmpty ? nil : normalized
        }
        if url.scheme == nil {
            let normalized = PathNormalizer.resolveWorkspaceRelativePath(url.absoluteString, workspaceDirectory: workspaceDirectory)
            return normalized.isEmpty ? nil : normalized
        }
        return nil
    }

    static func decodeBase64ImageData(_ raw: String?) -> Data? {
        guard let raw, !raw.isEmpty else { return nil }
        if let data = Data(base64Encoded: raw), UIImage(data: data) != nil {
            return data
        }
        let cleaned = raw
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let data = Data(base64Encoded: cleaned), UIImage(data: data) != nil else { return nil }
        return data
    }

    static func decodeDataURL(_ url: URL?) -> Data? {
        guard let raw = url?.absoluteString, raw.hasPrefix("data:") else { return nil }
        guard let comma = raw.firstIndex(of: ",") else { return nil }
        let metadata = raw[..<comma]
        let payload = String(raw[raw.index(after: comma)...])
        guard metadata.contains(";base64") else { return nil }
        return decodeBase64ImageData(payload.removingPercentEncoding ?? payload)
    }
}

private struct WorkspaceMarkdownImageView: View {
    let url: URL?
    let loadFileContent: @Sendable (String) async throws -> FileContent
    let workspaceDirectory: String?

    @State private var imageData: Data?
    @State private var didAttemptLoad = false
    @State private var showImageSheet = false

    private var decodedUIImage: UIImage? {
        imageData.flatMap(UIImage.init(data:))
    }

    private var imageDisplayName: String {
        if let path = WorkspaceMarkdownImageProvider.workspaceRelativePath(from: url, workspaceDirectory: workspaceDirectory) {
            return URL(fileURLWithPath: path).lastPathComponent
        }
        if let url {
            return url.lastPathComponent.isEmpty ? "Image" : url.lastPathComponent
        }
        return "Image"
    }

    var body: some View {
        Group {
            if let uiImage = decodedUIImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("[WorkspaceMarkdownImageProvider] tapped image name=\(imageDisplayName)")
                        showImageSheet = true
                    }
            } else if let url, let scheme = url.scheme, scheme == "http" || scheme == "https" {
                NetworkImage(url: url) { state in
                    switch state {
                    case .empty, .failure:
                        Color.clear.frame(width: 0, height: 0)
                    case .success(let image, _):
                        image.resizable().aspectRatio(contentMode: .fit)
                    }
                }
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .sheet(isPresented: $showImageSheet) {
            if let uiImage = decodedUIImage {
                NavigationStack {
                    ImageView(uiImage: uiImage)
                        .navigationTitle(imageDisplayName)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                ShareLink(
                                    item: Image(uiImage: uiImage),
                                    preview: SharePreview(imageDisplayName, image: Image(uiImage: uiImage))
                                ) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    showImageSheet = false
                                }
                            }
                        }
                }
            }
        }
        .task(id: url?.absoluteString) {
            guard !didAttemptLoad else { return }
            didAttemptLoad = true

            if let data = WorkspaceMarkdownImageProvider.decodeDataURL(url) {
                imageData = data
                return
            }

            guard let path = WorkspaceMarkdownImageProvider.workspaceRelativePath(from: url, workspaceDirectory: workspaceDirectory) else {
                if let url {
                    print("[WorkspaceMarkdownImageProvider] unsupported image url=\(url.absoluteString)")
                }
                return
            }

            do {
                print("[WorkspaceMarkdownImageProvider] load local image path=\(path)")
                let content = try await loadFileContent(path)
                guard let data = WorkspaceMarkdownImageProvider.decodeBase64ImageData(content.content) else {
                    print("[WorkspaceMarkdownImageProvider] failed to decode image path=\(path) type=\(content.type)")
                    return
                }
                imageData = data
                print("[WorkspaceMarkdownImageProvider] loaded local image path=\(path) bytes=\(data.count)")
            } catch {
                print("[WorkspaceMarkdownImageProvider] failed to load local image path=\(path) error=\(error.localizedDescription)")
            }
        }
    }
}
#endif
