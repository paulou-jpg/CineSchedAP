// Formatting.swift
// Shared formatting helpers used across views and PDF export

import Foundation

/// Returns a short date string, e.g. "Mon Jun 2"
func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "E MMM d"
    return formatter.string(from: date)
}

/// Returns a full date string, e.g. "Tuesday, October 6, 2026" — used by the
/// stripboard's "END OF DAY" marker, where the calendar's abbreviated
/// formattedDate would read too clipped for a full-width banner line.
func formattedFullDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEE, MMMM d, yyyy"
    return formatter.string(from: date)
}

/// Returns a minute count as "H:MM", e.g. 510 -> "8:30" — used by the
/// stripboard's "END OF DAY" marker; distinct from formattedTime's word-based
/// "8 hr 30 min" style used elsewhere.
func formattedTimeHM(_ minutes: Int) -> String {
    let hours = minutes / 60
    let mins  = minutes % 60
    return "\(hours):\(String(format: "%02d", mins))"
}

/// Returns an eighths-of-a-page count as a readable fraction string.
func formattedEighths(_ totalEighths: Int) -> String {
    FractionParser.formatEighths(totalEighths)
}

/// Returns a minute count as a readable time string.
func formattedTime(_ minutes: Int) -> String {
    TimeParser.formatMinutes(minutes)
}

/// Weekday component is 1-7 with 1 = Sunday, 7 = Saturday in the Gregorian
/// calendar, regardless of locale — independent of any calendar grid's own
/// first-day-of-week display setting.
func isWeekend(_ date: Date) -> Bool {
    let weekday = Calendar.current.component(.weekday, from: date)
    return weekday == 1 || weekday == 7
}

/// Maps each ShootDay's id to its "Day N" production-day number — the Nth
/// day, in date order, that has at least one real scene (a scene with a
/// scene number). Days with no scenes, or only notice/banner scenes (blank
/// scene number, e.g. "DOWN FOR THANKSGIVING"), don't count and don't break
/// the sequence — they're just skipped, not renumbered around.
func productionDayNumbers(for shootDays: [ShootDay]) -> [UUID: Int] {
    var result: [UUID: Int] = [:]
    var counter = 0
    for day in shootDays {
        let hasRealScene = day.scenes.contains { !$0.sceneNumber.trimmingCharacters(in: .whitespaces).isEmpty }
        if hasRealScene {
            counter += 1
            result[day.id] = counter
        }
    }
    return result
}

/// Generates an array of ShootDays between two dates (inclusive).
func generateDays(from startDate: Date, to endDate: Date) -> [ShootDay] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 1 // Sunday

    var days: [ShootDay] = []
    var current = calendar.startOfDay(for: startDate)
    let end     = calendar.startOfDay(for: endDate)

    while current <= end {
        days.append(ShootDay(date: current))
        current = calendar.date(byAdding: .day, value: 1, to: current)!
    }
    return days
}
