import XCTest
@testable import ClockifyWatcher

final class ClockifyClientTests: XCTestCase {

    // MARK: - Model decoding

    func testDecodeUser() throws {
        let json = #"{"id":"user123","activeWorkspace":"ws456","email":"a@b.com","name":"Alice"}"#
            .data(using: .utf8)!
        let user = try JSONDecoder().decode(ClockifyUser.self, from: json)
        XCTAssertEqual(user.id, "user123")
        XCTAssertEqual(user.activeWorkspace, "ws456")
    }

    func testDecodeProject() throws {
        let json = ##"{"id":"proj1","name":"My Project","color":"#FF5722","archived":false}"##
            .data(using: .utf8)!
        let project = try JSONDecoder().decode(ClockifyProject.self, from: json)
        XCTAssertEqual(project.id, "proj1")
        XCTAssertEqual(project.name, "My Project")
        XCTAssertEqual(project.color, "#FF5722")
        XCTAssertFalse(project.archived)
    }

    func testDecodeRunningTimeEntry() throws {
        let json = """
        {
          "id":"entry1",
          "projectId":"proj1",
          "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
        XCTAssertEqual(entry.id, "entry1")
        XCTAssertEqual(entry.projectId, "proj1")
        XCTAssertNil(entry.timeInterval.end)
    }

    func testDecodeTimeEntryWithNullProjectId() throws {
        let json = """
        {
          "id":"entry2",
          "projectId":null,
          "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
        XCTAssertNil(entry.projectId)
    }
}
