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

struct TimeZoneOption: Identifiable, Hashable {
    var id: String { identifier }
    let name: String
    let identifier: String
}

enum TimeZoneCatalog {
    static let common: [TimeZoneOption] = [
        TimeZoneOption(name: "Amsterdam", identifier: "Europe/Amsterdam"),
        TimeZoneOption(name: "London", identifier: "Europe/London"),
        TimeZoneOption(name: "Miami / Atlanta / New York", identifier: "America/New_York"),
        TimeZoneOption(name: "Chicago", identifier: "America/Chicago"),
        TimeZoneOption(name: "Denver", identifier: "America/Denver"),
        TimeZoneOption(name: "Los Angeles / San Francisco", identifier: "America/Los_Angeles"),
        TimeZoneOption(name: "India", identifier: "Asia/Kolkata"),
        TimeZoneOption(name: "UTC", identifier: "UTC"),
    ]

    static func options(including identifier: String) -> [TimeZoneOption] {
        if common.contains(where: { $0.identifier == identifier }) {
            return common
        }
        let extra = TimeZoneOption(
            name: identifier.replacingOccurrences(of: "_", with: " "),
            identifier: identifier
        )
        return [extra] + common
    }
}

struct TripSegment: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var timeZoneIdentifier: String
    var start: Date
    var end: Date
    var isFlight: Bool

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "UTC")!
    }

    init(
        id: UUID = UUID(),
        name: String,
        timeZone: TimeZone,
        start: Date,
        end: Date,
        isFlight: Bool
    ) {
        self.id = id
        self.name = name
        self.timeZoneIdentifier = timeZone.identifier
        self.start = start
        self.end = end
        self.isFlight = isFlight
    }
}

struct TripEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var start: Date
    var end: Date

    init(id: UUID = UUID(), name: String, start: Date, end: Date) {
        self.id = id
        self.name = name
        self.start = start
        self.end = end
    }
}

struct Trip: Codable, Equatable {
    var name: String
    var homeTimeZoneIdentifier: String
    var segments: [TripSegment]
    var events: [TripEvent]

    var homeTimeZone: TimeZone {
        TimeZone(identifier: homeTimeZoneIdentifier) ?? TimeZone(identifier: "Europe/Amsterdam")!
    }

    var routeSummary: String {
        segments.map(\.name).joined(separator: " → ")
    }

    init(
        name: String,
        homeTimeZone: TimeZone,
        segments: [TripSegment],
        events: [TripEvent]
    ) {
        self.name = name
        self.homeTimeZoneIdentifier = homeTimeZone.identifier
        self.segments = segments
        self.events = events
    }

    func segment(at date: Date) -> TripSegment? {
        segments.first { date >= $0.start && date < $0.end }
            ?? segments.last(where: { date >= $0.start })
            ?? segments.first
    }

    mutating func replaceSegment(_ updated: TripSegment) {
        guard let i = segments.firstIndex(where: { $0.id == updated.id }) else { return }
        var next = updated
        if next.end <= next.start {
            next.end = next.start.addingTimeInterval(3600)
        }
        segments[i] = next
        if i + 1 < segments.count {
            segments[i + 1].start = next.end
            if segments[i + 1].end <= segments[i + 1].start {
                segments[i + 1].end = segments[i + 1].start.addingTimeInterval(3600)
            }
        }
        if i > 0 {
            segments[i - 1].end = next.start
        }
    }

    mutating func addSegment() {
        let last = segments.last
        let tz = last?.timeZone ?? homeTimeZone
        let start = last?.end ?? Date()
        let end = start.addingTimeInterval(4 * 3600)
        segments.append(
            TripSegment(name: "New stop", timeZone: tz, start: start, end: end, isFlight: false)
        )
    }

    mutating func deleteSegment(id: UUID) {
        guard segments.count > 1, let i = segments.firstIndex(where: { $0.id == id }) else { return }
        segments.remove(at: i)
        if i > 0 && i < segments.count {
            segments[i].start = segments[i - 1].end
        }
    }

    mutating func replaceEvent(_ updated: TripEvent) {
        guard let i = events.firstIndex(where: { $0.id == updated.id }) else { return }
        var next = updated
        if next.end <= next.start {
            next.end = next.start.addingTimeInterval(3600)
        }
        events[i] = next
    }

    mutating func addEvent() {
        let start = events.last?.end
            ?? segments.last(where: { !$0.isFlight })?.start
            ?? Date()
        events.append(
            TripEvent(name: "Event", start: start, end: start.addingTimeInterval(3 * 3600))
        )
    }

    mutating func deleteEvent(id: UUID) {
        events.removeAll { $0.id == id }
    }
}

enum TripStore {
    static let key = "tripJSON"

    static func load(from defaults: UserDefaults) -> Trip? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Trip.self, from: data)
    }

    static func save(_ trip: Trip, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(trip) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
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

    /// Keep the displayed wall-clock time when switching a segment's timezone.
    static func keepingWallClock(_ date: Date, from: TimeZone, to: TimeZone) -> Date {
        var source = Calendar(identifier: .gregorian)
        source.timeZone = from
        var comps = source.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        comps.timeZone = to
        var dest = Calendar(identifier: .gregorian)
        dest.timeZone = to
        return dest.date(from: comps) ?? date
    }
}
