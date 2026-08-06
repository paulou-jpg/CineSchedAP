// FountainPaginatorTests.swift
// Unit tests for the pagination engine. FountainParser/FountainPaginator have
// zero SwiftUI/AppKit dependencies, so these run as plain logic tests with no
// host application required.

import XCTest
@testable import CineSched

final class FountainPaginatorTests: XCTestCase {

    // MARK: - Helpers

    private func heading(_ text: String, line: Int) -> FountainElement {
        FountainElement(kind: .sceneHeading, text: text, lineIndex: line)
    }

    private func action(_ text: String, line: Int) -> FountainElement {
        FountainElement(kind: .action, text: text, lineIndex: line)
    }

    // MARK: - Single-line scene -> 1/8th

    func testSingleLineSceneIsOneEighth() {
        let elements = [
            heading("INT. KITCHEN - DAY", line: 0),
            action("She pours coffee.", line: 1),
        ]
        let result = FountainPaginator.paginate(elements)
        XCTAssertEqual(result.scenes.count, 1)
        XCTAssertEqual(result.scenes[0].rawLines, 3)   // heading(2) + 1 action line
        XCTAssertEqual(result.scenes[0].eighths, 1)
    }

    // MARK: - 7-line scene -> 1/8th

    func testSevenLineSceneIsOneEighth() {
        var elements = [heading("INT. OFFICE - DAY", line: 0)]
        for i in 0..<5 {
            elements.append(action("A short beat.", line: i + 1))
        }
        // heading(2) + 5 action lines(5) = 7 raw lines
        let result = FountainPaginator.paginate(elements)
        XCTAssertEqual(result.scenes[0].rawLines, 7)
        XCTAssertEqual(result.scenes[0].eighths, 1)
    }

    // MARK: - 8-line scene -> 2/8ths

    func testEightLineSceneIsTwoEighths() {
        var elements = [heading("INT. OFFICE - DAY", line: 0)]
        for i in 0..<6 {
            elements.append(action("A short beat.", line: i + 1))
        }
        // heading(2) + 6 action lines(6) = 8 raw lines
        let result = FountainPaginator.paginate(elements)
        XCTAssertEqual(result.scenes[0].rawLines, 8)
        XCTAssertEqual(result.scenes[0].eighths, 2)
    }

    // MARK: - Scene straddling a page boundary -> correct combined count

    func testSceneStraddlingPageBoundaryCountsAllLines() {
        var elements: [FountainElement] = []
        var line = 0

        // Filler scene: push the running page counter close to the 56-line boundary.
        elements.append(heading("INT. FILLER - DAY", line: line)); line += 1
        for _ in 0..<50 {
            elements.append(action("Filler.", line: line)); line += 1
        }
        // Filler scene: 2 (heading) + 50 = 52 raw lines -> page counter sits at 52.

        // This scene's 12 raw lines (heading + 10 action) will cross line 56.
        elements.append(heading("INT. STRADDLE - DAY", line: line)); line += 1
        for _ in 0..<10 {
            elements.append(action("More content.", line: line)); line += 1
        }

        let result = FountainPaginator.paginate(elements)
        XCTAssertEqual(result.scenes.count, 2)
        let straddling = result.scenes[1]
        XCTAssertEqual(straddling.rawLines, 12)
        XCTAssertEqual(straddling.eighths, 2)   // ceil(12/7)
        XCTAssertGreaterThan(straddling.endPage, straddling.startPage, "scene should straddle two pages")
    }

    // MARK: - Hard page break resets the counter

    func testHardPageBreakResetsCounter() {
        let elements: [FountainElement] = [
            heading("INT. ROOM - DAY", line: 0),
            action("A short line.", line: 1),                                  // sceneRawLines = 3, page counter = 3
            FountainElement(kind: .pageBreak, text: "", lineIndex: 2),
            action("After the break.", line: 3),
        ]

        let result = FountainPaginator.paginate(elements)
        // The break pads the remainder of page 1 (56 - 3 = 53 lines) into the
        // scene's own raw-line count, then the next line starts at the top of page 2.
        XCTAssertEqual(result.scenes[0].rawLines, 3 + 53 + 1)
        XCTAssertEqual(result.scenes[0].endPage, 2)
    }

    // MARK: - Full script with a known page count

    /// Self-authored fixture (no third-party screenplay text) with a
    /// deterministic structure: 20 scenes, each a heading (2 lines) plus 5
    /// short action lines (5 lines) = 7 raw lines/scene, 140 lines total ->
    /// ceil(140/56) = 3 expected pages.
    func testFullSyntheticScriptTotalPagesWithinTolerance() {
        var script = ""
        for n in 1...20 {
            script += "INT. LOCATION \(n) - DAY\n"
            for beat in 1...5 {
                script += "Beat \(beat) of scene \(n) happens right here in the room.\n"
            }
        }

        let parsed = FountainParser.parse(script)
        let result = FountainPaginator.paginate(parsed.elements)

        XCTAssertEqual(result.scenes.count, 20)
        let expectedPages = 3
        XCTAssertLessThanOrEqual(abs(result.totalPages - expectedPages), 2)
    }
}
