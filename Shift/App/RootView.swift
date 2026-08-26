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
                VStack(alignment: .leading, spacing: 16) {
                    if let plan = model.today {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ClockMath.formatDay(plan.dayStart, timeZone: plan.timeZone))
                                .font(.title2.weight(.semibold))
                            Spacer()
                            Text(plan.clockCity)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        NowTimeline(plan: plan, allPlans: model.plans, now: model.now)
                    } else {
                        Text("No plan yet. Open Trips and generate a schedule.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .background(ShiftTheme.bg.ignoresSafeArea())
            .navigationTitle("Shift")
            .navigationBarTitleDisplayMode(.large)
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
                            Text(ClockMath.formatDay(plan.dayStart, timeZone: plan.timeZone))
                                .font(.headline)
                            Spacer()
                            HStack(spacing: 6) {
                                if plan.inFlight != nil {
                                    Image(systemName: "airplane")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(ShiftTheme.flight)
                                }
                                Text(plan.clockCity)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        DayRibbon(plan: plan)
                        Text(
                            ClockMath.format(plan.targetSleep, timeZone: plan.timeZone)
                                + "–"
                                + ClockMath.format(plan.targetWake, timeZone: plan.timeZone)
                        )
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
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
                    NavigationLink("Edit") {
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
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ClockMath.formatDay(item.dayStart, timeZone: item.timeZone))
                                    .font(.title.weight(.semibold))
                                Text(item.clockCity)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.inFlight != nil {
                                Label("Flight", systemImage: "airplane")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ShiftTheme.flight)
                            }
                        }
                        TimelineLegend()
                        DayTimeline(plan: item, now: model.now, hourHeight: 36)
                            .padding(.bottom, 8)
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
                    Text("How early you need to be up before a long-haul. 3 h before a 10:30 flight means wake by 07:30.")
                }
                Section {
                    Toggle("Use melatonin", isOn: $model.schedule.useMelatonin)
                        .onChange(of: model.schedule.useMelatonin) { _, _ in
                            model.rebuild()
                        }
                } header: {
                    Text("Melatonin")
                } footer: {
                    Text("Off by default. Optional low dose, timed on shift days. Ask a clinician.")
                }
                Section("Alerts") {
                    Toggle("Timed reminders", isOn: $model.notificationsOn)
                }
                Section("Trip") {
                    NavigationLink {
                        ItineraryView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.trip.name)
                            Text(model.trip.compactRoute)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(model.trip.dateSpanLabel)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
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
