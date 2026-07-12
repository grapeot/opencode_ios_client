import Foundation
import Testing
@testable import OpenCodeClient

struct WorkspaceLinkResolverTests {
    private let workspace = "/Users/me/project"

    @Test func httpAndHttpsOpenExternally() throws {
        #expect(WorkspaceLinkResolver.resolve("https://example.com/a", workspaceDirectory: workspace) == .external(try #require(URL(string: "https://example.com/a"))))
        #expect(WorkspaceLinkResolver.resolve("http://example.com/a", workspaceDirectory: workspace) == .external(try #require(URL(string: "http://example.com/a"))))
    }

    @Test func httpDoesNotRequireWorkspaceDirectory() throws {
        #expect(WorkspaceLinkResolver.resolve("https://example.com/a", workspaceDirectory: nil) == .external(try #require(URL(string: "https://example.com/a"))))
    }

    @Test func relativeLinksResolveFromWorkspaceRoot() {
        #expect(WorkspaceLinkResolver.resolve("README.md", workspaceDirectory: workspace) == .file(path: "README.md"))
        #expect(WorkspaceLinkResolver.resolve("./docs/a.md", workspaceDirectory: workspace) == .file(path: "docs/a.md"))
    }

    @Test func relativeLinksResolveFromMarkdownFileDirectory() {
        let result = WorkspaceLinkResolver.resolve(
            "../README.md",
            workspaceDirectory: workspace,
            baseFilePath: "/Users/me/project/docs/a.md"
        )
        #expect(result == .file(path: "README.md"))
    }

    @Test func absoluteWorkspacePathBecomesWorkspaceRelative() {
        #expect(
            WorkspaceLinkResolver.resolve("/Users/me/project/docs/a.md", workspaceDirectory: workspace) == .file(path: "docs/a.md")
        )
    }

    @Test func fileURLInsideWorkspaceOpensFile() {
        #expect(
            WorkspaceLinkResolver.resolve("file:///Users/me/project/docs/a.md", workspaceDirectory: workspace) == .file(path: "docs/a.md")
        )
        #expect(
            WorkspaceLinkResolver.resolve("file://localhost/Users/me/project/docs/a.md", workspaceDirectory: workspace) == .file(path: "docs/a.md")
        )
    }

    @Test func fileURLWithNonLocalhostAuthorityIsRejected() {
        guard case .rejected = WorkspaceLinkResolver.resolve("file://example.com/Users/me/project/docs/a.md", workspaceDirectory: workspace) else {
            Issue.record("Expected non-localhost file URL authority to be rejected")
            return
        }
    }

    @Test func fragmentOnlyDoesNotRequestFile() {
        #expect(WorkspaceLinkResolver.resolve("#intro", workspaceDirectory: workspace) == .fragmentOnly)
    }

    @Test func fileAnchorOpensFile() {
        #expect(WorkspaceLinkResolver.resolve("README.md#intro", workspaceDirectory: workspace) == .file(path: "README.md"))
    }

    @Test func relativeTraversalOutsideWorkspaceIsRejected() {
        guard case .rejected = WorkspaceLinkResolver.resolve("../secret.md", workspaceDirectory: workspace) else {
            Issue.record("Expected workspace escape to be rejected")
            return
        }
    }

    @Test func encodedTraversalIsRejected() {
        guard case .rejected = WorkspaceLinkResolver.resolve("%2e%2e/secret.md", workspaceDirectory: workspace) else {
            Issue.record("Expected encoded traversal to be rejected")
            return
        }
    }

    @Test func prefixCollisionAbsolutePathIsRejected() {
        guard case .rejected = WorkspaceLinkResolver.resolve("/Users/me/project-other/README.md", workspaceDirectory: workspace) else {
            Issue.record("Expected prefix collision outside workspace to be rejected")
            return
        }
    }

    @Test func unsafeAndUnknownSchemesAreRejected() {
        for href in ["javascript:alert(1)", "data:text/plain,hi", "ftp://example.com/a"] {
            guard case .rejected = WorkspaceLinkResolver.resolve(href, workspaceDirectory: workspace) else {
                Issue.record("Expected \(href) to be rejected")
                return
            }
        }
    }
}
