import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var trip: Trip
    @Published var schedule: SleepSchedule
    @Published var plans: [DayPlan]
    @Published var notificationsOn: Bool
    @Published var now: Date = Date()

    private let defaults: UserDefaults
    private let notifications = NotificationScheduler()
    private var timer: Timer?

    init(defaults: UserDefaults = .standard, trip: Trip? = nil) {
        self.defaults = defaults
        self.trip = trip ?? TripStore.load(from: defaults) ?? Trips.usAugust2026()
        self.schedule = SleepSchedule(
            bedHour: defaults.object(forKey: "bedHour") as? Int ?? 23,
            bedMinute: defaults.object(forKey: "bedMinute") as? Int ?? 0,
            wakeHour: defaults.object(forKey: "wakeHour") as? Int ?? 7,
            wakeMinute: defaults.object(forKey: "wakeMinute") as? Int ?? 0
        )
        self.notificationsOn = defaults.object(forKey: "notificationsOn") as? Bool ?? true
        self.plans = PlanEngine.build(trip: self.trip, schedule: self.schedule, now: Date())
        startClock()
    }

    var today: DayPlan? {
        PlanEngine.plan(for: now, in: plans)
    }

    var nextAction: ActionItem? {
        guard let today else { return nil }
        return PlanEngine.currentAction(at: now, plan: today)
    }

    func rebuild() {
        plans = PlanEngine.build(trip: trip, schedule: schedule, now: now)
        persist()
        Task { await refreshNotifications() }
    }

    func refreshNotifications() async {
        guard notificationsOn else {
            NotificationScheduler.center.removeAllPendingNotificationRequests()
            return
        }
        await notifications.requestAndSchedule(plans: plans, now: now)
    }

    func persist() {
        defaults.set(schedule.bedHour, forKey: "bedHour")
        defaults.set(schedule.bedMinute, forKey: "bedMinute")
        defaults.set(schedule.wakeHour, forKey: "wakeHour")
        defaults.set(schedule.wakeMinute, forKey: "wakeMinute")
        defaults.set(notificationsOn, forKey: "notificationsOn")
        TripStore.save(trip, to: defaults)
    }

    func applyTrip(_ trip: Trip) {
        self.trip = trip
        rebuild()
    }

    func resetTrip() {
        trip = Trips.usAugust2026()
        rebuild()
    }

    func replaceSegment(_ segment: TripSegment) {
        trip.replaceSegment(segment)
        rebuild()
    }

    func addSegment() {
        trip.addSegment()
        rebuild()
    }

    func deleteSegment(id: UUID) {
        trip.deleteSegment(id: id)
        rebuild()
    }

    func replaceEvent(_ event: TripEvent) {
        trip.replaceEvent(event)
        rebuild()
    }

    func addEvent() {
        trip.addEvent()
        rebuild()
    }

    func deleteEvent(id: UUID) {
        trip.deleteEvent(id: id)
        rebuild()
    }

    private func startClock() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
            }
        }
        timer?.tolerance = 10
    }
}
