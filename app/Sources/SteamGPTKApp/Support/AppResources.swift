// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

enum AppResources {
    static let bundleName = "SteamGPTKApp_SteamGPTKApp.bundle"

    // Native SwiftPM searches beside the app and then its absolute build path.
    // Packaged apps must use their own resources on every supported build system.
    static let bundle: Bundle = packagedBundle(in: Bundle.main.resourceURL) ?? .module

    static func packagedBundle(in directory: URL?) -> Bundle? {
        guard let directory else { return nil }
        return Bundle(url: directory.appending(path: bundleName))
    }
}
