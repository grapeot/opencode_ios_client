//
//  MarkdownWebPreviewPathTests.swift
//  OpenCodeClientTests
//
//  Layer 1 deterministic tests for relative-reference resolution used by the
//  Markdown Web Preview (and shared with Native Preview image resolution).
//  Covers same-dir, subdir, `../` parent traversal, and workspace-absolute paths.
//

import Foundation
import Testing
@testable import OpenCodeClient

struct MarkdownWebPreviewPathTests {

    private let workspace = "/Users/me/project"
    private let mdPath = "/Users/me/project/docs/report.md"

    @Test func sameDirectoryReference() {
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "chart.png", markdownFilePath: mdPath, workspaceDirectory: workspace
        )
        // docs/report.md + chart.png -> docs/chart.png (workspace-relative)
        #expect(resolved == "docs/chart.png")
    }

    @Test func subdirectoryReference() {
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "images/chart.png", markdownFilePath: mdPath, workspaceDirectory: workspace
        )
        #expect(resolved == "docs/images/chart.png")
    }

    @Test func dotSlashReferenceIsStripped() {
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "./images/chart.png", markdownFilePath: mdPath, workspaceDirectory: workspace
        )
        #expect(resolved == "docs/images/chart.png")
    }

    @Test func parentTraversalReference() {
        // docs/report.md + ../images/chart.png -> images/chart.png
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "../images/chart.png", markdownFilePath: mdPath, workspaceDirectory: workspace
        )
        #expect(resolved == "images/chart.png")
    }

    @Test func deepParentTraversalReference() {
        let deepMd = "/Users/me/project/docs/sub/nested.md"
        // docs/sub/nested.md + ../../assets/x.png -> assets/x.png
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "../../assets/x.png", markdownFilePath: deepMd, workspaceDirectory: workspace
        )
        #expect(resolved == "assets/x.png")
    }

    @Test func workspaceAbsoluteReference() {
        // An absolute path under the workspace is made workspace-relative.
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "/Users/me/project/shared/logo.svg", markdownFilePath: mdPath, workspaceDirectory: workspace
        )
        #expect(resolved == "shared/logo.svg")
    }

    @Test func absoluteOutsideWorkspaceIsNormalizedButNotRelativized() {
        // Outside the workspace: normalize() strips the leading slash but cannot
        // make it workspace-relative (no shared prefix).
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "/etc/hosts", markdownFilePath: mdPath, workspaceDirectory: workspace
        )
        #expect(resolved == "etc/hosts")
    }

    @Test func nilMarkdownPathKeepsReferenceWorkspaceRelative() {
        // Without a markdown file path we cannot anchor to its directory; the
        // reference is only workspace-normalized.
        let resolved = MarkdownImageResolver.resolveRelativeReference(
            "images/chart.png", markdownFilePath: nil, workspaceDirectory: workspace
        )
        #expect(resolved == "images/chart.png")
    }
}
