import Foundation

enum PlanEngine {
    static func build(
        trip: Trip,
        schedule: SleepSchedule,
        now: Date = Date()
    ) -> [DayPlan] {
        guard !trip.segments.isEmpty else { return [] }

        let home = trip.homeTimeZone
        var bodyMinusLocal = 0.0
        var currentTZ = home
        var plans: [DayPlan] = []

        for segment in trip.segments {
            let tz = segment.timeZone
            if tz.identifier != currentTZ.identifier {
                let at = segment.start
                bodyMinusLocal += ClockMath.gmtOffsetHours(currentTZ, at: at)
                    - ClockMath.gmtOffsetHours(tz, at: at)
                currentTZ = tz
            }

            var dayStart = ClockMath.startOfDay(segment.start, timeZone: tz)
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = tz

            while dayStart < segment.end {
                let already = plans.contains { abs($0.dayStart.timeIntervalSince(dayStart)) < 60 }
                if !already {
                    let probe = max(dayStart.addingTimeInterval(10 * 3600), segment.start)
                    let westJump = upcomingWestboundHours(trip: trip, from: probe, home: home)
                    let eastJump = upcomingEastboundHours(trip: trip, from: probe)
                    let preDelay = shouldPreDelay(
                        bodyMinusLocal: bodyMinusLocal,
                        westJump: westJump,
                        daysUntilWest: daysUntilWestbound(trip: trip, from: probe),
                        preShiftDays: schedule.preShiftDays
                    )
                    let preAdvance = shouldPreAdvance(
                        bodyMinusLocal: bodyMinusLocal,
                        eastJump: eastJump,
                        daysUntilEast: daysUntilEastbound(trip: trip, from: probe),
                        preShiftDays: max(schedule.preShiftDays, 4)
                    )

                    let kind: ShiftKind
                    if segment.isFlight {
                        kind = .flight
                    } else if preDelay || bodyMinusLocal > 0.35 {
                        kind = .delay
                    } else if preAdvance || bodyMinusLocal < -0.35 {
                        kind = .advance
                    } else {
                        kind = .hold
                    }

                    switch kind {
                    case .delay:
                        if preDelay && bodyMinusLocal <= 0.35 {
                            let cap = -(max(westJump, 0) - 2)
                            bodyMinusLocal = max(cap, bodyMinusLocal - 1.0)
                        } else {
                            bodyMinusLocal = max(0, bodyMinusLocal - schedule.delayRateHours)
                        }
                    case .advance:
                        if preAdvance && bodyMinusLocal >= -0.35 {
                            let cap = max(eastJump, 0) - 2
                            bodyMinusLocal = min(cap, bodyMinusLocal + 1.0)
                        } else {
                            bodyMinusLocal = min(0, bodyMinusLocal + schedule.advanceRateHours)
                        }
                    case .hold, .flight:
                        break
                    }

                    let plan = makeDay(
                        dayStart: dayStart,
                        tz: tz,
                        locationName: segment.name,
                        bodyMinusLocal: bodyMinusLocal,
                        kind: kind,
                        isFlight: segment.isFlight,
                        schedule: schedule,
                        events: trip.events,
                        trip: trip
                    )
                    plans.append(plan)
                }

                guard let next = cal.date(byAdding: .day, value: 1, to: dayStart) else { break }
                dayStart = next
            }
        }

        _ = now
        return plans
    }

    static func plan(for date: Date, in plans: [DayPlan]) -> DayPlan? {
        plans.first { date >= $0.dayStart && date < $0.dayStart.addingTimeInterval(86_400) }
            ?? plans.min(by: { abs($0.dayStart.timeIntervalSince(date)) < abs($1.dayStart.timeIntervalSince(date)) })
    }

    static func currentAction(at date: Date, plan: DayPlan) -> ActionItem? {
        let upcoming = plan.actions.filter { $0.date >= date.addingTimeInterval(-20 * 60) }
        return upcoming.min(by: { $0.date < $1.date })
    }

    // MARK: - Day

    private static func makeDay(
        dayStart: Date,
        tz: TimeZone,
        locationName: String,
        bodyMinusLocal: Double,
        kind: ShiftKind,
        isFlight: Bool,
        schedule: SleepSchedule,
        events: [TripEvent],
        trip: Trip
    ) -> DayPlan {
        let sleepLength = schedule.sleepLengthHours * 3600
        let idealLocalBed = ClockMath.at(
            hour: schedule.bedHour,
            minute: schedule.bedMinute,
            on: dayStart,
            timeZone: tz
        )
        var targetSleep = idealLocalBed.addingTimeInterval(-bodyMinusLocal * 3600)
        var targetWake = targetSleep.addingTimeInterval(sleepLength)
        var constraintNote: String?

        let dayEvents = events.filter {
            $0.start >= dayStart && $0.start < dayStart.addingTimeInterval(86_400)
        }
        for event in dayEvents where event.end > targetSleep {
            targetSleep = event.end.addingTimeInterval(30 * 60)
            targetWake = targetSleep.addingTimeInterval(sleepLength)
        }

        if let leave = mustLeaveBy(trip: trip, after: targetSleep.addingTimeInterval(-2 * 3600), before: targetWake.addingTimeInterval(14 * 3600), leadHours: schedule.airportLeadHours) {
            if targetWake > leave.leaveBy + 60 {
                targetWake = leave.leaveBy
                targetSleep = targetWake.addingTimeInterval(-sleepLength)
                let flightWhen = ClockMath.formatWhen(leave.flight.start, timeZone: tz)
                let wakeWhen = ClockMath.formatWhen(targetWake, timeZone: tz)
                constraintNote = "Wake by \(wakeWhen) for \(leave.flight.name) at \(flightWhen). You can’t sleep in later — you have to be up and moving for that flight."
            }
        }

        let caffeineCutoff = targetSleep.addingTimeInterval(-8 * 3600)
        let wake = targetWake
        let (seek, avoid) = lightWindows(
            kind: kind,
            dayStart: dayStart,
            wake: wake,
            sleep: targetSleep,
            tz: tz
        )

        let headline = headlineText(kind: kind, location: locationName, hoursOff: abs(bodyMinusLocal), isFlight: isFlight)
        let summary = summaryText(
            kind: kind,
            location: locationName,
            tz: tz,
            sleep: targetSleep,
            wake: targetWake,
            constraint: constraintNote
        )

        var actions: [ActionItem] = [
            ActionItem(
                date: wake,
                kind: .wake,
                title: "Wake",
                detail: "Get up \(ClockMath.formatWhen(wake, timeZone: tz))."
                    + (constraintNote != nil ? " Flight morning — don’t snooze." : "")
            ),
        ]
        if let seek {
            actions.append(
                ActionItem(
                    date: seek.start,
                    kind: .seekLight,
                    title: "Seek bright light",
                    detail: "Outdoor or bright indoor light \(ClockMath.formatWhen(seek.start, timeZone: tz))–\(ClockMath.format(seek.end, timeZone: tz))."
                )
            )
        }
        if let avoid {
            actions.append(
                ActionItem(
                    date: avoid.start,
                    kind: .avoidLight,
                    title: "Avoid bright light",
                    detail: "Sunglasses / dim screens \(ClockMath.formatWhen(avoid.start, timeZone: tz))–\(ClockMath.format(avoid.end, timeZone: tz))."
                )
            )
        }
        actions.append(
            ActionItem(
                date: caffeineCutoff,
                kind: .caffeineCutoff,
                title: "Caffeine cutoff",
                detail: "Last coffee before \(ClockMath.formatWhen(caffeineCutoff, timeZone: tz))."
            )
        )
        actions.append(
            ActionItem(
                date: targetSleep.addingTimeInterval(-30 * 60),
                kind: .move,
                title: "Wind down",
                detail: "Dim lights from \(ClockMath.formatWhen(targetSleep.addingTimeInterval(-30 * 60), timeZone: tz))."
            )
        )
        actions.append(
            ActionItem(
                date: targetSleep,
                kind: .sleep,
                title: "Sleep",
                detail: ClockMath.formatSleepWindow(sleep: targetSleep, wake: targetWake, timeZone: tz)
            )
        )
        if isFlight {
            actions.append(
                ActionItem(
                    date: dayStart.addingTimeInterval(10 * 3600),
                    kind: .hydrate,
                    title: "Hydrate on the plane",
                    detail: "Water over alcohol. Sleep on board only if it overlaps tonight’s target."
                )
            )
        }
        for event in dayEvents {
            actions.append(
                ActionItem(
                    date: event.start,
                    kind: .note,
                    title: event.name,
                    detail: "\(ClockMath.formatWhen(event.start, timeZone: tz))–\(ClockMath.format(event.end, timeZone: tz)). Bedtime after this."
                )
            )
        }
        actions.sort { $0.date < $1.date }

        return DayPlan(
            dayStart: dayStart,
            timeZone: tz,
            locationName: locationName,
            bodyMinusLocalHours: bodyMinusLocal,
            targetSleep: targetSleep,
            targetWake: targetWake,
            caffeineCutoff: caffeineCutoff,
            lightSeek: seek,
            lightAvoid: avoid,
            kind: kind,
            headline: headline,
            summary: summary,
            actions: actions,
            constraintNote: constraintNote
        )
    }

    private static func mustLeaveBy(
        trip: Trip,
        after start: Date,
        before end: Date,
        leadHours: Double
    ) -> (leaveBy: Date, flight: TripSegment)? {
        var best: (Date, TripSegment)?
        for flight in trip.segments where flight.isFlight {
            let lead = (flight.durationHours >= 4 ? leadHours : min(leadHours, 2)) * 3600
            let leaveBy = flight.start.addingTimeInterval(-lead)
            if leaveBy > start && leaveBy < end {
                if best == nil || leaveBy < best!.0 {
                    best = (leaveBy, flight)
                }
            }
        }
        return best.map { (leaveBy: $0.0, flight: $0.1) }
    }

    private static func lightWindows(
        kind: ShiftKind,
        dayStart: Date,
        wake: Date,
        sleep: Date,
        tz: TimeZone
    ) -> (DateInterval?, DateInterval?) {
        let afternoon = ClockMath.at(hour: 14, minute: 0, on: dayStart, timeZone: tz)
        let evening = ClockMath.at(hour: 20, minute: 0, on: dayStart, timeZone: tz)
        let lateMorning = ClockMath.at(hour: 11, minute: 0, on: dayStart, timeZone: tz)
        switch kind {
        case .delay, .flight:
            let seek = interval(from: max(wake, afternoon), to: min(sleep, evening.addingTimeInterval(3600)))
            let avoid = interval(from: wake, to: max(wake.addingTimeInterval(3600), min(lateMorning, sleep)))
            return (seek, avoid)
        case .advance:
            let seek = interval(from: wake, to: max(wake.addingTimeInterval(2 * 3600), lateMorning))
            let avoidStart = ClockMath.at(hour: 18, minute: 0, on: dayStart, timeZone: tz)
            let avoid = interval(from: avoidStart, to: sleep)
            return (seek, avoid)
        case .hold:
            return (interval(from: wake, to: lateMorning), nil)
        }
    }

    private static func interval(from start: Date, to end: Date) -> DateInterval? {
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func headlineText(kind: ShiftKind, location: String, hoursOff: Double, isFlight: Bool) -> String {
        if isFlight { return "Flight day · \(location)" }
        let off = hoursOff < 0.4 ? "adapted" : String(format: "%.0fh off", hoursOff)
        switch kind {
        case .delay: return "Delay · \(location) · \(off)"
        case .advance: return "Advance · \(location) · \(off)"
        case .hold: return "Hold · \(location)"
        case .flight: return "Flight · \(location)"
        }
    }

    private static func summaryText(
        kind: ShiftKind,
        location: String,
        tz: TimeZone,
        sleep: Date,
        wake: Date,
        constraint: String?
    ) -> String {
        let window = ClockMath.formatSleepWindow(sleep: sleep, wake: wake, timeZone: tz)
        let core: String
        switch kind {
        case .delay:
            core = "Push sleep later toward local night in \(location). \(window). Evening light, dark morning."
        case .advance:
            core = "Pull sleep earlier toward local night in \(location). \(window). Morning light, dim evenings."
        case .hold:
            core = "Stay on local time in \(location). \(window)."
        case .flight:
            core = "Live on destination time as much as you can. Sleep \(window) only if it still fits."
        }
        if let constraint {
            return "\(constraint) \(core)"
        }
        return core
    }

    // MARK: - Jumps

    private static func upcomingWestboundHours(trip: Trip, from date: Date, home: TimeZone) -> Double {
        guard let current = trip.segment(at: date) ?? trip.segments.first else { return 0 }
        let later = trip.segments.filter { $0.start >= date }
        for next in later {
            let delta = ClockMath.gmtOffsetHours(current.timeZone, at: next.start)
                - ClockMath.gmtOffsetHours(next.timeZone, at: next.start)
            if delta > 0.5 { return delta }
        }
        _ = home
        return 0
    }

    private static func upcomingEastboundHours(trip: Trip, from date: Date) -> Double {
        guard let current = trip.segment(at: date) ?? trip.segments.first else { return 0 }
        let later = trip.segments.filter { $0.start >= date }
        for next in later {
            let delta = ClockMath.gmtOffsetHours(next.timeZone, at: next.start)
                - ClockMath.gmtOffsetHours(current.timeZone, at: next.start)
            if delta > 0.5 { return delta }
        }
        return 0
    }

    private static func daysUntilWestbound(trip: Trip, from date: Date) -> Int {
        guard let current = trip.segment(at: date) else { return 99 }
        for next in trip.segments where next.start >= date {
            let delta = ClockMath.gmtOffsetHours(current.timeZone, at: next.start)
                - ClockMath.gmtOffsetHours(next.timeZone, at: next.start)
            if delta > 0.5 {
                return max(0, Int((next.start.timeIntervalSince(date) / 86_400).rounded(.down)))
            }
        }
        return 99
    }

    private static func daysUntilEastbound(trip: Trip, from date: Date) -> Int {
        guard let current = trip.segment(at: date) else { return 99 }
        for next in trip.segments where next.start >= date {
            let delta = ClockMath.gmtOffsetHours(next.timeZone, at: next.start)
                - ClockMath.gmtOffsetHours(current.timeZone, at: next.start)
            if delta > 0.5 {
                return max(0, Int((next.start.timeIntervalSince(date) / 86_400).rounded(.down)))
            }
        }
        return 99
    }

    private static func shouldPreDelay(bodyMinusLocal: Double, westJump: Double, daysUntilWest: Int, preShiftDays: Int) -> Bool {
        westJump > 0.5 && daysUntilWest <= preShiftDays && bodyMinusLocal < westJump - 0.4
    }

    private static func shouldPreAdvance(bodyMinusLocal: Double, eastJump: Double, daysUntilEast: Int, preShiftDays: Int) -> Bool {
        eastJump > 0.5 && daysUntilEast <= preShiftDays && bodyMinusLocal > -(eastJump - 0.4)
    }
}
