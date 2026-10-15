// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

enum PackagedResourceCheck {
    static func run() throws {
        let bundle = AppResources.bundle
        let expected = Bundle.main.bundleURL.appending(path: "Contents/Resources/NotProtonApp_NotProtonApp.bundle")
        guard bundle.bundleURL.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath() else {
            throw StepFailure(step: "Check packaged resources", detail: "Resources resolved outside the packaged app: \(bundle.bundleURL.path)")
        }
        _ = try PayloadManifest.bundled()
        _ = try ValvePackageManifest.bundled()
        _ = try FreeNtdllPatch.bundled()
        _ = try InstallPayload.locate()
        for (name, ext) in [("compat_run", "sh"), ("detour2", "bin"), ("detour32", "bin"),
                            ("detour32-fex", "bin"), ("detour64-fex", "bin")] {
            guard let url = bundle.url(forResource: name, withExtension: ext),
                  !(try Data(contentsOf: url)).isEmpty else {
                throw StepFailure(step: "Check packaged resources", detail: "Missing resource: \(name).\(ext)")
            }
        }
    }
}
