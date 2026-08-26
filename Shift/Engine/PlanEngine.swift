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

            for dayStart in nightStarts(in: segment) {
                let already = plans.contains { abs($0.dayStart.timeIntervalSince(dayStart)) < 60 }
                if already { continue }

                let probe = max(dayStart.addingTimeInterval(21 * 3600), segment.start)
                let westJump = upcomingWestboundHours(trip: trip, from: probe, home: home)
                let eastJump = upcomingEastboundHours(trip: trip, from: probe)
                let daysUntilWest = daysUntilWestbound(trip: trip, from: probe)
                let daysUntilEast = daysUntilEastbound(trip: trip, from: probe)
                let preDelay = shouldPreDelay(
                    bodyMinusLocal: bodyMinusLocal,
                    westJump: westJump,
                    daysUntilWest: daysUntilWest,
                    preShiftDays: schedule.preShiftDays
                )
                let preAdvance = shouldPreAdvance(
                    bodyMinusLocal: bodyMinusLocal,
                    eastJump: eastJump,
                    daysUntilEast: daysUntilEast,
                    preShiftDays: max(schedule.preShiftDays, 4)
                )

                let chasingWest = westJump > 0.5 && daysUntilWest <= max(schedule.preShiftDays, 4)
                let kind: ShiftKind
                if segment.isFlight {
                    kind = .flight
                } else if preDelay || chasingWest || bodyMinusLocal > 0.35 {
                    kind = .delay
                } else if preAdvance || bodyMinusLocal < -0.35 {
                    kind = .advance
                } else {
                    kind = .hold
                }

                switch kind {
                case .delay:
                    let cap = chasingWest ? -westJump : 0
                    if preDelay && bodyMinusLocal <= 0.35 && westJump >= 4 {
                        bodyMinusLocal = max(cap, bodyMinusLocal - 1.0)
                    } else if chasingWest {
                        bodyMinusLocal = max(cap, bodyMinusLocal - schedule.delayRateHours)
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

                plans.append(
                    makeDay(
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
                )
            }
        }

        _ = now
        return plans
    }

    static func plan(for date: Date, in plans: [DayPlan]) -> DayPlan? {
        let sorted = plans.sorted { $0.targetSleep < $1.targetSleep }
        if let covering = sorted.last(where: {
            date >= $0.targetSleep.addingTimeInterval(-4 * 3600)
                && date <= $0.targetWake.addingTimeInterval(3 * 3600)
        }) {
            return covering
        }
        for (i, plan) in sorted.enumerated() {
            let nextSleep = i + 1 < sorted.count
                ? sorted[i + 1].targetSleep
                : plan.targetWake.addingTimeInterval(18 * 3600)
            if date >= plan.targetWake && date < nextSleep {
                return plan
            }
        }
        return sorted.min(by: { abs($0.dayStart.timeIntervalSince(date)) < abs($1.dayStart.timeIntervalSince(date)) })
    }

    static func currentAction(at date: Date, plan: DayPlan) -> ActionItem? {
        let upcoming = plan.actions.filter { $0.date >= date.addingTimeInterval(-20 * 60) }
        return upcoming.min(by: { $0.date < $1.date })
    }

    // MARK: - Nights

    /// Local calendar dates where this stop actually owns the night:
    /// still there at 21:00, or (flights) overlapping 22:00–06:00 in the segment timezone.
    static func nightStarts(in segment: TripSegment) -> [Date] {
        let tz = segment.timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        var seen = Set<TimeInterval>()
        var out: [Date] = []

        func consider(_ dayStart: Date) {
            guard occupiesNight(dayStart, segment: segment) else { return }
            let key = dayStart.timeIntervalSince1970.rounded()
            guard seen.insert(key).inserted else { return }
            out.append(dayStart)
        }

        var d = ClockMath.startOfDay(segment.start, timeZone: tz)
        if let prev = cal.date(byAdding: .day, value: -1, to: d) {
            consider(prev)
        }
        let last = ClockMath.startOfDay(segment.end, timeZone: tz)
        while d <= last.addingTimeInterval(86_400) {
            consider(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
            if d > segment.end.addingTimeInterval(36 * 3600) { break }
        }
        return out
    }

    static func occupiesNight(_ dayStart: Date, segment: TripSegment) -> Bool {
        let tz = segment.timeZone
        if !segment.isFlight {
            let settle = ClockMath.at(hour: 21, minute: 0, on: dayStart, timeZone: tz)
            return settle >= segment.start && settle < segment.end
        }
        // Real overnight: in the air at 02:00 destination-local the next morning.
        // A 10:30 AMS departure is 04:30 in Miami — that must not count as a Miami night.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        guard let nextMorning = cal.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let twoAM = ClockMath.at(hour: 2, minute: 0, on: nextMorning, timeZone: tz)
        return twoAM >= segment.start && twoAM < segment.end
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
        let city = DayPlan.clockCity(from: locationName)

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
                let flightWhen = ClockMath.formatWhen(leave.flight.start, timeZone: tz, city: city)
                let wakeWhen = ClockMath.formatWhen(targetWake, timeZone: tz, city: city)
                constraintNote = "Wake by \(wakeWhen) for \(leave.flight.name) at \(flightWhen). You can’t sleep in later — you have to be up and moving for that flight."
            }
        }

        if constraintNote == nil, let arrival = inboundFlight(on: dayStart, tz: tz, trip: trip) {
            let land = ClockMath.formatWhen(arrival.end, timeZone: tz, city: city)
            constraintNote = "You land \(land). Tonight’s sleep is in \(city) — not origin time."
        }

        let caffeineCutoff = targetSleep.addingTimeInterval(-8 * 3600)
        let wake = targetWake
        let arrival = inboundFlight(on: dayStart, tz: tz, trip: trip)
        let (seek, avoid) = lightWindows(
            kind: kind,
            dayStart: dayStart,
            wake: wake,
            sleep: targetSleep,
            tz: tz,
            seekFloor: arrival?.end
        )

        let headline = headlineText(kind: kind, location: locationName, hoursOff: abs(bodyMinusLocal), isFlight: isFlight)
        let summary = summaryText(
            kind: kind,
            city: city,
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
                detail: "Get up \(ClockMath.formatWhen(wake, timeZone: tz, city: city))."
                    + (constraintNote != nil && constraintNote?.contains("Wake by") == true ? " Flight morning — don’t snooze." : "")
            ),
        ]
        let coffeeStart = ClockMath.at(hour: 7, minute: 0, on: dayStart, timeZone: tz)
        actions.append(
            ActionItem(
                date: min(max(coffeeStart, dayStart.addingTimeInterval(7 * 3600)), caffeineCutoff.addingTimeInterval(-60)),
                kind: .caffeineOk,
                title: "Coffee is OK",
                detail: "Coffee is OK until \(ClockMath.formatWhen(caffeineCutoff, timeZone: tz, city: city)). None after that."
            )
        )
        actions.append(
            ActionItem(
                date: caffeineCutoff,
                kind: .caffeineCutoff,
                title: "Coffee cutoff",
                detail: "Last coffee before \(ClockMath.formatWhen(caffeineCutoff, timeZone: tz, city: city)). None after that."
            )
        )
        if let seek {
            actions.append(
                ActionItem(
                    date: seek.start,
                    kind: .seekLight,
                    title: "Get outdoor light",
                    detail: "Bright outdoor light \(ClockMath.formatWhen(seek.start, timeZone: tz, city: city))–\(ClockMath.format(seek.end, timeZone: tz)). This is what shifts the clock."
                )
            )
        }
        if let avoid {
            actions.append(
                ActionItem(
                    date: avoid.start,
                    kind: .avoidLight,
                    title: "Keep light low",
                    detail: "Dim indoor light \(ClockMath.formatWhen(avoid.start, timeZone: tz, city: city))–\(ClockMath.format(avoid.end, timeZone: tz)). Bright morning light here pushes you the wrong way."
                )
            )
        }
        if schedule.useMelatonin, kind == .delay || kind == .flight {
            let when = wake.addingTimeInterval(30 * 60)
            actions.append(
                ActionItem(
                    date: when,
                    kind: .melatonin,
                    title: "Melatonin (optional)",
                    detail: "If you use it, low dose (~0.5 mg) around \(ClockMath.formatWhen(when, timeZone: tz, city: city)). Not medical advice — ask a clinician."
                )
            )
        }
        if schedule.useMelatonin, kind == .advance {
            let when = targetSleep.addingTimeInterval(-5 * 3600)
            if when > wake {
                actions.append(
                    ActionItem(
                        date: when,
                        kind: .melatonin,
                        title: "Melatonin (optional)",
                        detail: "If you use it, low dose (~0.5 mg) around \(ClockMath.formatWhen(when, timeZone: tz, city: city)). Not medical advice — ask a clinician."
                    )
                )
            }
        }
        actions.append(
            ActionItem(
                date: targetSleep.addingTimeInterval(-30 * 60),
                kind: .move,
                title: "Wind down",
                detail: "Dim lights from \(ClockMath.formatWhen(targetSleep.addingTimeInterval(-30 * 60), timeZone: tz, city: city))."
            )
        )
        actions.append(
            ActionItem(
                date: targetSleep,
                kind: .sleep,
                title: "Sleep tonight",
                detail: ClockMath.formatSleepWindow(sleep: targetSleep, wake: targetWake, timeZone: tz, city: city)
            )
        )
        if isFlight {
            let takeoff = trip.segments.first(where: { $0.isFlight && $0.name == locationName })?.start ?? dayStart.addingTimeInterval(10 * 3600)
            actions.append(
                ActionItem(
                    date: takeoff,
                    kind: .hydrate,
                    title: "Hydrate on the plane",
                    detail: "Water over alcohol."
                )
            )
            actions.append(
                ActionItem(
                    date: takeoff.addingTimeInterval(2 * 3600),
                    kind: .nap,
                    title: "Optional plane nap",
                    detail: "Stay awake if you can. If wrecked, one 60–90 min nap max — not a full night. Sleep on board only if it overlaps tonight’s \(city) window."
                )
            )
        }
        let outbound = trip.segments.first { $0.isFlight && abs($0.start.timeIntervalSince(wake)) < 6 * 3600 }
        if let flight = outbound, !isFlight {
            actions.append(
                ActionItem(
                    date: flight.start,
                    kind: .nap,
                    title: "On the plane",
                    detail: "Stay awake if you can. Optional 60–90 min nap. Window shades down in the morning, up later. No full sleep — tonight is at destination."
                )
            )
        }
        if arrival != nil, !isFlight {
            let napEndLimit = targetSleep.addingTimeInterval(-6 * 3600)
            if let land = arrival?.end, land.addingTimeInterval(90 * 60) < napEndLimit {
                actions.append(
                    ActionItem(
                        date: land.addingTimeInterval(30 * 60),
                        kind: .nap,
                        title: "Nap only if wrecked",
                        detail: "Optional 20–30 min, done by \(ClockMath.formatWhen(napEndLimit, timeZone: tz, city: city)). Don’t start a second night."
                    )
                )
            }
        }
        for event in dayEvents {
            actions.append(
                ActionItem(
                    date: event.start,
                    kind: .note,
                    title: event.name,
                    detail: "\(ClockMath.formatWhen(event.start, timeZone: tz, city: city))–\(ClockMath.format(event.end, timeZone: tz)). Bedtime after this."
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

    private static func inboundFlight(on dayStart: Date, tz: TimeZone, trip: Trip) -> TripSegment? {
        trip.segments.first { flight in
            guard flight.isFlight else { return false }
            let landDay = ClockMath.startOfDay(flight.end, timeZone: tz)
            return abs(landDay.timeIntervalSince(dayStart)) < 60
        }
    }

    private static func lightWindows(
        kind: ShiftKind,
        dayStart: Date,
        wake: Date,
        sleep: Date,
        tz: TimeZone,
        seekFloor: Date?
    ) -> (DateInterval?, DateInterval?) {
        let afternoon = ClockMath.at(hour: 14, minute: 0, on: dayStart, timeZone: tz)
        switch kind {
        case .delay, .flight:
            let seekEnd = sleep.addingTimeInterval(-90 * 60)
            var seekStart = afternoon
            if let floor = seekFloor {
                seekStart = max(seekStart, floor)
            }
            let seek = interval(from: seekStart, to: seekEnd)
            let avoid = interval(from: wake, to: wake.addingTimeInterval(3 * 3600))
            return (seek, avoid)
        case .advance:
            let seek = interval(from: wake, to: wake.addingTimeInterval(3 * 3600))
            let avoidStart = ClockMath.at(hour: 18, minute: 0, on: dayStart, timeZone: tz)
            let avoid = interval(from: avoidStart, to: sleep)
            return (seek, avoid)
        case .hold:
            return (interval(from: wake, to: wake.addingTimeInterval(3 * 3600)), nil)
        }
    }

    private static func interval(from start: Date, to end: Date) -> DateInterval? {
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private static func headlineText(kind: ShiftKind, location: String, hoursOff: Double, isFlight: Bool) -> String {
        if isFlight { return "Flight night · \(location)" }
        let off = hoursOff < 0.4 ? "adapted" : String(format: "%.0fh off", hoursOff)
        switch kind {
        case .delay: return "Sleep later · \(location) · \(off)"
        case .advance: return "Sleep earlier · \(location) · \(off)"
        case .hold: return "Local night · \(location)"
        case .flight: return "Flight · \(location)"
        }
    }

    private static func summaryText(
        kind: ShiftKind,
        city: String,
        tz: TimeZone,
        sleep: Date,
        wake: Date,
        constraint: String?
    ) -> String {
        let window = ClockMath.formatSleepWindow(sleep: sleep, wake: wake, timeZone: tz, city: city)
        let core: String
        switch kind {
        case .delay:
            core = "All times \(city) local. Push bedtime later. \(window). Evening outdoor light, keep mornings dim. Coffee until the cutoff, then none."
        case .advance:
            core = "All times \(city) local. Pull bedtime earlier toward night there. \(window). Morning light, dim evenings."
        case .hold:
            core = "All times \(city) local. Stay on local time. \(window)."
        case .flight:
            core = "All times \(city) local (destination). Sleep on the plane only if it overlaps \(window)."
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
