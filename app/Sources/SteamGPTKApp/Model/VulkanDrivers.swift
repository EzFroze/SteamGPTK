// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

enum VulkanDrivers {
    private static let drivers = [("kosmickrisp_mesa_icd.json", "libvulkan_kosmickrisp.dylib"),
                                  ("MoltenVK_icd.json", "libMoltenVK.dylib")]

    static func isComplete(root: URL) -> Bool {
        drivers.allSatisfy { name, library in
            guard FileManager.default.fileExists(atPath: root.appending(path: "Frameworks/\(library)").path),
                  let bytes = try? Data(contentsOf: root.appending(path: "vulkan/icd.d/\(name)")),
                  let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let icd = json["ICD"] as? [String: Any],
                  icd["library_path"] is String else { return false }
            return true
        }
    }

    // The wrapper stores these manifests below Contents/Resources. Our runtime
    // moves vulkan/ beside Frameworks/, so its original relative paths are wrong.
    static func configure(root: URL) throws {
        let fm = FileManager.default
        var updates: [(URL, Data)] = []
        for (name, library) in drivers {
            let manifest = root.appending(path: "vulkan/icd.d/\(name)")
            let original = try Data(contentsOf: manifest)
            guard var json = try JSONSerialization.jsonObject(with: original) as? [String: Any],
                  var icd = json["ICD"] as? [String: Any],
                  fm.fileExists(atPath: root.appending(path: "Frameworks/\(library)").path) else {
                throw StepFailure(step: FreeRunnerInstaller.step, detail: "The Vulkan driver \(name) is incomplete. Repair the Wine runtime.")
            }
            let path = "../../Frameworks/\(library)"
            guard icd["library_path"] as? String != path else { continue }
            icd["library_path"] = path
            json["ICD"] = icd
            updates.append((manifest, try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])))
        }
        for (url, bytes) in updates {
            try atomicReplace(url, with: bytes, step: FreeRunnerInstaller.step)
        }
    }
}
