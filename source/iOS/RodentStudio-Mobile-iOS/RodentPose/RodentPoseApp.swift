import SwiftUI

@main
struct RodentPoseApp: App {
    @StateObject private var app = AppModel()
    @AppStorage(L10n.preferenceKey) private var uiLanguage = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                // SwiftUI must rebuild screens that call L10n.tr() directly.
                .id(uiLanguage)
                .environment(\.locale, Locale(identifier: uiLanguage == "system"
                    ? (Locale.preferredLanguages.first ?? "en") : uiLanguage))
                // Own the sheet above the language-refresh subtree, so the
                // language picker stays open while the underlying UI updates.
                .sheet(isPresented: $app.showSettings) {
                    // Sheet content must receive the dependencies on its own.
                    // Injecting them only into RootView (below .sheet) does
                    // not reliably propagate them into a separately hosted
                    // presentation. Without PoseEngine this crashes as soon
                    // as SettingsView reads @EnvironmentObject.
                    SettingsView()
                        .environmentObject(app)
                        .environmentObject(app.store)
                        .environmentObject(app.engine)
                }
                // Inject at the outside of the presentation modifier too,
                // so the root screens and their nested presentations all
                // inherit the same shared instances.
                .environmentObject(app)
                .environmentObject(app.store)
                .environmentObject(app.engine)
        }
    }
}
