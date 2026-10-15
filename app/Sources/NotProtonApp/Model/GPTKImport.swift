// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

enum GPTKImport {
    static let downloadURL = URL(string: "https://developer.apple.com/download/all/?q=game%20porting%20toolkit")!
    static let relativePath = "Frameworks/renderer/d3dmetal"

    static func version(in library: URL) -> String? {
        let fm = FileManager.default
        let framework = "external/D3DMetal.framework/Versions/A"
        let required = ["\(framework)/D3DMetal", "external/libd3dshared.dylib",
                        "wine/x86_64-windows/d3d11.dll", "wine/x86_64-windows/d3d12.dll",
                        "wine/x86_64-windows/dxgi.dll", "wine/x86_64-windows/d3d12core.dll",
                        "wine/x86_64-unix/d3d11.so", "wine/x86_64-unix/d3d12.so",
                        "wine/x86_64-unix/d3d12core.so", "wine/x86_64-unix/dxgi.so"]
        let base = library.resolvingSymlinksInPath().path + "/"
        guard required.allSatisfy({
            let file = library.appending(path: $0)
            let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            return file.resolvingSymlinksInPath().path.hasPrefix(base)
                && size > 0
        }), let data = try? Data(contentsOf: library.appending(path: "\(framework)/Resources/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.apple.D3DMetal",
              let version = info["CFBundleShortVersionString"] as? String,
              version.hasPrefix("4.")
        else { return nil }
        return version
    }

    @discardableResult
    static func installLibrary(from library: URL, runner: URL,
                               checkCanWrite: () throws -> Void = {}) throws -> URL? {
        guard version(in: library) != nil else {
            throw StepFailure(step: "Import GPTK", detail: "Select a complete Game Porting Toolkit 4 evaluation environment from Apple.")
        }
        let fm = FileManager.default
        let target = runner.appending(path: relativePath)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A replacement is prepared in full before moving the live renderer.
        let stage = target.deletingLastPathComponent().appending(path: ".gptk-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        try fm.copyItem(at: library, to: stage)
        guard version(in: stage) != nil else {
            throw StepFailure(step: "Import GPTK", detail: "The copied GPTK files are incomplete; the installed version was preserved.")
        }
        try checkCanWrite()
        var backup: URL?
        if fm.fileExists(atPath: target.path) {
            let kept = target.deletingLastPathComponent().appending(path: "d3dmetal.backup-\(UUID().uuidString)")
            try fm.moveItem(at: target, to: kept)
            backup = kept
        }
        do { try fm.moveItem(at: stage, to: target) }
        catch {
            if let backup { try? fm.moveItem(at: backup, to: target) }
            throw error
        }
        return backup
    }

    static func importDMG(_ dmg: URL, runner: URL,
                          checkCanWrite: () throws -> Void = {}) throws {
        guard dmg.pathExtension.lowercased() == "dmg",
              FileManager.default.fileExists(atPath: dmg.path) else {
            throw StepFailure(step: "Import GPTK", detail: "Choose the GPTK DMG downloaded from Apple.")
        }
        let outer = try mount(dmg)
        defer { unmount(outer) }
        var mounts = [outer]
        if let nested = try FileManager.default.contentsOfDirectory(at: outer.root, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension.lowercased() == "dmg"
                && $0.lastPathComponent.localizedCaseInsensitiveContains("Evaluation environment") }) {
            mounts.append(try mount(nested))
        }
        defer { for m in mounts.dropFirst().reversed() { unmount(m) } }
        for mounted in mounts.reversed() {
            let library = mounted.root.appending(path: "redist/lib")
            if version(in: library) != nil {
                try installLibrary(from: library, runner: runner, checkCanWrite: checkCanWrite)
                return
            }
        }
        throw StepFailure(step: "Import GPTK", detail: "This DMG does not contain a complete GPTK 4 evaluation environment.")
    }

    private struct MountedImage {
        let root: URL
        let owned: Bool
    }

    private static func mount(_ dmg: URL) throws -> MountedImage {
        // Finder may already have opened either image. Reuse that mount without
        // detaching a volume that belongs to the user when the import finishes.
        if let output = try? Shell.check("/usr/bin/hdiutil", ["info", "-plist"]),
           let info = try? PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any],
           let images = info["images"] as? [[String: Any]] {
            for image in images {
                guard let path = image["image-path"] as? String,
                      URL(filePath: path).resolvingSymlinksInPath() == dmg.resolvingSymlinksInPath(),
                      let entities = image["system-entities"] as? [[String: Any]],
                      let mounted = entities.compactMap({ $0["mount-point"] as? String }).first else { continue }
                return MountedImage(root: URL(filePath: mounted), owned: false)
            }
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: "notproton-gptk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            _ = try Shell.check("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-quiet", "-mountpoint", dir.path, dmg.path])
            return MountedImage(root: dir, owned: true)
        } catch { try? FileManager.default.removeItem(at: dir); throw error }
    }

    private static func unmount(_ image: MountedImage) {
        guard image.owned else { return }
        if (try? Shell.run("/usr/bin/hdiutil", ["detach", "-quiet", image.root.path]).succeeded) == true {
            try? FileManager.default.removeItem(at: image.root)
        }
    }
}
