import Foundation
import UserNotifications

@MainActor
final class NotificationScheduler {
    static let center = UNUserNotificationCenter.current()

    func requestAndSchedule(plans: [DayPlan], now: Date) async {
        let granted = await request()
        guard granted else { return }
        await schedule(plans: plans, now: now)
    }

    func request() async -> Bool {
        do {
            return try await Self.center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func schedule(plans: [DayPlan], now: Date) async {
        Self.center.removeAllPendingNotificationRequests()
        let horizon = now.addingTimeInterval(3 * 86_400)
        let kinds: Set<ActionKind> = [.seekLight, .avoidLight, .caffeineCutoff, .caffeineOk, .sleep, .wake, .nap, .melatonin]
        var count = 0
        for plan in plans {
            for action in plan.actions where kinds.contains(action.kind) {
                guard action.date > now.addingTimeInterval(5 * 60), action.date < horizon else { continue }
                guard count < 48 else { return }
                let content = UNMutableNotificationContent()
                content.title = action.title
                content.body = action.detail
                content.sound = .default
                var comps = Calendar.current.dateComponents(in: plan.timeZone, from: action.date)
                comps.second = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(
                    calendar: Calendar(identifier: .gregorian),
                    timeZone: plan.timeZone,
                    year: comps.year,
                    month: comps.month,
                    day: comps.day,
                    hour: comps.hour,
                    minute: comps.minute
                ), repeats: false)
                let id = "shift.\(Int(action.date.timeIntervalSince1970)).\(action.kind.rawValue)"
                let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await Self.center.add(req)
                count += 1
            }
        }
    }
}
