import SwiftUI

@main
struct EventCountdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    var body: some Scene {
        let _ = { appDelegate.appModel = appModel }()

        MenuBarExtra {
            EventListView()
                .environment(appModel)
        } label: {
            MenuBarLabelView(
                event: appModel.menuBarEvent,
                resolution: appModel.menuBarEvent.map { appModel.emojiResolution(for: $0) } ?? .appIcon,
                needsAcknowledgment: appModel.hasPendingAcknowledgment
            )
            .environment(appModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appModel)
        }
    }
}
