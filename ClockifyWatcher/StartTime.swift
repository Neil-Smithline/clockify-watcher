import Foundation

enum StartTimeError: Error, Equatable {
    /// The chosen time is later than the entry's current start.
    case notEarlier
}

/// Resolves a picked clock time into an absolute start date for the running entry.
///
/// Only the hour and minute of `picked` are used; they are combined with the calendar
/// day of `now` and seconds are zeroed, matching `formatElapsed`'s minute granularity.
///
/// The result must be no later than `currentStart` — the editor can only move a start
/// earlier. Since `currentStart` is always at or before `now`, this also rules out
/// future start times, and it rejects every edit to an entry that began on an earlier
/// day.
///
/// Because seconds are zeroed, picking the minute the picker currently displays for
/// `currentStart` still succeeds and moves the start earlier by `currentStart`'s seconds.
func resolveStartTime(picked: Date,
                      currentStart: Date,
                      now: Date,
                      calendar: Calendar = .current) -> Result<Date, StartTimeError> {
    let time = calendar.dateComponents([.hour, .minute], from: picked)
    guard let resolved = calendar.date(bySettingHour: time.hour ?? 0,
                                       minute: time.minute ?? 0,
                                       second: 0,
                                       of: now),
          resolved <= currentStart else {
        return .failure(.notEarlier)
    }
    return .success(resolved)
}
