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
    let constraintNote: String?

    var hoursOff: Double { abs(bodyMinusLocalHours) }

    /// City name used on clocks — destination side of a "AMS → Miami" flight.
    var clockCity: String { Self.clockCity(from: locationName) }

    static func clockCity(from locationName: String) -> String {
        if let arrow = locationName.range(of: "→") {
            return locationName[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return locationName
    }

    func bodyClockTime(at date: Date) -> Date {
        date.addingTimeInterval(bodyMinusLocalHours * 3600)
    }
}

struct SleepSchedule: Equatable {
    var bedHour: Int = 23
    var bedMinute: Int = 0
    var wakeHour: Int = 7
    var wakeMinute: Int = 0
    var delayRateHours: Double = 1.5
    var advanceRateHours: Double = 1.0
    var preShiftDays: Int = 3
    /// Hours before departure to be awake and at the airport.
    var airportLeadHours: Double = 3.0

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

    var durationHours: Double {
        max(0, end.timeIntervalSince(start) / 3600)
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

struct Trip: Codable, Equatable, Identifiable {
    var id: UUID
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

    var dateSpanLabel: String {
        guard let first = segments.first, let last = segments.last else { return name }
        let a = ClockMath.formatDay(first.start, timeZone: first.timeZone)
        let b = ClockMath.formatDay(last.end, timeZone: last.timeZone)
        return a == b ? a : "\(a) – \(b)"
    }

    init(
        id: UUID = UUID(),
        name: String,
        homeTimeZone: TimeZone,
        segments: [TripSegment],
        events: [TripEvent]
    ) {
        self.id = id
        self.name = name
        self.homeTimeZoneIdentifier = homeTimeZone.identifier
        self.segments = segments
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case id, name, homeTimeZoneIdentifier, segments, events
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        homeTimeZoneIdentifier = try c.decode(String.self, forKey: .homeTimeZoneIdentifier)
        segments = try c.decode([TripSegment].self, forKey: .segments)
        events = try c.decode([TripEvent].self, forKey: .events)
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

    func duplicated(name: String? = nil) -> Trip {
        var copy = self
        copy.id = UUID()
        copy.name = name ?? "\(self.name) copy"
        copy.segments = segments.map {
            TripSegment(id: UUID(), name: $0.name, timeZone: $0.timeZone, start: $0.start, end: $0.end, isFlight: $0.isFlight)
        }
        copy.events = events.map {
            TripEvent(id: UUID(), name: $0.name, start: $0.start, end: $0.end)
        }
        return copy
    }
}

struct TripLibrary: Codable, Equatable {
    var trips: [Trip]
    var activeTripID: UUID

    var active: Trip {
        trips.first { $0.id == activeTripID } ?? trips[0]
    }
}

enum TripStore {
    static let key = "tripJSON"
    static let libraryKey = "tripLibraryJSON"

    static func loadLibrary(from defaults: UserDefaults) -> TripLibrary {
        if let data = defaults.data(forKey: libraryKey),
           let lib = try? JSONDecoder().decode(TripLibrary.self, from: data),
           !lib.trips.isEmpty {
            return lib
        }
        if let data = defaults.data(forKey: key),
           let trip = try? JSONDecoder().decode(Trip.self, from: data) {
            return TripLibrary(trips: [trip], activeTripID: trip.id)
        }
        let us = Trips.usAugust2026()
        return TripLibrary(trips: [us], activeTripID: us.id)
    }

    static func saveLibrary(_ library: TripLibrary, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(library) else { return }
        defaults.set(data, forKey: libraryKey)
    }

    static func load(from defaults: UserDefaults) -> Trip? {
        loadLibrary(from: defaults).active
    }

    static func save(_ trip: Trip, to defaults: UserDefaults) {
        var lib = loadLibrary(from: defaults)
        if let i = lib.trips.firstIndex(where: { $0.id == trip.id }) {
            lib.trips[i] = trip
            lib.activeTripID = trip.id
        } else {
            lib.trips.append(trip)
            lib.activeTripID = trip.id
        }
        saveLibrary(lib, to: defaults)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: libraryKey)
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

    /// Weekday, date, and time — e.g. "Sat 29 Aug, 07:30".
    static func formatWhen(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = "EEE d MMM, HH:mm"
        return f.string(from: date)
    }

    static func formatWhen(_ date: Date, timeZone: TimeZone, city: String) -> String {
        "\(formatWhen(date, timeZone: timeZone)) \(city)"
    }

    static func formatSleepWindow(sleep: Date, wake: Date, timeZone: TimeZone, city: String? = nil) -> String {
        let range = "\(formatWhen(sleep, timeZone: timeZone)) → \(formatWhen(wake, timeZone: timeZone))"
        if let city, !city.isEmpty {
            return "Tonight · \(range) · \(city) time"
        }
        return range
    }

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
