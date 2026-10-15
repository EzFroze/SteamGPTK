// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

enum FreeSteamSignature {
    // This module uses the schema-3, 17-anchor profile. A newer CrossOver/FEX
    // profile is not interchangeable just because its Steam build number is higher.
    static func installIfNeeded(
        app: URL = SupportPaths.Steam.app, signatures: URL = SupportPaths.signatures,
        sign: (URL) throws -> Void = { try SteamInstaller.adHocSign($0) }
    ) throws {
        let plist = SupportPaths.Steam.infoPlist(inBundle: app)
        guard var info = SteamBundle.readInfoPlist(at: plist) else {
            throw StepFailure(step: "Select Steam signatures", detail: "Steam Info.plist is unreadable.")
        }
        var env = info[SteamBundle.environmentKey] as? [String: String] ?? [:]
        if let chosen = env["NOTPROTON_SIG"], valid(URL(filePath: chosen)) { return }
        let profile = signatures.appending(path: "1788400362.json")
        guard valid(profile) else {
            throw StepFailure(step: "Select Steam signatures", detail: "The Wine / GPTK signature profile is missing or incompatible.")
        }
        env["NOTPROTON_SIG"] = profile.path(percentEncoded: false)
        info[SteamBundle.environmentKey] = env
        let original = try Data(contentsOf: plist)
        do {
            let bytes = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try atomicReplace(plist, with: bytes, step: "Select Steam signatures")
            try sign(app)
            SteamBundle.register(app)
        } catch {
            try? atomicReplace(plist, with: original, step: "Restore Steam configuration")
            try? sign(app)
            throw error
        }
    }

    private static func valid(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["schema_version"] as? Int == 3,
              (json["signatures"] as? [Any])?.count == 17 else { return false }
        return true
    }
}
