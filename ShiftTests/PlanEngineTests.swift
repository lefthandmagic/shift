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
        // By LA the engine has already been sliding toward Pacific, so first LA night is close to local.
        XCTAssertLessThan(la!.hoursOff, 3.5)
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
        let day = plans.first { $0.locationName == "Amsterdam" }
        XCTAssertNotNil(day)
        let gap = day!.targetSleep.timeIntervalSince(day!.caffeineCutoff)
        XCTAssertEqual(gap, 8 * 3600, accuracy: 60)
    }

    func testSaturdayFlightForcesWakeBeforeEleven() {
        let ams = Trips.amsterdam
        let eleven = ClockMath.date(year: 2026, month: 8, day: 29, hour: 11, minute: 0, timeZone: ams)
        let leaveBy = ClockMath.date(year: 2026, month: 8, day: 29, hour: 7, minute: 30, timeZone: ams)
        let friday = plans.first {
            $0.locationName == "Amsterdam"
                && ClockMath.format($0.dayStart, timeZone: ams, template: "d MMM") == "28 Aug"
        }
        XCTAssertNotNil(friday, "Friday night in Amsterdam should own Saturday morning’s wake")
        XCTAssertLessThan(friday!.targetWake, eleven)
        XCTAssertLessThanOrEqual(friday!.targetWake.timeIntervalSince(leaveBy), 60)
        XCTAssertNotNil(friday!.constraintNote)
        XCTAssertTrue(friday!.constraintNote?.contains("10:30") == true)
    }

    func testSaturdayIsMiamiNightNotAmsterdamLieIn() {
        let ams = Trips.amsterdam
        let et = Trips.newYork
        let amsterdamSaturday = plans.filter {
            $0.locationName == "Amsterdam"
                && ClockMath.format($0.dayStart, timeZone: ams, template: "d MMM") == "29 Aug"
        }
        XCTAssertTrue(amsterdamSaturday.isEmpty, "leave AMS at 10:30 — no Amsterdam night on Sat 29")

        let saturday = plans.filter {
            ClockMath.format($0.dayStart, timeZone: $0.timeZone, template: "d MMM") == "29 Aug"
        }
        XCTAssertEqual(saturday.count, 1)
        XCTAssertTrue(saturday[0].locationName.contains("Miami"))
        XCTAssertEqual(saturday[0].timeZone.identifier, "America/New_York")
        let sleepHour = hour(saturday[0].targetSleep, tz: et)
        XCTAssertTrue(sleepHour >= 20 || sleepHour <= 2, "Miami tonight, not a 03:00 Amsterdam lie-in, got \(sleepHour)")
        XCTAssertTrue(saturday[0].constraintNote?.contains("land") == true
                      || saturday[0].constraintNote?.contains("Land") == true)
    }

    func testSaturdayFlightIsOnTheTimeline() {
        let et = Trips.newYork
        let saturday = plans.first {
            $0.locationName.contains("Miami")
                && ClockMath.format($0.dayStart, timeZone: et, template: "d MMM") == "29 Aug"
        }
        XCTAssertNotNil(saturday?.inFlight)
        XCTAssertEqual(saturday?.inFlight?.start, ClockMath.date(year: 2026, month: 8, day: 29, hour: 10, minute: 30, timeZone: Trips.amsterdam))
        XCTAssertTrue(saturday!.actions.contains { $0.kind == .stayAwake })
        XCTAssertTrue(saturday!.actions.contains { $0.title == "Shades down" })
        XCTAssertTrue(saturday!.actions.contains { $0.title == "Shades up" })
        XCTAssertTrue(saturday!.actions.contains { $0.kind == .land })
        let friday = plans.first {
            $0.locationName == "Amsterdam"
                && ClockMath.format($0.dayStart, timeZone: Trips.amsterdam, template: "d MMM") == "28 Aug"
        }
        XCTAssertFalse(friday!.actions.contains { $0.title == "On the plane" })
        XCTAssertFalse(friday!.actions.contains { $0.kind == .stayAwake })
        let midday = ClockMath.date(year: 2026, month: 8, day: 29, hour: 12, minute: 0, timeZone: Trips.amsterdam)
        let current = PlanEngine.plan(for: midday, in: plans)
        XCTAssertTrue(current?.locationName.contains("Miami") == true)
    }

    func testCompactRouteDropsDuplicateCitiesAndFlights() {
        XCTAssertEqual(
            trip.compactRoute,
            "Amsterdam → Miami → Atlanta → Los Angeles → San Francisco → Amsterdam"
        )
    }

    func testTuesdayNightIsAtlantaNotMiami() {
        let et = Trips.newYork
        let tuesdayMiami = plans.filter {
            $0.locationName == "Miami"
                && ClockMath.format($0.dayStart, timeZone: et, template: "d MMM") == "1 Sep"
        }
        XCTAssertTrue(tuesdayMiami.isEmpty, "leave Miami 20:19 — no Miami night on Tue 1 Sep")
        let tuesday = plans.first {
            ClockMath.format($0.dayStart, timeZone: $0.timeZone, template: "d MMM") == "1 Sep"
        }
        XCTAssertEqual(tuesday?.locationName, "Atlanta")
    }

    func testNoFakeDaytimeFlightNight() {
        let outboundNights = plans.filter { $0.locationName.contains("AMS →") }
        XCTAssertTrue(outboundNights.isEmpty, "daytime AMS→Miami must not own a sleep night")
        XCTAssertTrue(plans.contains { $0.locationName.contains("SFO") && $0.kind == .flight })
    }

    func testEveryNightHasCoffeeAndLight() {
        for plan in plans {
            XCTAssertTrue(plan.actions.contains { $0.kind == .caffeineOk }, plan.locationName)
            XCTAssertTrue(plan.actions.contains { $0.kind == .caffeineCutoff }, plan.locationName)
            XCTAssertEqual(plan.targetSleep.timeIntervalSince(plan.caffeineCutoff), 8 * 3600, accuracy: 60)
        }
        let wed = plans.first {
            $0.locationName == "Amsterdam"
                && ClockMath.format($0.dayStart, timeZone: Trips.amsterdam, template: "d MMM") == "26 Aug"
        }
        XCTAssertNotNil(wed?.lightSeek)
    }

    func testMelatoninOnlyWhenEnabled() {
        XCTAssertFalse(plans.contains { $0.actions.contains { $0.kind == .melatonin } })
        var on = SleepSchedule()
        on.useMelatonin = true
        let withMel = PlanEngine.build(trip: trip, schedule: on)
        XCTAssertTrue(withMel.contains { $0.actions.contains { $0.kind == .melatonin } })
    }

    func testSlidesTowardPacificAfterMiami() {
        let et = Trips.newYork
        let sunday = plans.first {
            $0.locationName == "Miami"
                && ClockMath.format($0.dayStart, timeZone: et, template: "d MMM") == "30 Aug"
        }
        let monday = plans.first {
            $0.locationName == "Miami"
                && ClockMath.format($0.dayStart, timeZone: et, template: "d MMM") == "31 Aug"
        }
        XCTAssertNotNil(sunday)
        XCTAssertNotNil(monday)
        XCTAssertGreaterThan(
            monday!.targetSleep.timeIntervalSince(sunday!.targetSleep),
            24 * 3600,
            "Monday bedtime should be later than Sunday as we slide toward Pacific"
        )
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

    func testLibraryKeepsTwoTrips() {
        let suite = "shift.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = AppModel(defaults: defaults, trip: Trips.usAugust2026())
        model.addTrip(Trips.blank(name: "London"))
        XCTAssertEqual(model.trips.count, 2)
        XCTAssertEqual(model.trip.name, "London")

        let reloaded = AppModel(defaults: defaults)
        XCTAssertEqual(reloaded.trips.count, 2)
        XCTAssertEqual(reloaded.trip.name, "London")
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

    func testFormatWhenIncludesWeekdayAndTime() {
        let at = ClockMath.date(year: 2026, month: 8, day: 29, hour: 7, minute: 30, timeZone: Trips.amsterdam)
        XCTAssertEqual(
            ClockMath.formatWhen(at, timeZone: Trips.amsterdam),
            "Sat 29 Aug, 07:30"
        )
        XCTAssertEqual(
            ClockMath.formatWhen(at, timeZone: Trips.amsterdam, city: "Amsterdam"),
            "Sat 29 Aug, 07:30 Amsterdam"
        )
    }

    func testNightDateKeepsAfterMidnightSleepOnThePreviousEvening() {
        let ams = Trips.amsterdam
        let et = Trips.newYork
        let delayed = ClockMath.date(year: 2026, month: 8, day: 28, hour: 1, minute: 0, timeZone: ams)
        let fridayNight = ClockMath.date(year: 2026, month: 8, day: 28, hour: 23, minute: 30, timeZone: ams)
        XCTAssertEqual(ClockMath.formatNight(delayed, timeZone: ams), "Thu 27 Aug")
        XCTAssertEqual(ClockMath.formatNight(fridayNight, timeZone: ams), "Fri 28 Aug")

        let miamiSaturday = ClockMath.date(year: 2026, month: 8, day: 29, hour: 23, minute: 0, timeZone: et)
        XCTAssertEqual(ClockMath.formatNight(miamiSaturday, timeZone: ams), "Sat 29 Aug")
    }

    func testUSTripNightLabelsAreUniqueOnThePhoneClock() {
        let plans = PlanEngine.build(trip: Trips.usAugust2026(), schedule: SleepSchedule())
        let now = ClockMath.date(year: 2026, month: 8, day: 27, hour: 20, minute: 42, timeZone: Trips.amsterdam)
        let labels = PlanEngine.relevantPlans(plans, at: now).map {
            ClockMath.formatNight($0.targetSleep, timeZone: Trips.amsterdam)
        }
        XCTAssertEqual(labels.count, Set(labels).count, "duplicate night labels: \(labels)")
        XCTAssertTrue(labels.contains("Thu 27 Aug"))
        XCTAssertTrue(labels.contains("Fri 28 Aug"))
        XCTAssertTrue(labels.contains("Sat 29 Aug"))
    }

    func testLocalDayRangeIsMidnightToMidnight() {
        let tz = TimeZone(identifier: "Europe/Amsterdam")!
        let afternoon = ClockMath.date(year: 2026, month: 8, day: 27, hour: 14, minute: 30, timeZone: tz)
        let range = ClockMath.localDayRange(containing: afternoon, timeZone: tz)
        XCTAssertEqual(ClockMath.format(range.lowerBound, timeZone: tz, template: "d MMM"), "27 Aug")
        XCTAssertEqual(ClockMath.format(range.lowerBound, timeZone: tz), "00:00")
        XCTAssertEqual(ClockMath.format(range.upperBound, timeZone: tz, template: "d MMM"), "28 Aug")
        XCTAssertEqual(ClockMath.format(range.upperBound, timeZone: tz), "00:00")
        XCTAssertEqual(range.upperBound.timeIntervalSince(range.lowerBound), 24 * 3600, accuracy: 1)
    }
}

final class PlanRelevanceTests: XCTestCase {
    func testRelevantPlansDropsFinishedNightsAndKeepsTonightOnward() {
        let plans = PlanEngine.build(trip: Trips.usAugust2026(), schedule: SleepSchedule())
        let now = ClockMath.date(year: 2026, month: 8, day: 27, hour: 14, minute: 30, timeZone: Trips.amsterdam)
        let relevant = PlanEngine.relevantPlans(plans, at: now)
        XCTAssertFalse(relevant.contains {
            ClockMath.format($0.dayStart, timeZone: $0.timeZone, template: "d MMM") == "26 Aug"
        })
        XCTAssertTrue(relevant.contains {
            ClockMath.format($0.dayStart, timeZone: $0.timeZone, template: "d MMM") == "27 Aug"
        })
        XCTAssertEqual(
            relevant.first.map { ClockMath.format($0.dayStart, timeZone: $0.timeZone, template: "d MMM") },
            "27 Aug"
        )
    }

    func testRelevantPlansKeepsLastNightWhileYouAreStillInIt() {
        let plans = PlanEngine.build(trip: Trips.usAugust2026(), schedule: SleepSchedule())
        let now = ClockMath.date(year: 2026, month: 8, day: 27, hour: 6, minute: 0, timeZone: Trips.amsterdam)
        let relevant = PlanEngine.relevantPlans(plans, at: now)
        XCTAssertTrue(relevant.contains {
            ClockMath.format($0.dayStart, timeZone: $0.timeZone, template: "d MMM") == "26 Aug"
        })
    }
}
