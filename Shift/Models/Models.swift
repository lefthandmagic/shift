import Foundation

enum ShiftKind: String, Codable, Equatable {
    case delay
    case advance
    case hold
    case flight
}

enum ActionKind: String, Codable, Equatable {
    case seekLight
    case avoidLight
    case sleep
    case wake
    case caffeineCutoff
    case move
    case hydrate
    case note
}

struct ActionItem: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let kind: ActionKind
    let title: String
    let detail: String

    init(id: UUID = UUID(), date: Date, kind: ActionKind, title: String, detail: String) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

struct DayPlan: Identifiable, Equatable {
    var id: Date { dayStart }
    let dayStart: Date
    let timeZone: TimeZone
    let locationName: String
    let bodyMinusLocalHours: Double
    let targetSleep: Date
    let targetWake: Date
    let caffeineCutoff: Date
    let lightSeek: DateInterval?
    let lightAvoid: DateInterval?
    let kind: ShiftKind
    let headline: String
    let summary: String
    let actions: [ActionItem]

    var hoursOff: Double { abs(bodyMinusLocalHours) }

    func bodyClockTime(at date: Date) -> Date {
        date.addingTimeInterval(bodyMinusLocalHours * 3600)
    }
}

struct SleepSchedule: Equatable {
    var bedHour: Int = 23
    var bedMinute: Int = 0
    var wakeHour: Int = 7
    var wakeMinute: Int = 0
    /// Hours of circadian delay (westbound) applied per day.
    var delayRateHours: Double = 1.5
    /// Hours of circadian advance (eastbound) applied per day.
    var advanceRateHours: Double = 1.0
    var preShiftDays: Int = 3

    var sleepLengthHours: Double {
        let bed = Double(bedHour) + Double(bedMinute) / 60
        var wake = Double(wakeHour) + Double(wakeMinute) / 60
        if wake <= bed { wake += 24 }
        return wake - bed
    }
}

struct TripSegment: Equatable {
    let name: String
    let timeZone: TimeZone
    let start: Date
    let end: Date
    let isFlight: Bool
}

struct TripEvent: Equatable {
    let name: String
    let start: Date
    let end: Date
}

struct Trip: Equatable {
    let name: String
    let homeTimeZone: TimeZone
    let segments: [TripSegment]
    let events: [TripEvent]

    func segment(at date: Date) -> TripSegment? {
        segments.first { date >= $0.start && date < $0.end }
            ?? segments.last(where: { date >= $0.start })
            ?? segments.first
    }
}

enum ClockMath {
    static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, timeZone: TimeZone) -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = timeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return comps.date!
    }

    static func startOfDay(_ date: Date, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.startOfDay(for: date)
    }

    static func at(hour: Int, minute: Int, on day: Date, timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        comps.timeZone = timeZone
        return cal.date(from: comps)!
    }

    static func gmtOffsetHours(_ timeZone: TimeZone, at date: Date) -> Double {
        Double(timeZone.secondsFromGMT(for: date)) / 3600.0
    }

    static func format(_ date: Date, timeZone: TimeZone, template: String = "HH:mm") -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    static func formatDay(_ date: Date, timeZone: TimeZone) -> String {
        format(date, timeZone: timeZone, template: "EEE d MMM")
    }
}
