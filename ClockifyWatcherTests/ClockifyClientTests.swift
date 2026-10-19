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

    func testDecodeTimeEntryPreservesDescriptionTaskAndTags() throws {
        let json = """
        {
          "id":"entry3",
          "projectId":"proj1",
          "description":"writing docs",
          "taskId":"task1",
          "tagIds":["tag1","tag2"],
          "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
        XCTAssertEqual(entry.description, "writing docs")
        XCTAssertEqual(entry.taskId, "task1")
        XCTAssertEqual(entry.tagIds, ["tag1", "tag2"])
    }

    func testDecodeTimeEntryWithoutOptionalFields() throws {
        // The polling response may omit these keys entirely; decoding must still work.
        let json = """
        {
          "id":"entry4",
          "projectId":"proj1",
          "timeInterval":{"start":"2024-01-01T10:00:00Z","end":null,"duration":null}
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(ClockifyTimeEntry.self, from: json)
        XCTAssertNil(entry.description)
        XCTAssertNil(entry.taskId)
        XCTAssertNil(entry.tagIds)
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

    func testFetchProjectsPreservesAPIOrder() async throws {
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

    func testUpdateEntrySendsPreservedFieldsAndNoEnd() async throws {
        let session = RecordingURLSession()
        let client = ClockifyClient(apiKey: "key", session: session)

        try await client.updateEntry(workspaceId: "ws1", entryId: "e1",
                                     start: Date(timeIntervalSince1970: 1_700_000_000),
                                     projectId: "p1",
                                     description: "writing docs",
                                     taskId: "task1",
                                     tagIds: ["tag1", "tag2"])

        let request = try XCTUnwrap(session.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/workspaces/ws1/time-entries/e1")

        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["projectId"] as? String, "p1")
        XCTAssertEqual(body["description"] as? String, "writing docs")
        XCTAssertEqual(body["taskId"] as? String, "task1")
        XCTAssertEqual(body["tagIds"] as? [String], ["tag1", "tag2"])
        XCTAssertEqual(body["billable"] as? Bool, true)
        XCTAssertNotNil(body["start"])
        XCTAssertNil(body["end"], "A running entry must not be given an end time")
    }

    // MARK: - Rate limiting (Clockify Free plan: 30 requests/hour)

    /// The real body Clockify returns once the hourly budget is spent.
    private static let rateLimitBody = #"""
    {"message":"Too many requests!","code":429,"rateLimitCode":null,"customMessage":"You have reached the limit of 30 requests per hour allowed on a Free plan. To increase the rate limit please upgrade your workspace or wait for one hour."}
    """#.data(using: .utf8)!

    func testRateLimitIsItsOwnErrorAndNotAGenericHTTPError() async {
        let client = ClockifyClient(apiKey: "key",
                                    session: MockURLSession(data: Self.rateLimitBody, statusCode: 429))
        do {
            _ = try await client.fetchProjects(workspaceId: "ws1")
            XCTFail("Expected ClockifyError.rateLimited")
        } catch ClockifyError.rateLimited(let retryAfter) {
            XCTAssertNil(retryAfter, "Clockify sends no Retry-After on this response")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testRateLimitIsNotMistakenForAnExpiredKey() async {
        // A 429 must never reach the unauthorized path: that deletes the stored key.
        let client = ClockifyClient(apiKey: "key",
                                    session: MockURLSession(data: Self.rateLimitBody, statusCode: 429))
        do {
            _ = try await client.fetchRunningEntry(workspaceId: "ws1", userId: "u1")
            XCTFail("Expected ClockifyError.rateLimited")
        } catch ClockifyError.unauthorized {
            XCTFail("429 must not be reported as unauthorized")
        } catch ClockifyError.rateLimited {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testRetryAfterSecondsAreParsedWhenPresent() async {
        let client = ClockifyClient(apiKey: "key",
                                    session: MockURLSession(data: Data(), statusCode: 429,
                                                            headers: ["Retry-After": "120"]))
        do {
            _ = try await client.fetchProjects(workspaceId: "ws1")
            XCTFail("Expected ClockifyError.rateLimited")
        } catch ClockifyError.rateLimited(let retryAfter) {
            XCTAssertEqual(retryAfter, 120)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testUnparseableRetryAfterIsTreatedAsAbsent() async {
        let client = ClockifyClient(apiKey: "key",
                                    session: MockURLSession(data: Data(), statusCode: 429,
                                                            headers: ["Retry-After": "soon"]))
        do {
            _ = try await client.fetchProjects(workspaceId: "ws1")
            XCTFail("Expected ClockifyError.rateLimited")
        } catch ClockifyError.rateLimited(let retryAfter) {
            XCTAssertNil(retryAfter)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testWriteRequestsAlsoReportRateLimiting() async {
        // Stopping a timer on sleep or lock must surface a 429 rather than look like success.
        let client = ClockifyClient(apiKey: "key",
                                    session: MockURLSession(data: Data(), statusCode: 429))
        do {
            try await client.stopCurrentTimer(workspaceId: "ws1", userId: "u1")
            XCTFail("Expected ClockifyError.rateLimited")
        } catch ClockifyError.rateLimited {
            // expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func testOtherHTTPErrorsStillCarryTheirStatusCode() async {
        let client = ClockifyClient(apiKey: "key",
                                    session: MockURLSession(data: Data(), statusCode: 503))
        do {
            _ = try await client.fetchProjects(workspaceId: "ws1")
            XCTFail("Expected ClockifyError.httpError")
        } catch ClockifyError.httpError(let code) {
            XCTAssertEqual(code, 503)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}

// MARK: - Test helpers

struct MockURLSession: URLSessionProtocol {
    let data: Data
    let statusCode: Int
    let headers: [String: String]?

    init(data: Data, statusCode: Int, headers: [String: String]? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                       httpVersion: nil, headerFields: headers)!
        return (data, response)
    }
}

/// Captures the last request so tests can assert on method, URL, and body.
final class RecordingURLSession: URLSessionProtocol, @unchecked Sendable {
    private(set) var lastRequest: URLRequest?
    let data: Data
    let statusCode: Int

    init(data: Data = Data(), statusCode: Int = 200) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}
