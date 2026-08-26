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
        .toolbarBackground(ShiftTheme.bg, for: .tabBar)
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
                        NowTimeline(plan: plan, now: model.now, next: model.nextAction)
                        NavigationLink {
                            DayDetailView(plan: plan)
                        } label: {
                            HStack {
                                Text("Full day timeline")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .background(ShiftTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
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

}

struct PlanView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List(model.plans) { plan in
                NavigationLink {
                    DayDetailView(plan: plan)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ClockMath.formatDay(plan.dayStart, timeZone: plan.timeZone))
                                    .font(.headline)
                                Text(plan.locationName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            KindBadge(kind: plan.kind)
                        }
                        DayRibbon(plan: plan)
                        HStack {
                            Text(ClockMath.format(plan.targetSleep, timeZone: plan.timeZone) + "–" + ClockMath.format(plan.targetWake, timeZone: plan.timeZone))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(plan.clockCity)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        if let note = plan.constraintNote {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(ShiftTheme.accent)
                        }
                    }
                    .padding(.vertical, 4)
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
    @EnvironmentObject private var model: AppModel
    let plan: DayPlan
    @State private var selected: Date

    init(plan: DayPlan) {
        self.plan = plan
        _selected = State(initialValue: plan.dayStart)
    }

    var body: some View {
        TabView(selection: $selected) {
            ForEach(model.plans) { item in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ClockMath.formatDay(item.dayStart, timeZone: item.timeZone))
                                    .font(.title.weight(.semibold))
                                Text("\(item.locationName) · \(item.clockCity) time")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            KindBadge(kind: item.kind)
                        }
                        if let note = item.constraintNote {
                            Text(note)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(ShiftTheme.accent)
                        }
                        TimelineLegend()
                        DayTimeline(plan: item, now: model.now, hourHeight: 36)
                            .padding(.bottom, 8)
                        Text(item.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .tag(item.dayStart)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .background(ShiftTheme.bg.ignoresSafeArea())
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selected = plan.dayStart }
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
