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
            Group {
                if let plan = model.today {
                    NowTimeline(plan: plan, allPlans: model.plans, now: model.now)
                        .padding(12)
                } else {
                    Text("No plan yet. Open Trips and generate a schedule.")
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ShiftTheme.bg.ignoresSafeArea())
            .navigationTitle("Shift")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PlanView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(model.relevantPlans) { plan in
                    NavigationLink {
                        DayDetailView(plan: plan)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(ClockMath.formatNight(plan.targetSleep, timeZone: .current))
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
                                ClockMath.format(plan.targetSleep, timeZone: .current)
                                    + "–"
                                    + ClockMath.format(plan.targetWake, timeZone: .current)
                            )
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .id(plan.id)
                    .listRowBackground(
                        plan.id == model.focusedPlan?.id
                            ? ShiftTheme.accent.opacity(0.14)
                            : ShiftTheme.card
                    )
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
                .onAppear {
                    scrollPlanToNow(proxy)
                }
            }
        }
    }

    private func scrollPlanToNow(_ proxy: ScrollViewProxy) {
        let id = model.focusedPlan?.id
        DispatchQueue.main.async {
            if let id {
                proxy.scrollTo(id, anchor: .top)
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
            ForEach(model.relevantPlans) { item in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ClockMath.formatNight(item.targetSleep, timeZone: .current))
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
                            DayTimeline(plan: item, now: model.now, hourHeight: 36, timeZone: .current)
                                .padding(.bottom, 8)
                        }
                        .padding(16)
                    }
                    .onAppear {
                        let range = TimelineLayout.range(for: item)
                        guard model.now >= range.lowerBound && model.now <= range.upperBound else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo("now", anchor: .center)
                        }
                    }
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
