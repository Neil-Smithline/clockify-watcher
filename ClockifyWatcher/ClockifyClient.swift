import Foundation

// MARK: - Response models

struct ClockifyUser: Decodable {
    let id: String
    let activeWorkspace: String
}

struct ClockifyProject: Decodable {
    let id: String
    let name: String
    let color: String
    let archived: Bool
}

struct ClockifyTimeEntry: Decodable {
    let id: String
    let projectId: String?
    let description: String?
    let taskId: String?
    let tagIds: [String]?
    let timeInterval: ClockifyTimeInterval
}

struct ClockifyTimeInterval: Decodable {
    let start: Date
    let end: Date?
}

// MARK: - Request bodies

struct StopTimerBody: Encodable {
    let end: Date
}

struct StartTimerBody: Encodable {
    let start: Date
    let projectId: String
    let billable: Bool = true
}

struct UpdateEntryBody: Encodable {
    let start: Date
    let projectId: String
    let description: String?
    let taskId: String?
    let tagIds: [String]?
    let billable: Bool = true
}

// MARK: - Errors

enum ClockifyError: Error, Equatable {
    case unauthorized
    /// HTTP 429. Clockify's Free plan allows 30 requests/hour per workspace; once
    /// that is spent every data endpoint returns this until the window rolls over.
    /// `retryAfter` carries the `Retry-After` header when the server sends one —
    /// Clockify currently does not.
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(Int)
}

// MARK: - URLSession abstraction

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// RFC 7231 IMF-fixdate, the format `Retry-After` uses when it carries a date.
private let httpDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "GMT")
    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return f
}()

// MARK: - Client

final class ClockifyClient {
    private let apiKey: String
    private let session: URLSessionProtocol
    private let baseURL = URL(string: "https://api.clockify.me/api/v1")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    init(apiKey: String, session: URLSessionProtocol = URLSession.shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchUser() async throws -> ClockifyUser {
        try await get(url: baseURL.appendingPathComponent("user"))
    }

    func fetchProjects(workspaceId: String) async throws -> [ClockifyProject] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("workspaces/\(workspaceId)/projects"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "archived", value: "false")]
        return try await get(url: comps.url!)
    }

    func fetchRunningEntry(workspaceId: String, userId: String) async throws -> ClockifyTimeEntry? {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("workspaces/\(workspaceId)/user/\(userId)/time-entries"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "in-progress", value: "true"),
            URLQueryItem(name: "page-size", value: "1")
        ]
        let entries: [ClockifyTimeEntry] = try await get(url: comps.url!)
        return entries.first
    }

    func stopCurrentTimer(workspaceId: String, userId: String) async throws {
        let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/user/\(userId)/time-entries")
        try await patch(url: url, body: StopTimerBody(end: Date()))
    }

    func startTimer(workspaceId: String, projectId: String) async throws {
        let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/time-entries")
        try await post(url: url, body: StartTimerBody(start: Date(), projectId: projectId))
    }

    func updateEntry(workspaceId: String, entryId: String, start: Date, projectId: String,
                     description: String?, taskId: String?, tagIds: [String]?) async throws {
        let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/time-entries/\(entryId)")
        try await put(url: url, body: UpdateEntryBody(start: start, projectId: projectId,
                                                      description: description,
                                                      taskId: taskId, tagIds: tagIds))
    }

    func deleteEntry(workspaceId: String, entryId: String) async throws {
        let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/time-entries/\(entryId)")
        try await delete(url: url)
    }

    // MARK: - Helpers

    private func get<T: Decodable>(url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await session.data(for: req)
        try checkResponse(response)
        return try decoder.decode(T.self, from: data)
    }

    private func patch<B: Encodable>(url: URL, body: B) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try checkResponse(response)
    }

    private func post<B: Encodable>(url: URL, body: B) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try checkResponse(response)
    }

    private func put<B: Encodable>(url: URL, body: B) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(body)
        let (_, response) = try await session.data(for: req)
        try checkResponse(response)
    }

    private func delete(url: URL) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        let (_, response) = try await session.data(for: req)
        try checkResponse(response)
    }

    private func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        let path = http.url?.path ?? "?"
        switch http.statusCode {
        case 200...299:
            break
        case 401:
            Log.api.error("401 unauthorized on \(path, privacy: .public)")
            throw ClockifyError.unauthorized
        case 429:
            let retryAfter = Self.retryAfterSeconds(from: http)
            Log.api.error("""
                429 rate limited on \(path, privacy: .public) \
                (Retry-After: \(retryAfter.map { String($0) } ?? "absent", privacy: .public))
                """)
            throw ClockifyError.rateLimited(retryAfter: retryAfter)
        default:
            Log.api.error("HTTP \(http.statusCode, privacy: .public) on \(path, privacy: .public)")
            throw ClockifyError.httpError(http.statusCode)
        }
    }

    /// `Retry-After` as seconds. Handles both the delta-seconds and HTTP-date
    /// forms; returns nil when the header is absent or unparseable.
    private static func retryAfterSeconds(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) { return seconds }
        guard let date = httpDateFormatter.date(from: raw) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}
