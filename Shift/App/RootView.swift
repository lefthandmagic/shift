import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.horizon.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct TodayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let plan = model.today {
                        clocks(plan)
                        nextUp(plan)
                        sleepCard(plan)
                        lightCard(plan)
                        Text(plan.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No plan for today.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Not medical advice. Light, sleep timing, and caffeine are the levers — skip anything that fights how you feel.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .background(Color(red: 0.05, green: 0.07, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Shift")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func clocks(_ plan: DayPlan) -> some View {
        Card {
            Text(plan.headline)
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                clockColumn(
                    label: "Local · \(plan.locationName)",
                    time: ClockMath.format(model.now, timeZone: plan.timeZone, template: "HH:mm"),
                    sub: ClockMath.formatDay(model.now, timeZone: plan.timeZone)
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

    private func nextUp(_ plan: DayPlan) -> some View {
        let action = model.nextAction
        return Card {
            Text("Next")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let action {
                Label(action.title, systemImage: symbol(action.kind))
                    .font(.title3.weight(.semibold))
                Text("\(ClockMath.format(action.date, timeZone: plan.timeZone)) · \(action.detail)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("You’re through today’s list. Sleep target \(ClockMath.format(plan.targetSleep, timeZone: plan.timeZone)).")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sleepCard(_ plan: DayPlan) -> some View {
        Card {
            Label("Sleep window", systemImage: "bed.double.fill")
                .font(.headline)
            Text("\(ClockMath.format(plan.targetSleep, timeZone: plan.timeZone)) → \(ClockMath.format(plan.targetWake, timeZone: plan.timeZone))")
                .font(.title3.monospacedDigit())
            Text("Caffeine off after \(ClockMath.format(plan.caffeineCutoff, timeZone: plan.timeZone))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func lightCard(_ plan: DayPlan) -> some View {
        Card {
            Label("Light", systemImage: "sun.max.fill")
                .font(.headline)
            if let seek = plan.lightSeek {
                Text("Seek  \(ClockMath.format(seek.start, timeZone: plan.timeZone))–\(ClockMath.format(seek.end, timeZone: plan.timeZone))")
            }
            if let avoid = plan.lightAvoid {
                Text("Avoid \(ClockMath.format(avoid.start, timeZone: plan.timeZone))–\(ClockMath.format(avoid.end, timeZone: plan.timeZone))")
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
        case .avoidLight: return "sunglasses"
        case .sleep: return "moon.fill"
        case .wake: return "sunrise.fill"
        case .caffeineCutoff: return "cup.and.saucer.fill"
        case .move: return "figure.walk"
        case .hydrate: return "drop.fill"
        case .note: return "star.fill"
        }
    }
}

struct PlanView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List(model.plans) { plan in
                VStack(alignment: .leading, spacing: 6) {
                    Text(ClockMath.formatDay(plan.dayStart, timeZone: plan.timeZone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(plan.headline)
                        .font(.headline)
                    Text("Sleep \(ClockMath.format(plan.targetSleep, timeZone: plan.timeZone)) · up \(ClockMath.format(plan.targetWake, timeZone: plan.timeZone))")
                        .font(.subheadline)
                        .monospacedDigit()
                    Text(plan.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.white.opacity(0.05))
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.05, green: 0.07, blue: 0.12).ignoresSafeArea())
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("Edit trip") {
                        ItineraryView()
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var bedDate: Date = SettingsView.date(hour: 23, minute: 0)
    @State private var wakeDate: Date = SettingsView.date(hour: 7, minute: 0)

    var body: some View {
        NavigationStack {
            Form {
                Section("Home sleep (Amsterdam)") {
                    DatePicker("Bedtime", selection: $bedDate, displayedComponents: .hourAndMinute)
                    DatePicker("Wake", selection: $wakeDate, displayedComponents: .hourAndMinute)
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
                            Text(model.trip.routeSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                Section("About") {
                    Text("Shift times your light, sleep, and caffeine around timezone jumps. It is a coach, not a doctor.")
                    Text("Melatonin is omitted on purpose — ask a clinician if you use it.")
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.05, green: 0.07, blue: 0.12).ignoresSafeArea())
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
