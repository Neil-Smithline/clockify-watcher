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

    // MARK: - Networking

    func testFetchUserSuccess() async throws {
        let json = #"{"id":"user123","activeWorkspace":"ws456","email":"a@b.com","name":"Alice"}"#
            .data(using: .utf8)!
        let client = ClockifyClient(apiKey: "test-key", session: MockURLSession(data: json, statusCode: 200))
        let user = try await client.fetchUser()
        XCTAssertEqual(user.id, "user123")
    }

    func testFetchUserThrowsOn401() async {
        let client = ClockifyClient(apiKey: "bad-key", session: MockURLSession(data: Data(), statusCode: 401))
        do {
            _ = try await client.fetchUser()
            XCTFail("Expected ClockifyError.unauthorized")
        } catch ClockifyError.unauthorized {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testFetchProjectsReturnsSortedByName() async throws {
        let json = """
        [
          {"id":"p1","name":"Zebra","color":"#FF0000","archived":false},
          {"id":"p2","name":"Alpha","color":"#00FF00","archived":false}
        ]
        """.data(using: .utf8)!
        let client = ClockifyClient(apiKey: "key", session: MockURLSession(data: json, statusCode: 200))
        let projects = try await client.fetchProjects(workspaceId: "ws1")
        XCTAssertEqual(projects.count, 2)
        XCTAssertEqual(projects[0].name, "Zebra")  // API order preserved; sorting is AppDelegate's job
    }

    func testFetchRunningEntryNilWhenNoTimer() async throws {
        let client = ClockifyClient(apiKey: "key", session: MockURLSession(data: "[]".data(using: .utf8)!, statusCode: 200))
        let entry = try await client.fetchRunningEntry(workspaceId: "ws1", userId: "u1")
        XCTAssertNil(entry)
    }

    func testFetchRunningEntryReturnsFirst() async throws {
        let json = """
        [{"id":"e1","projectId":"p1","timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}}]
        """.data(using: .utf8)!
        let client = ClockifyClient(apiKey: "key", session: MockURLSession(data: json, statusCode: 200))
        let entry = try await client.fetchRunningEntry(workspaceId: "ws1", userId: "u1")
        XCTAssertEqual(entry?.id, "e1")
        XCTAssertEqual(entry?.projectId, "p1")
    }
}

// MARK: - Test helpers

struct MockURLSession: URLSessionProtocol {
    let data: Data
    let statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
