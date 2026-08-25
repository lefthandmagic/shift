import XCTest
@testable import Shift

final class PlanEngineTests: XCTestCase {
    private let trip = Trips.usAugust2026()
    private let schedule = SleepSchedule()
    private lazy var plans: [DayPlan] = PlanEngine.build(trip: trip, schedule: schedule)

    func testPlanCoversPreShiftThroughRecovery() {
        XCTAssertGreaterThanOrEqual(plans.count, 14)
        let first = plans.first
        XCTAssertEqual(first?.locationName, "Amsterdam")
        XCTAssertEqual(ClockMath.format(first!.dayStart, timeZone: Trips.amsterdam, template: "d MMM"), "26 Aug")
        XCTAssertEqual(plans.last?.locationName, "Amsterdam")
    }

    func testPreShiftDelaysBedtimeInAmsterdam() {
        let aug26 = plans.first { $0.locationName == "Amsterdam" && ClockMath.format($0.dayStart, timeZone: Trips.amsterdam, template: "d MMM") == "26 Aug" }
        XCTAssertNotNil(aug26)
        XCTAssertEqual(aug26?.kind, .delay)
        let bedHour = hour(aug26!.targetSleep, tz: Trips.amsterdam)
        XCTAssertTrue(bedHour == 0 || bedHour >= 23, "pre-shift bedtime should move later than 23:00, got \(bedHour)")
    }

    func testMiamiLandingIsWestboundDelay() {
        let miami = plans.first { $0.locationName == "Miami" || $0.locationName.contains("Miami") }
        XCTAssertNotNil(miami)
        XCTAssertTrue(miami!.kind == .delay || miami!.kind == .flight)
        XCTAssertLessThan(miami!.bodyMinusLocalHours, 6.1)
        XCTAssertGreaterThan(miami!.bodyMinusLocalHours, 0)
    }

    func testPacificJumpAddsDelay() {
        let la = plans.first { $0.locationName == "Los Angeles" }
        XCTAssertNotNil(la)
        XCTAssertGreaterThan(la!.bodyMinusLocalHours, 0.3)
        XCTAssertEqual(la!.kind, .delay)
    }

    func testReturnFlightUsesAmsterdamTime() {
        let flight = plans.first { $0.locationName.contains("SFO") }
        XCTAssertNotNil(flight)
        XCTAssertEqual(flight?.timeZone.identifier, "Europe/Amsterdam")
        XCTAssertEqual(flight?.kind, .flight)
    }

    func testKatseyePushesBedtime() {
        let ams = Trips.amsterdam
        let landingDay = plans.first {
            $0.locationName == "Amsterdam"
                && ClockMath.format($0.dayStart, timeZone: ams, template: "d MMM") == "11 Sep"
        }
        XCTAssertNotNil(landingDay)
        let concertEnd = ClockMath.date(year: 2026, month: 9, day: 11, hour: 23, minute: 0, timeZone: ams)
        XCTAssertGreaterThan(landingDay!.targetSleep, concertEnd)
        XCTAssertTrue(landingDay!.actions.contains { $0.title.contains("KATSEYE") })
    }

    func testCaffeineCutoffIsEightHoursBeforeBed() {
        let day = plans[3]
        let gap = day.targetSleep.timeIntervalSince(day.caffeineCutoff)
        XCTAssertEqual(gap, 8 * 3600, accuracy: 60)
    }

    private func hour(_ date: Date, tz: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.component(.hour, from: date)
    }
}

final class TripEditTests: XCTestCase {
    func testDefaultTripRoundTripsThroughJSON() throws {
        let original = Trips.usAugust2026()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Trip.self, from: data)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.segments.count, original.segments.count)
        XCTAssertEqual(decoded.events.count, 1)
        XCTAssertEqual(decoded.segments[4].name, "Los Angeles")
        XCTAssertEqual(decoded.segments[4].timeZone.identifier, "America/Los_Angeles")
        XCTAssertEqual(decoded.homeTimeZone.identifier, "Europe/Amsterdam")
    }

    func testEditingLosAngelesArrivalChainsAtlantaEnd() {
        var trip = Trips.usAugust2026()
        let pt = Trips.losAngeles
        guard var la = trip.segments.first(where: { $0.name == "Los Angeles" }) else {
            return XCTFail("missing Los Angeles segment")
        }
        la.start = ClockMath.date(year: 2026, month: 9, day: 3, hour: 21, minute: 30, timeZone: pt)
        trip.replaceSegment(la)

        XCTAssertEqual(trip.segments.first { $0.name == "Atlanta" }?.end, la.start)
        XCTAssertEqual(trip.segments.first { $0.name == "Los Angeles" }?.start, la.start)

        let plans = PlanEngine.build(trip: trip, schedule: SleepSchedule())
        let laPlan = plans.first { $0.locationName == "Los Angeles" }
        XCTAssertEqual(
            ClockMath.format(laPlan!.dayStart, timeZone: pt, template: "d MMM"),
            "3 Sep"
        )
    }

    func testKeepingWallClockPreservesLocalTime() {
        let ams = Trips.amsterdam
        let pt = Trips.losAngeles
        let source = ClockMath.date(year: 2026, month: 9, day: 3, hour: 16, minute: 0, timeZone: ams)
        let converted = ClockMath.keepingWallClock(source, from: ams, to: pt)
        XCTAssertEqual(ClockMath.format(converted, timeZone: pt, template: "d MMM HH:mm"), "3 Sep 16:00")
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    func testPersistsEditedTrip() {
        let suite = "shift.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var trip = Trips.usAugust2026()
        trip.name = "Custom itinerary"
        let model = AppModel(defaults: defaults, trip: trip)
        model.rebuild()

        let reloaded = AppModel(defaults: defaults)
        XCTAssertEqual(reloaded.trip.name, "Custom itinerary")
        XCTAssertEqual(reloaded.trip.segments.count, trip.segments.count)
    }
}

final class ClockMathTests: XCTestCase {
    func testAmsterdamToMiamiOffsetIsSixHours() {
        let at = ClockMath.date(year: 2026, month: 8, day: 29, hour: 16, minute: 0, timeZone: Trips.newYork)
        let delta = ClockMath.gmtOffsetHours(Trips.amsterdam, at: at)
            - ClockMath.gmtOffsetHours(Trips.newYork, at: at)
        XCTAssertEqual(delta, 6, accuracy: 0.01)
    }

    func testEasternToPacificOffsetIsThreeHours() {
        let at = ClockMath.date(year: 2026, month: 9, day: 3, hour: 16, minute: 0, timeZone: Trips.losAngeles)
        let delta = ClockMath.gmtOffsetHours(Trips.newYork, at: at)
            - ClockMath.gmtOffsetHours(Trips.losAngeles, at: at)
        XCTAssertEqual(delta, 3, accuracy: 0.01)
    }
}
