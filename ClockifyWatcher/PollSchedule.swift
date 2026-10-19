import Foundation

/// How long to wait between polls, and how far to back off when Clockify
/// rate-limits us.
///
/// Clockify's Free plan allows **30 API requests per hour** per workspace.
/// Exceeding it earns a 429 on every data endpoint (`/user` keeps working) until
/// the hour's window rolls over, which looks exactly like the app losing API
/// access. The values here keep the steady-state poll well under that budget and
/// leave headroom for menu actions, each of which also costs a request.

/// 180 s → 20 requests/hour, leaving ~10/hour for start, stop, and project switches.
let basePollInterval: TimeInterval = 180

/// Backoff bounds used when a 429 arrives. The ceiling is one hour because
/// Clockify's budget is hourly — waiting longer than the window cannot help.
let minRateLimitBackoff: TimeInterval = 60
let maxRateLimitBackoff: TimeInterval = 3600

/// Wait after the first 429, doubled for each consecutive one.
let initialRateLimitBackoff: TimeInterval = 300

/// Opening the menu refreshes state only if the last poll is at least this old.
/// Menu opens are unbounded and each one used to cost two requests, which alone
/// could drain the hourly budget.
let menuPollStaleness: TimeInterval = 60

/// How long to wait before retrying a project fetch that failed. Without this
/// the retry fires on every poll, doubling our request rate precisely when we
/// are already over budget.
let projectsRetryCooldown: TimeInterval = 600

enum PollOutcome: Equatable {
    case success
    /// A 429. `retryAfter` is the server's `Retry-After`, when it sends one.
    case rateLimited(retryAfter: TimeInterval?)
    /// Network error, decode error, or a non-429 HTTP error.
    case failed
}

/// Seconds to wait before the next poll.
/// - Parameter consecutiveRateLimits: 429s in a row *including* this one, so the
///   first 429 passes 1. Ignored unless `outcome` is `.rateLimited`.
func nextPollDelay(after outcome: PollOutcome, consecutiveRateLimits: Int) -> TimeInterval {
    switch outcome {
    case .success:
        return basePollInterval

    case .failed:
        // A network blip or a 5xx costs nothing against the quota and usually
        // clears by itself, so keep the normal cadence rather than stalling.
        return basePollInterval

    case .rateLimited(let retryAfter):
        if let retryAfter {
            return min(max(retryAfter, minRateLimitBackoff), maxRateLimitBackoff)
        }
        // Exponential: 5, 10, 20, 40 min, then pinned at the hourly ceiling.
        // `min(step, 10)` only guards the exponent against absurd input.
        let step = min(max(0, consecutiveRateLimits - 1), 10)
        return min(initialRateLimitBackoff * pow(2, Double(step)), maxRateLimitBackoff)
    }
}
