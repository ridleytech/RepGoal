//
//  App.swift (v13)
import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppStyle.applyNavigationTitleSizing()
        BackgroundScheduler.register()
        requestNotificationAuthorization()
        BackgroundScheduler.scheduleNextCheck()
        do {
            let config = ModelConfiguration("RepGoal")
            let container = try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
            let context = ModelContext(container)
            LocalReminderScheduler.rescheduleAll(using: context)
        } catch { print("⚠️ initial reschedule error: \(error)") }
        return true
    }
    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error { print("Notification auth error: \(error)") }
            print("Notifications granted: \(granted)")
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.badge, .sound, .banner, .list])
    }
}

@main
struct RepGoalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let container: ModelContainer = {
        do {
            let config = ModelConfiguration("RepGoal")
            return try ModelContainer(for: Exercise.self, RepEntry.self, AppSettings.self, MacroGoal.self, configurations: config)
        } catch { fatalError("💥 Failed to create ModelContainer: \(error)") }
    }()
    var body: some Scene {
        WindowGroup { ContentView() }.modelContainer(container)
    }
}
