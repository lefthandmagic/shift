import SwiftUI

@main
struct ShiftApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Color(red: 0.98, green: 0.62, blue: 0.22))
                .preferredColorScheme(.dark)
                .task {
                    await model.refreshNotifications()
                }
        }
    }
}
