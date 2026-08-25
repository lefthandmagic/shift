import Foundation

enum Trips {
    static let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!
    static let newYork = TimeZone(identifier: "America/New_York")!
    static let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    /// Praveen's US trip 29 Aug – 11 Sep 2026.
    static func usAugust2026() -> Trip {
        let ams = amsterdam
        let et = newYork
        let pt = losAngeles

        let pre = ClockMath.date(year: 2026, month: 8, day: 26, hour: 0, minute: 0, timeZone: ams)
        let outboundDep = ClockMath.date(year: 2026, month: 8, day: 29, hour: 10, minute: 40, timeZone: ams)
        let outboundArr = ClockMath.date(year: 2026, month: 8, day: 29, hour: 14, minute: 45, timeZone: et)
        let atlArrive = ClockMath.date(year: 2026, month: 9, day: 1, hour: 20, minute: 19, timeZone: et)
        let laxArrive = ClockMath.date(year: 2026, month: 9, day: 3, hour: 16, minute: 0, timeZone: pt)
        let sfoArrive = ClockMath.date(year: 2026, month: 9, day: 6, hour: 15, minute: 50, timeZone: pt)
        let returnDep = ClockMath.date(year: 2026, month: 9, day: 10, hour: 13, minute: 45, timeZone: pt)
        let returnArr = ClockMath.date(year: 2026, month: 9, day: 11, hour: 9, minute: 5, timeZone: ams)
        let recoveryEnd = ClockMath.date(year: 2026, month: 9, day: 16, hour: 0, minute: 0, timeZone: ams)

        let katseyeStart = ClockMath.date(year: 2026, month: 9, day: 11, hour: 20, minute: 0, timeZone: ams)
        let katseyeEnd = ClockMath.date(year: 2026, month: 9, day: 11, hour: 23, minute: 0, timeZone: ams)

        return Trip(
            name: "US · 29 Aug–11 Sep",
            homeTimeZone: ams,
            segments: [
                TripSegment(name: "Amsterdam", timeZone: ams, start: pre, end: outboundDep, isFlight: false),
                TripSegment(name: "AMS → Miami", timeZone: et, start: outboundDep, end: outboundArr, isFlight: true),
                TripSegment(name: "Miami", timeZone: et, start: outboundArr, end: atlArrive, isFlight: false),
                TripSegment(name: "Atlanta", timeZone: et, start: atlArrive, end: laxArrive, isFlight: false),
                TripSegment(name: "Los Angeles", timeZone: pt, start: laxArrive, end: sfoArrive, isFlight: false),
                TripSegment(name: "San Francisco", timeZone: pt, start: sfoArrive, end: returnDep, isFlight: false),
                TripSegment(name: "SFO → Amsterdam", timeZone: ams, start: returnDep, end: returnArr, isFlight: true),
                TripSegment(name: "Amsterdam", timeZone: ams, start: returnArr, end: recoveryEnd, isFlight: false),
            ],
            events: [
                TripEvent(name: "KATSEYE · Ziggo Dome", start: katseyeStart, end: katseyeEnd),
            ]
        )
    }
}
