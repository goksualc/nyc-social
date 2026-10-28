import Foundation

/// Human-readable dates: "Today · 5:00 PM", "Tomorrow · 1–5 PM", "Fri · 11 AM–3 PM".
enum ActivityTime {
    nonisolated(unsafe) static var calendar = Calendar.current

    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate(pattern)
        return f.string(from: date)
    }

    static func day(_ date: Date, now: Date = .now) -> String {
        let cal = calendar
        if cal.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if (2...6).contains(days) { return format(date, "EEE") }
        return format(date, "EEE MMM d")
    }

    /// "5:00 PM", or "1 PM" when `compact` and on the hour.
    static func time(_ date: Date, compact: Bool = false) -> String {
        let onHour = calendar.component(.minute, from: date) == 0
        return format(date, compact && onHour ? "j" : "jmm")
    }

    static func start(_ date: Date, now: Date = .now, separator: String = " · ") -> String {
        "\(day(date, now: now))\(separator)\(time(date))"
    }

    /// "1–5 PM" (shared meridiem) or "11 AM–3 PM".
    static func range(_ start: Date, _ end: Date) -> String {
        let s = time(start, compact: true), e = time(end, compact: true)
        let sParts = s.split { $0.isWhitespace }, eParts = e.split { $0.isWhitespace }
        if sParts.count == 2, eParts.count == 2, sParts[1] == eParts[1] {
            return "\(sParts[0])–\(e)"
        }
        return "\(s)–\(e)"
    }

    static func summary(_ activity: Activity, now: Date = .now, separator: String = " · ") -> String {
        switch activity.kind {
        case .walk: start(activity.startDate, now: now, separator: separator)
        case .cowork: "\(day(activity.startDate, now: now))\(separator)\(range(activity.startDate, activity.endDate))"
        }
    }

    /// Chat timestamps: "4:12 PM" today, otherwise "Tue".
    static func stamp(_ date: Date, now: Date = .now) -> String {
        calendar.isDate(date, inSameDayAs: now) ? time(date) : day(date, now: now)
    }

    // MARK: Filters

    static func isToday(_ date: Date, now: Date = .now) -> Bool { calendar.isDate(date, inSameDayAs: now) }
    static func isTomorrow(_ date: Date, now: Date = .now) -> Bool {
        guard let t = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: t)
    }
}
