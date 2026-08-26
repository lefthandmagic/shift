import SwiftUI

struct TimelineBand: Identifiable {
    enum Kind {
        case sleep, seekLight, avoidLight, caffeineOk
    }

    let start: Date
    let end: Date
    let kind: Kind
    let title: String

    var id: String {
        "\(kind)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
    }

    var color: Color {
        switch kind {
        case .sleep: return ShiftTheme.sleep
        case .seekLight: return ShiftTheme.seekLight
        case .avoidLight: return ShiftTheme.avoidLight
        case .caffeineOk: return ShiftTheme.caffeine
        }
    }
}

enum TimelineLayout {
    static func range(for plan: DayPlan) -> ClosedRange<Date> {
        var dates: [Date] = [plan.targetSleep, plan.targetWake, plan.caffeineCutoff]
        if let seek = plan.lightSeek {
            dates.append(seek.start)
            dates.append(seek.end)
        }
        if let avoid = plan.lightAvoid {
            dates.append(avoid.start)
            dates.append(avoid.end)
        }
        dates.append(contentsOf: plan.actions.map(\.date))
        let start = dates.min() ?? plan.dayStart
        let end = dates.max() ?? plan.targetWake
        let padStart = start.addingTimeInterval(-30 * 60)
        let padEnd = end.addingTimeInterval(45 * 60)
        return padStart...max(padEnd, padStart.addingTimeInterval(3 * 3600))
    }

    static func bands(for plan: DayPlan) -> [TimelineBand] {
        var out: [TimelineBand] = []
        if let ok = plan.actions.first(where: { $0.kind == .caffeineOk }), plan.caffeineCutoff > ok.date {
            out.append(TimelineBand(start: ok.date, end: plan.caffeineCutoff, kind: .caffeineOk, title: "Coffee"))
        }
        if let seek = plan.lightSeek, seek.end > seek.start {
            out.append(TimelineBand(start: seek.start, end: seek.end, kind: .seekLight, title: "Outdoor light"))
        }
        if let avoid = plan.lightAvoid, avoid.end > avoid.start {
            out.append(TimelineBand(start: avoid.start, end: avoid.end, kind: .avoidLight, title: "Low light"))
        }
        if plan.targetWake > plan.targetSleep {
            out.append(TimelineBand(start: plan.targetSleep, end: plan.targetWake, kind: .sleep, title: "Sleep"))
        }
        return out
    }

    static func visibleBands(for plan: DayPlan, in range: ClosedRange<Date>) -> [TimelineBand] {
        bands(for: plan).compactMap { band in
            let start = max(band.start, range.lowerBound)
            let end = min(band.end, range.upperBound)
            guard end > start else { return nil }
            return TimelineBand(start: start, end: end, kind: band.kind, title: band.title)
        }
    }

    static func pins(for plan: DayPlan, in range: ClosedRange<Date>) -> [ActionItem] {
        plan.actions.filter { action in
            guard range.contains(action.date) else { return false }
            switch action.kind {
            case .wake, .sleep, .caffeineCutoff, .melatonin, .nap, .hydrate, .note:
                return true
            case .seekLight, .avoidLight, .caffeineOk, .move:
                return false
            }
        }
        .sorted { $0.date < $1.date }
    }

    static func happening(at date: Date, plan: DayPlan) -> String? {
        let hits = bands(for: plan).filter { date >= $0.start && date < $0.end }
        if hits.contains(where: { $0.kind == .sleep }) { return "Sleep window" }
        if hits.contains(where: { $0.kind == .avoidLight }) { return "Keep light low" }
        if hits.contains(where: { $0.kind == .seekLight }) { return "Get outdoor light" }
        if hits.contains(where: { $0.kind == .caffeineOk }) { return "Coffee is OK" }
        return nil
    }

    static func y(date: Date, range: ClosedRange<Date>, hourHeight: CGFloat) -> CGFloat {
        let hours = date.timeIntervalSince(range.lowerBound) / 3600
        return CGFloat(max(0, hours)) * hourHeight
    }

    static func height(range: ClosedRange<Date>, hourHeight: CGFloat) -> CGFloat {
        CGFloat(range.upperBound.timeIntervalSince(range.lowerBound) / 3600) * hourHeight
    }
}

/// Full vertical day — hour rail, color bands, icons you can tap.
struct DayTimeline: View {
    let plan: DayPlan
    var now: Date? = nil
    var hourHeight: CGFloat = 34
    var rangeOverride: ClosedRange<Date>? = nil

    @State private var selected: ActionItem?

    private var range: ClosedRange<Date> { rangeOverride ?? TimelineLayout.range(for: plan) }
    private var bands: [TimelineBand] { TimelineLayout.visibleBands(for: plan, in: range) }
    private var pins: [ActionItem] { TimelineLayout.pins(for: plan, in: range) }

    var body: some View {
        let h = TimelineLayout.height(range: range, hourHeight: hourHeight)
        GeometryReader { geo in
            let timeW: CGFloat = 42
            let iconW: CGFloat = 36
            let trackX = timeW + 8
            let trackW = max(96, geo.size.width - trackX - iconW - 2)
            ZStack(alignment: .topLeading) {
                hourGrid(width: geo.size.width, height: h)
                bandColumn(trackX: trackX, trackW: trackW, height: h)
                pinColumn(x: trackX + trackW - 6, height: h)
                if let now, now >= range.lowerBound && now <= range.upperBound {
                    nowNeedle(now, width: geo.size.width, height: h)
                }
            }
        }
        .frame(height: h)
        .sheet(item: $selected) { action in
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Label(action.title, systemImage: ShiftIcons.symbol(action.kind))
                        .font(.title2.weight(.semibold))
                    Text(ClockMath.formatWhen(action.date, timeZone: plan.timeZone, city: plan.clockCity))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(ShiftTheme.accent)
                    Text(action.detail)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ShiftTheme.bg.ignoresSafeArea())
                .navigationTitle(plan.clockCity)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { selected = nil }
                    }
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }

    private func hourGrid(width: CGFloat, height: CGFloat) -> some View {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = plan.timeZone
        var hours: [Date] = []
        var cursor = ClockMath.at(
            hour: cal.component(.hour, from: range.lowerBound),
            minute: 0,
            on: range.lowerBound,
            timeZone: plan.timeZone
        )
        if cursor < range.lowerBound {
            cursor = cursor.addingTimeInterval(3600)
        }
        while cursor <= range.upperBound {
            hours.append(cursor)
            cursor = cursor.addingTimeInterval(3600)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(hours, id: \.self) { hour in
                let y = TimelineLayout.y(date: hour, range: range, hourHeight: hourHeight)
                HStack(spacing: 8) {
                    Text(ClockMath.format(hour, timeZone: plan.timeZone, template: "HH:mm"))
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                    Rectangle()
                        .fill(ShiftTheme.stroke)
                        .frame(height: 1)
                }
                .frame(width: width, alignment: .leading)
                .offset(y: y - 7)
            }
        }
        .frame(width: width, height: height, alignment: .top)
    }

    private func bandColumn(trackX: CGFloat, trackW: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(width: trackW, height: height)
                .offset(x: trackX)

            ForEach(bands) { band in
                let y = TimelineLayout.y(date: band.start, range: range, hourHeight: hourHeight)
                let h = max(16, TimelineLayout.y(date: band.end, range: range, hourHeight: hourHeight) - y)
                let inset: CGFloat = band.kind == .caffeineOk ? 10 : 0
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(band.color.opacity(band.kind == .sleep ? 0.42 : 0.26))
                    .overlay {
                        if band.kind == .avoidLight {
                            SlashOverlay(color: band.color)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(band.color.opacity(0.6), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        if h > 28 {
                            Text(band.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(band.color)
                                .padding(8)
                        }
                    }
                    .frame(width: trackW - inset * 2, height: h, alignment: .topLeading)
                    .offset(x: trackX + inset, y: y)
            }
        }
        .frame(height: height, alignment: .top)
    }

    private func pinColumn(x: CGFloat, height: CGFloat) -> some View {
        let extras = pinNudge()
        return ZStack(alignment: .topLeading) {
            ForEach(pins) { pin in
                let y = TimelineLayout.y(date: pin.date, range: range, hourHeight: hourHeight)
                Button {
                    selected = pin
                } label: {
                    Image(systemName: ShiftIcons.symbol(pin.kind))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(ShiftIcons.color(pin.kind), in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: x + (extras[pin.id] ?? 0), y: y - 14)
                .accessibilityLabel(pin.title)
            }
        }
        .frame(height: height, alignment: .top)
    }

    private func pinNudge() -> [UUID: CGFloat] {
        var extra: [UUID: CGFloat] = [:]
        var lastY: CGFloat = -100
        var lane = 0
        for pin in pins {
            let y = TimelineLayout.y(date: pin.date, range: range, hourHeight: hourHeight)
            if abs(y - lastY) < 26 {
                lane += 1
                extra[pin.id] = CGFloat(-lane) * 32
            } else {
                lane = 0
                lastY = y
            }
        }
        return extra
    }

    private func nowNeedle(_ now: Date, width: CGFloat, height: CGFloat) -> some View {
        let y = TimelineLayout.y(date: now, range: range, hourHeight: hourHeight)
        return HStack(spacing: 6) {
            Text("NOW")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(ShiftTheme.now)
            Circle()
                .fill(ShiftTheme.now)
                .frame(width: 8, height: 8)
            Rectangle()
                .fill(ShiftTheme.now)
                .frame(height: 2)
        }
        .offset(y: y - 6)
        .frame(width: width, height: height, alignment: .top)
        .allowsHitTesting(false)
    }
}

struct SlashOverlay: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let spacing: CGFloat = 7
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(path, with: .color(color.opacity(0.55)), lineWidth: 1.4)
                x += spacing
            }
        }
    }
}

/// Timeshifter-style 3-hour window around now.
struct NowTimeline: View {
    let plan: DayPlan
    let now: Date
    var next: ActionItem? = nil

    var body: some View {
        let start = now.addingTimeInterval(-40 * 60)
        let end = now.addingTimeInterval(2.6 * 3600)
        let window = start...end
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next 3 hours")
                        .font(.headline)
                    if let happening = TimelineLayout.happening(at: now, plan: plan) {
                        Text(happening)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ShiftTheme.accent)
                    } else if let next {
                        Text("Next · \(next.title) · \(ClockMath.format(next.date, timeZone: plan.timeZone))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Quiet stretch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(plan.clockCity)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            DayTimeline(plan: plan, now: now, hourHeight: 54, rangeOverride: window)
            TimelineLegend()
        }
        .padding(16)
        .background(ShiftTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ShiftTheme.stroke, lineWidth: 1)
        )
    }
}

/// Mini horizontal color bar for the plan list.
struct DayRibbon: View {
    let plan: DayPlan

    var body: some View {
        let range = TimelineLayout.range(for: plan)
        let span = max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                ForEach(TimelineLayout.bands(for: plan)) { band in
                    let x = geo.size.width * CGFloat(band.start.timeIntervalSince(range.lowerBound) / span)
                    let w = geo.size.width * CGFloat(band.end.timeIntervalSince(band.start) / span)
                    Capsule()
                        .fill(band.color.opacity(band.kind == .avoidLight ? 0.55 : 0.85))
                        .frame(width: max(4, w), height: 8)
                        .offset(x: max(0, x))
                }
            }
        }
        .frame(height: 8)
    }
}

enum ShiftIcons {
    static func symbol(_ kind: ActionKind) -> String {
        switch kind {
        case .seekLight: return "sun.max.fill"
        case .avoidLight: return "moon.zzz.fill"
        case .sleep: return "moon.fill"
        case .wake: return "sunrise.fill"
        case .caffeineCutoff, .caffeineOk: return "cup.and.saucer.fill"
        case .move: return "figure.walk"
        case .hydrate: return "drop.fill"
        case .note: return "star.fill"
        case .nap: return "zzz"
        case .melatonin: return "pills"
        }
    }

    static func color(_ kind: ActionKind) -> Color {
        switch kind {
        case .seekLight: return ShiftTheme.seekLight
        case .avoidLight: return ShiftTheme.avoidLight
        case .sleep: return ShiftTheme.sleep
        case .wake: return ShiftTheme.accent
        case .caffeineCutoff, .caffeineOk: return ShiftTheme.caffeine
        case .melatonin: return ShiftTheme.flight
        case .nap: return ShiftTheme.advance
        case .hydrate: return ShiftTheme.hold
        case .note, .move: return ShiftTheme.accent
        }
    }
}

struct TimelineLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legend(ShiftTheme.seekLight, "Light")
            legend(ShiftTheme.avoidLight, "Dim")
            legend(ShiftTheme.sleep, "Sleep")
            legend(ShiftTheme.caffeine, "Coffee")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 6)
            Text(label)
        }
    }
}
