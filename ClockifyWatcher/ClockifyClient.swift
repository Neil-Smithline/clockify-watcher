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
