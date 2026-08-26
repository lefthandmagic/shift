import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.horizon.fill") }
                .tag(0)
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(1)
            TripsView()
                .tabItem { Label("Trips", systemImage: "airplane") }
                .tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(3)
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    tripChip
                    if let plan = model.today {
                        clocks(plan)
                        if let note = plan.constraintNote {
                            constraintBanner(note)
                        }
                        nextUp(plan)
                        sleepCard(plan)
                        lightCard(plan)
                        Text(plan.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No plan for today. Open Trips and generate a schedule.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Not medical advice. Light, sleep timing, and caffeine are the levers — skip anything that fights how you feel.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .background(ShiftTheme.bg.ignoresSafeArea())
            .navigationTitle("Shift")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var tripChip: some View {
        Button {
            model.selectedTab = 2
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.trip.name)
                        .font(.subheadline.weight(.semibold))
                    Text(model.trip.dateSpanLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Switch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShiftTheme.accent)
            }
            .padding(12)
            .background(ShiftTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func clocks(_ plan: DayPlan) -> some View {
        ShiftCard(tint: ShiftTheme.color(for: plan.kind)) {
            HStack {
                KindBadge(kind: plan.kind)
                Spacer()
                Text(plan.locationName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(ClockMath.formatDay(plan.dayStart, timeZone: plan.timeZone))
                .font(.title2.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                clockColumn(
                    label: "Local",
                    time: ClockMath.format(model.now, timeZone: plan.timeZone, template: "HH:mm"),
                    sub: ClockMath.formatWhen(model.now, timeZone: plan.timeZone, city: plan.clockCity)
                )
                clockColumn(
                    label: "Body clock",
                    time: ClockMath.format(plan.bodyClockTime(at: model.now), timeZone: plan.timeZone, template: "HH:mm"),
                    sub: plan.hoursOff < 0.4 ? "Matched" : String(format: "%.1fh off", plan.hoursOff)
                )
            }
        }
    }

    private func clockColumn(label: String, time: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(time)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(sub)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func constraintBanner(_ note: String) -> some View {
        ShiftCard(tint: ShiftTheme.accent) {
            Label(note, systemImage: "airplane.departure")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ShiftTheme.accent)
        }
    }

    private func nextUp(_ plan: DayPlan) -> some View {
        let action = model.nextAction
        return ShiftCard {
            Text("Next")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let action {
                Label(action.title, systemImage: symbol(action.kind))
                    .font(.title3.weight(.semibold))
                Text(ClockMath.formatWhen(action.date, timeZone: plan.timeZone, city: plan.clockCity))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ShiftTheme.accent)
                Text(action.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("You’re through today’s list. Sleep \(ClockMath.formatWhen(plan.targetSleep, timeZone: plan.timeZone, city: plan.clockCity)).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sleepCard(_ plan: DayPlan) -> some View {
        ShiftCard {
            Label("Sleep window", systemImage: "bed.double.fill")
                .font(.headline)
            Text(ClockMath.formatSleepWindow(sleep: plan.targetSleep, wake: plan.targetWake, timeZone: plan.timeZone, city: plan.clockCity))
                .font(.title3.monospacedDigit())
            Text("Caffeine off after \(ClockMath.formatWhen(plan.caffeineCutoff, timeZone: plan.timeZone, city: plan.clockCity))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func lightCard(_ plan: DayPlan) -> some View {
        ShiftCard {
            Label("Light", systemImage: "sun.max.fill")
                .font(.headline)
            if let seek = plan.lightSeek {
                Text("Get outdoor light  \(ClockMath.formatWhen(seek.start, timeZone: plan.timeZone))–\(ClockMath.format(seek.end, timeZone: plan.timeZone))")
            }
            if let avoid = plan.lightAvoid {
                Text("Keep light low \(ClockMath.formatWhen(avoid.start, timeZone: plan.timeZone))–\(ClockMath.format(avoid.end, timeZone: plan.timeZone))")
                    .foregroundStyle(.secondary)
            }
            if plan.lightSeek == nil && plan.lightAvoid == nil {
                Text("No special light window today.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(_ kind: ActionKind) -> String {
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
}

struct PlanView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List(model.plans) { plan in
                NavigationLink {
                    DayDetailView(plan: plan)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(ClockMath.formatDay(plan.dayStart, timeZone: plan.timeZone))
                                .font(.headline)
                            Spacer()
                            KindBadge(kind: plan.kind)
                        }
                        Text(plan.locationName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(plan.clockCity) time")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(ClockMath.formatSleepWindow(sleep: plan.targetSleep, wake: plan.targetWake, timeZone: plan.timeZone, city: plan.clockCity))
                            .font(.subheadline.monospacedDigit())
                        Text("Coffee until \(ClockMath.formatWhen(plan.caffeineCutoff, timeZone: plan.timeZone, city: plan.clockCity))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let seek = plan.lightSeek {
                            Text("Light \(ClockMath.formatWhen(seek.start, timeZone: plan.timeZone))–\(ClockMath.format(seek.end, timeZone: plan.timeZone))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let note = plan.constraintNote {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(ShiftTheme.accent)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(ShiftTheme.card)
            }
            .scrollContentBackground(.hidden)
            .background(ShiftTheme.bg.ignoresSafeArea())
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit itinerary") {
                        ItineraryView()
                    }
                }
            }
        }
    }
}

struct DayDetailView: View {
    let plan: DayPlan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ShiftCard(tint: ShiftTheme.color(for: plan.kind)) {
                    KindBadge(kind: plan.kind)
                    Text(ClockMath.formatDay(plan.dayStart, timeZone: plan.timeZone))
                        .font(.title.weight(.semibold))
                    Text(plan.locationName)
                        .foregroundStyle(.secondary)
                    Text(plan.headline)
                        .font(.headline)
                }
                if let note = plan.constraintNote {
                    ShiftCard(tint: ShiftTheme.accent) {
                        Label(note, systemImage: "airplane.departure")
                            .font(.subheadline.weight(.medium))
                    }
                }
                ShiftCard {
                    Text("Sleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ClockMath.formatSleepWindow(sleep: plan.targetSleep, wake: plan.targetWake, timeZone: plan.timeZone, city: plan.clockCity))
                        .font(.title3.monospacedDigit())
                    Text("Caffeine off \(ClockMath.formatWhen(plan.caffeineCutoff, timeZone: plan.timeZone, city: plan.clockCity))")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Timeline")
                        .font(.headline)
                        .padding(.bottom, 8)
                    ForEach(plan.actions) { action in
                        HStack(alignment: .top, spacing: 12) {
                            Text(ClockMath.formatWhen(action.date, timeZone: plan.timeZone))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ShiftTheme.accent)
                                .frame(width: 108, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.clockCity)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(action.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(action.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        Divider().overlay(ShiftTheme.stroke)
                    }
                }
                Text(plan.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(ShiftTheme.bg.ignoresSafeArea())
        .navigationTitle(plan.locationName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var bedDate: Date = SettingsView.date(hour: 23, minute: 0)
    @State private var wakeDate: Date = SettingsView.date(hour: 7, minute: 0)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Bedtime", selection: $bedDate, displayedComponents: .hourAndMinute)
                    DatePicker("Wake", selection: $wakeDate, displayedComponents: .hourAndMinute)
                    Stepper(
                        value: $model.schedule.airportLeadHours,
                        in: 2...4,
                        step: 0.5
                    ) {
                        Text("Airport lead \(model.schedule.airportLeadHours, specifier: "%.1f") h")
                    }
                    .onChange(of: model.schedule.airportLeadHours) { _, _ in
                        model.rebuild()
                    }
                } header: {
                    Text("Home sleep")
                } footer: {
                    Text("Airport lead is how early you must be awake before a flight. A 10:30 long-haul with 3 h lead means wake by 07:30 — not 11:00.")
                }
                Section {
                    Toggle("Use melatonin", isOn: $model.schedule.useMelatonin)
                        .onChange(of: model.schedule.useMelatonin) { _, _ in
                            model.rebuild()
                        }
                } header: {
                    Text("Melatonin")
                } footer: {
                    Text("Off by default. If on, Shift times a low dose on shift days. Optional. Not medical advice — ask a clinician.")
                }
                Section("Alerts") {
                    Toggle("Timed reminders", isOn: $model.notificationsOn)
                }
                Section("Active trip") {
                    NavigationLink {
                        ItineraryView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.trip.name)
                            Text(model.trip.routeSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                Section("About") {
                    Text("Shift times light, sleep, and caffeine around timezone jumps. It is a coach, not a doctor.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ShiftTheme.bg.ignoresSafeArea())
            .navigationTitle("Settings")
            .onAppear {
                bedDate = SettingsView.date(hour: model.schedule.bedHour, minute: model.schedule.bedMinute)
                wakeDate = SettingsView.date(hour: model.schedule.wakeHour, minute: model.schedule.wakeMinute)
            }
            .onChange(of: bedDate) { _, new in
                let c = Calendar.current.dateComponents([.hour, .minute], from: new)
                model.schedule.bedHour = c.hour ?? 23
                model.schedule.bedMinute = c.minute ?? 0
                model.rebuild()
            }
            .onChange(of: wakeDate) { _, new in
                let c = Calendar.current.dateComponents([.hour, .minute], from: new)
                model.schedule.wakeHour = c.hour ?? 7
                model.schedule.wakeMinute = c.minute ?? 0
                model.rebuild()
            }
            .onChange(of: model.notificationsOn) { _, _ in
                model.rebuild()
            }
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
}
