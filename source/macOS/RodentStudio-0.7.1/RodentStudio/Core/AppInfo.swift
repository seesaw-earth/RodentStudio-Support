import Foundation

/// Name and version written into exports and window titles.
/// The bundle identifier and the workspace folder ("RodentDesktopNative" in Application Support) are
/// unchanged from Rodent Desktop, so existing workspaces and tracking runs keep working.
enum AppInfo {
    static let name = "RodentStudio"

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.7.0"
    }

    /// "RodentStudio 0.6.1"
    static var label: String { name + " " + version }
}
