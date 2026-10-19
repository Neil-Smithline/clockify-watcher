import Foundation
import os

/// Unified-system-log channels for the app.
///
/// The app has no visible error reporting beyond the menubar, so every API
/// failure is recorded here. To read it:
///
///     log stream --predicate 'subsystem == "com.clockify.ClockifyWatcher"'
///     log show --last 1h --predicate 'subsystem == "com.clockify.ClockifyWatcher"' --style compact
///
/// Interpolated values are marked `.public` deliberately: status codes, URL
/// paths, and intervals are diagnostics, not secrets. The API key is never
/// logged.
enum Log {
    private static let subsystem = "com.clockify.ClockifyWatcher"

    /// HTTP requests and their failures.
    static let api = Logger(subsystem: subsystem, category: "api")
    /// Poll scheduling, backoff, and rate-limit state.
    static let poll = Logger(subsystem: subsystem, category: "poll")
}
