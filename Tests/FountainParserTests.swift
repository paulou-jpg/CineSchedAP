// FountainParserTests.swift
// Unit tests for scene-number extraction: the standard trailing "#...#"
// convention, and the leading "#...#" form some tools (Highland) use instead —
// including disambiguating it from Fountain's leading-"#" section heading syntax.

import XCTest
@testable import CineSched

final class FountainParserTests: XCTestCase {

    private func sceneHeadings(in text: String) -> [FountainElement] {
        FountainParser.parse(text).elements.filter { $0.kind == .sceneHeading }
    }

    // MARK: - Trailing "#...#" (standard Fountain/Final Draft convention)

    func testTrailingSceneNumber() {
        let headings = sceneHeadings(in: "INT. HOUSE - DAY #3A#\nShe walks in.\n")
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings[0].text, "INT. HOUSE - DAY")
        XCTAssertEqual(headings[0].sceneNumber, "3A")
    }

    func testNoSceneNumberWhenAbsent() {
        let headings = sceneHeadings(in: "INT. HOUSE - DAY\nShe walks in.\n")
        XCTAssertEqual(headings.count, 1)
        XCTAssertNil(headings[0].sceneNumber)
    }

    // MARK: - Leading "#...#" (Highland-style)

    func testLeadingSceneNumber() {
        let headings = sceneHeadings(in: "#3A# INT. HOUSE - DAY\nShe walks in.\n")
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings[0].text, "INT. HOUSE - DAY")
        XCTAssertEqual(headings[0].sceneNumber, "3A")
    }

    func testLeadingSceneNumberOnForcedHeading() {
        let headings = sceneHeadings(in: ".#12# SPACESHIP BRIDGE\nAlarms blare.\n")
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings[0].text, "SPACESHIP BRIDGE")
        XCTAssertEqual(headings[0].sceneNumber, "12")
    }

    // MARK: - Disambiguation from section headings

    /// A real Fountain section heading ("# Act One") has no closing "#" right
    /// after a number, so it must still be discarded as outline-only rather
    /// than misread as a scene number.
    func testSectionHeadingIsNotMistakenForLeadingSceneNumber() {
        let parsed = FountainParser.parse("# Act One\n\nINT. HOUSE - DAY\nShe walks in.\n")
        XCTAssertTrue(parsed.elements.allSatisfy { $0.text != "Act One" })
        let headings = parsed.elements.filter { $0.kind == .sceneHeading }
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings[0].text, "INT. HOUSE - DAY")
        XCTAssertNil(headings[0].sceneNumber)
    }

    /// "#20#" followed by something that isn't a recognized scene heading is
    /// not a Highland-style number either — falls through to the ordinary
    /// section-heading discard rule.
    func testLeadingHashNumberNotFollowedByHeadingIsDiscarded() {
        let parsed = FountainParser.parse("#20# Just a note, not a heading\n\nINT. HOUSE - DAY\n")
        let headings = parsed.elements.filter { $0.kind == .sceneHeading }
        XCTAssertEqual(headings.count, 1)
        XCTAssertEqual(headings[0].text, "INT. HOUSE - DAY")
    }
}
