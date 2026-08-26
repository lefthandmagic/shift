import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var trips: [Trip]
    @Published var activeTripID: UUID
    @Published var trip: Trip
    @Published var schedule: SleepSchedule
    @Published var plans: [DayPlan]
    @Published var notificationsOn: Bool
    @Published var now: Date = Date()
    @Published var selectedTab: Int = 0

    private let defaults: UserDefaults
    private let notifications = NotificationScheduler()
    private var timer: Timer? = nil

    init(defaults: UserDefaults = .standard, trip: Trip? = nil) {
        self.defaults = defaults
        let resolvedTrip: Trip
        let resolvedID: UUID
        let resolvedTrips: [Trip]
        if let trip {
            resolvedTrips = [trip]
            resolvedID = trip.id
            resolvedTrip = trip
        } else {
            let lib = TripStore.loadLibrary(from: defaults)
            resolvedTrips = lib.trips
            resolvedID = lib.activeTripID
            resolvedTrip = lib.active
        }
        let resolvedSchedule = SleepSchedule(
            bedHour: defaults.object(forKey: "bedHour") as? Int ?? 23,
            bedMinute: defaults.object(forKey: "bedMinute") as? Int ?? 0,
            wakeHour: defaults.object(forKey: "wakeHour") as? Int ?? 7,
            wakeMinute: defaults.object(forKey: "wakeMinute") as? Int ?? 0,
            airportLeadHours: defaults.object(forKey: "airportLeadHours") as? Double ?? 3.0
        )
        self.trips = resolvedTrips
        self.activeTripID = resolvedID
        self.trip = resolvedTrip
        self.schedule = resolvedSchedule
        self.notificationsOn = defaults.object(forKey: "notificationsOn") as? Bool ?? true
        self.plans = PlanEngine.build(trip: resolvedTrip, schedule: resolvedSchedule, now: Date())
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
        writeActiveBack()
        plans = PlanEngine.build(trip: trip, schedule: schedule, now: now)
        persist()
        Task { await refreshNotifications() }
    }

    /// Rebuild the active trip’s schedule and jump to Plan.
    func generatePlan() {
        rebuild()
        selectedTab = 1
    }

    func selectTrip(id: UUID) {
        writeActiveBack()
        guard let next = trips.first(where: { $0.id == id }) else { return }
        activeTripID = id
        trip = next
        rebuild()
    }

    func addTrip(_ newTrip: Trip) {
        writeActiveBack()
        trips.append(newTrip)
        activeTripID = newTrip.id
        trip = newTrip
        rebuild()
    }

    func duplicateActive() {
        let copy = trip.duplicated()
        addTrip(copy)
    }

    func deleteTrip(id: UUID) {
        guard trips.count > 1 else { return }
        trips.removeAll { $0.id == id }
        if activeTripID == id {
            trip = trips[0]
            activeTripID = trip.id
        }
        rebuild()
    }

    func refreshNotifications() async {
        guard notificationsOn else {
            NotificationScheduler.center.removeAllPendingNotificationRequests()
            return
        }
        await notifications.requestAndSchedule(plans: plans, now: now)
    }

    func persist() {
        writeActiveBack()
        defaults.set(schedule.bedHour, forKey: "bedHour")
        defaults.set(schedule.bedMinute, forKey: "bedMinute")
        defaults.set(schedule.wakeHour, forKey: "wakeHour")
        defaults.set(schedule.wakeMinute, forKey: "wakeMinute")
        defaults.set(schedule.airportLeadHours, forKey: "airportLeadHours")
        defaults.set(notificationsOn, forKey: "notificationsOn")
        TripStore.saveLibrary(TripLibrary(trips: trips, activeTripID: activeTripID), to: defaults)
    }

    func applyTrip(_ trip: Trip) {
        self.trip = trip
        rebuild()
    }

    func resetTrip() {
        let replacement = Trips.usAugust2026()
        var next = replacement
        next.id = trip.id
        trip = next
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

    private func writeActiveBack() {
        if let i = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[i] = trip
            activeTripID = trip.id
        } else {
            trips.append(trip)
            activeTripID = trip.id
        }
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
