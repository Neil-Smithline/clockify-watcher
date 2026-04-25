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
}

struct UpdateEntryBody: Encodable {
    let start: Date
    let projectId: String
}

// MARK: - Errors

enum ClockifyError: Error {
    case unauthorized
    case httpError(Int)
}

// MARK: - URLSession abstraction

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

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

    func updateEntryProject(workspaceId: String, entryId: String, start: Date, projectId: String) async throws {
        let url = baseURL.appendingPathComponent("workspaces/\(workspaceId)/time-entries/\(entryId)")
        try await put(url: url, body: UpdateEntryBody(start: start, projectId: projectId))
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
        switch http.statusCode {
        case 200...299: break
        case 401: throw ClockifyError.unauthorized
        default: throw ClockifyError.httpError(http.statusCode)
        }
    }
}
