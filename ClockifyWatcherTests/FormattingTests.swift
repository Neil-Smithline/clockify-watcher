import XCTest
import AppKit
@testable import ClockifyWatcher

final class FormattingTests: XCTestCase {

    // MARK: - Elapsed time

    func testElapsedZeroMinutes() {
        let start = Date(timeIntervalSinceNow: -45)  // 45 seconds ago
        XCTAssertEqual(formatElapsed(from: start), "0:00")
    }

    func testElapsedMinutesPaddedToTwoDigits() {
        let start = Date(timeIntervalSinceNow: -(3 * 60))
        XCTAssertEqual(formatElapsed(from: start), "0:03")
    }

    func testElapsed23Minutes() {
        let start = Date(timeIntervalSinceNow: -((23 * 60) + 45))
        XCTAssertEqual(formatElapsed(from: start), "0:23")
    }

    func testElapsedExactlyOneHour() {
        let start = Date(timeIntervalSinceNow: -3600)
        XCTAssertEqual(formatElapsed(from: start), "1:00")
    }

    func testElapsedMultipleHoursAndMinutes() {
        let start = Date(timeIntervalSinceNow: -((2 * 3600) + (5 * 60)))
        XCTAssertEqual(formatElapsed(from: start), "2:05")
    }

    func testElapsedFutureStartClampsToZero() {
        let start = Date(timeIntervalSinceNow: 60)  // 1 minute in the future
        XCTAssertEqual(formatElapsed(from: start), "0:00")
    }

    // MARK: - Hex color

    func testHexColorWithHash() {
        XCTAssertNotNil(NSColor(hex: "#FF5722"))
    }

    func testHexColorWithoutHash() {
        XCTAssertNotNil(NSColor(hex: "FF5722"))
    }

    func testHexColorComponents() {
        let color = NSColor(hex: "#FF0000")!.usingColorSpace(.sRGB)!
        XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.01)
    }

    func testHexColorInvalidReturnsNil() {
        XCTAssertNil(NSColor(hex: "ZZZZZZ"))
        XCTAssertNil(NSColor(hex: "short"))
        XCTAssertNil(NSColor(hex: ""))
    }
}
