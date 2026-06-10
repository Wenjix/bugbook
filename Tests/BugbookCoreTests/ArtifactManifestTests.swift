import XCTest
@testable import BugbookCore

final class ArtifactManifestTests: XCTestCase {
    private let happyPath = """
    <!doctype html>
    <html><head>
    <meta charset="utf-8">
    <meta name="bugbook-artifact" content="1">
    <meta name="bugbook-title" content="Sleep Trends — 2026-W23">
    <meta name="bugbook-icon" content="sf:bed.double">
    <meta name="bugbook-generator" content="claude-code/wreview">
    </head><body></body></html>
    """

    func testParsesMarkerTitleIconGenerator() {
        let manifest = ArtifactManifest.parse(happyPath)
        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.version, 1)
        XCTAssertEqual(manifest?.title, "Sleep Trends — 2026-W23")
        XCTAssertEqual(manifest?.icon, "sf:bed.double")
        XCTAssertEqual(manifest?.generator, "claude-code/wreview")
        XCTAssertEqual(manifest?.hasCapabilityBlock, false)
        XCTAssertNil(manifest?.capabilities)
    }

    func testReturnsNilWithoutMarker() {
        let html = #"<html><head><meta name="bugbook-title" content="X"></head></html>"#
        XCTAssertNil(ArtifactManifest.parse(html))
        XCTAssertNil(ArtifactManifest.parse(""))
    }

    func testMarkerVersionParsing() {
        XCTAssertEqual(ArtifactManifest.parse(#"<meta name="bugbook-artifact" content="2">"#)?.version, 2)
        XCTAssertEqual(ArtifactManifest.parse(#"<meta name="bugbook-artifact" content="abc">"#)?.version, 1)
    }

    func testAttributeOrderReversed() {
        let html = #"<meta name="bugbook-artifact" content="1"><meta content="Reversed" name="bugbook-title">"#
        XCTAssertEqual(ArtifactManifest.parse(html)?.title, "Reversed")
    }

    func testSingleQuotedAndCaseInsensitive() {
        let html = "<META NAME='bugbook-artifact' CONTENT='1'><meta name='bugbook-title' content='Single'>"
        let manifest = ArtifactManifest.parse(html)
        XCTAssertEqual(manifest?.version, 1)
        XCTAssertEqual(manifest?.title, "Single")
    }

    func testIgnoresTagsBeyond4KBoundary() {
        let padding = String(repeating: "<!-- padding -->", count: 300)  // 4,800 bytes
        let html = #"<meta name="bugbook-artifact" content="1">"# + padding
            + #"<meta name="bugbook-title" content="Too Late">"#
        let manifest = ArtifactManifest.parse(html)
        XCTAssertNotNil(manifest)
        XCTAssertNil(manifest?.title)

        let lateMarker = padding + #"<meta name="bugbook-artifact" content="1">"#
        XCTAssertNil(ArtifactManifest.parse(lateMarker))
    }

    func testMultiByteCharacterAtBoundaryDoesNotCrash() {
        let pad = String(repeating: "a", count: 4093)
        let html = "<!-- " + pad + "🚀 -->"  // emoji straddles byte 4096
        XCTAssertNil(ArtifactManifest.parse(html))
    }

    func testParsesCapabilityManifest() {
        let html = happyPath + """
        <script type="application/bugbook-manifest">
        { "manifestVersion": 1,
          "capabilities": { "query": ["Garmin Sleep", "Weekly Reviews"], "mutate": [] } }
        </script>
        """
        let manifest = ArtifactManifest.parse(html)
        XCTAssertEqual(manifest?.hasCapabilityBlock, true)
        XCTAssertEqual(manifest?.capabilities?.query, ["Garmin Sleep", "Weekly Reviews"])
        XCTAssertEqual(manifest?.capabilities?.mutate, [])
        XCTAssertEqual(manifest?.capabilities?.manifestVersion, 1)
    }

    func testMalformedManifestJSONIsInert() {
        let html = happyPath + #"<script type="application/bugbook-manifest">{ not json</script>"#
        let manifest = ArtifactManifest.parse(html)
        XCTAssertEqual(manifest?.hasCapabilityBlock, true)
        XCTAssertNil(manifest?.capabilities)
    }

    func testLoadReadsBoundedBytesFromDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtifactManifestTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("big.html")
        try (happyPath + String(repeating: "x", count: 1_000_000))
            .write(to: url, atomically: true, encoding: .utf8)

        XCTAssertEqual(ArtifactManifest.load(contentsOf: url)?.title, "Sleep Trends — 2026-W23")
        XCTAssertNil(ArtifactManifest.load(contentsOf: dir.appendingPathComponent("missing.html")))
    }
}
