// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

enum LegacyInstallation {
    static let oldName = "notproton"
    static let oldNamespace = "NOTPROTON_"
    static let oldBackupSuffix = "notproton-orig"

    static func support(in applicationSupport: URL) -> URL {
        let current = applicationSupport.appending(path: "steamgptk")
        let old = applicationSupport.appending(path: oldName)
        return !FileManager.default.fileExists(atPath: current.path)
            && FileManager.default.fileExists(atPath: old.path) ? old : current
    }

    // Aliases preserve embedded paths, existing launch options, Wine drive links
    // and original backups. No runtime or prefix is copied, merged or removed.
    static func prepare(home: URL, checkCanWrite: () throws -> Void) throws {
        try checkCanWrite()
        let base = home.appending(path: "Library/Application Support")
        try alias(base.appending(path: oldName), as: base.appending(path: "steamgptk"), checkCanWrite: checkCanWrite)
        let caches = home.appending(path: "Library/Caches")
        for (old, current) in [("notproton-free/downloads", "steamgptk-free/downloads"),
                                ("notproton/valve-packages", "steamgptk/valve-packages")] {
            // Cache conflicts can simply use the new cache; user data cannot.
            let destination = caches.appending(path: current)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try alias(caches.appending(path: old), as: destination, checkCanWrite: checkCanWrite)
            }
        }
    }

    static func migrate(home: URL, checkCanWrite: () throws -> Void) throws {
        try prepare(home: home, checkCanWrite: checkCanWrite)
        let fm = FileManager.default
        let steam = home.appending(path: "Library/Application Support/Steam")
        var configs = [steam.appending(path: "config/config.vdf")]
        let users = (try? fm.contentsOfDirectory(at: steam.appending(path: "userdata"), includingPropertiesForKeys: nil)) ?? []
        for user in users {
            configs += [user.appending(path: "config/localconfig.vdf"), user.appending(path: "7/remote/sharedconfig.vdf")]
        }
        var changes: [(URL, Data)] = []
        for file in configs where fm.fileExists(atPath: file.path) {
            let original = try String(contentsOf: file, encoding: .utf8)
            let updated = try mappings(in: original)
            if updated != original { changes.append((file, Data(updated.utf8))) }
        }
        if !changes.isEmpty {
            let declaration = steam.appending(path: "compatibilitytools.d/steamgptk-proton/compatibilitytool.vdf")
            guard (try? String(contentsOf: declaration, encoding: .utf8))?.contains("\"steamgptk-proton\"") == true else {
                throw StepFailure(step: "Upgrade SteamGPTK", detail: "Install the new compatibility tool before migrating Steam settings.")
            }
        }
        for (file, bytes) in changes {
            try checkCanWrite()
            let backup = file.appendingPathExtension("before-steamgptk-0.2.0")
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: file, to: backup) }
            try atomicReplace(file, with: bytes, step: "Upgrade SteamGPTK")
        }
        let oldTool = steam.appending(path: "compatibilitytools.d/\(oldName)")
        let newTool = steam.appending(path: "compatibilitytools.d/steamgptk-proton/run")
        if fm.fileExists(atPath: oldTool.path), fm.isExecutableFile(atPath: newTool.path),
           (try? String(contentsOf: oldTool.appending(path: "compatibilitytool.vdf"), encoding: .utf8))?.contains("\"\(oldName)\"") == true {
            try checkCanWrite()
            let backup = support(in: steam.deletingLastPathComponent()).appending(path: "backups/compatibility-tool-\(UUID().uuidString)")
            try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: oldTool, to: backup)
        }
    }

    static func isPreviousInsert(_ path: String, replacing dylib: URL) -> Bool {
        path == dylib.deletingLastPathComponent().appending(path: "\(oldName).dylib").path
    }

    static func environment(_ original: [String: Any]) -> [String: Any] {
        var result = original
        for (key, value) in original where key.hasPrefix(oldNamespace) {
            let renamed = "STEAMGPTK_" + key.dropFirst(oldNamespace.count)
            if result[renamed] == nil { result[renamed] = value }
            result.removeValue(forKey: key)
        }
        return result
    }

    static func prefixSetting(_ name: String, in directory: URL) -> URL {
        let current = directory.appending(path: "steamgptk-\(name)")
        return FileManager.default.fileExists(atPath: current.path) ? current : directory.appending(path: "\(oldName)-\(name)")
    }

    static func removalDirectories(home: URL) -> [URL] {
        let base = home.appending(path: "Library/Application Support")
        let current = base.appending(path: "steamgptk")
        let old = base.appending(path: oldName)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil,
           current.resolvingSymlinksInPath() == old.resolvingSymlinksInPath() {
            return [current, old]
        }
        return [support(in: base)]
    }

    private static func alias(_ old: URL, as current: URL, checkCanWrite: () throws -> Void) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path) else { return }
        if fm.fileExists(atPath: current.path) {
            guard old.resolvingSymlinksInPath() == current.resolvingSymlinksInPath() else {
                throw StepFailure(step: "Upgrade SteamGPTK", detail: "Both old and new support directories contain data. They were preserved; choose one installation before upgrading.")
            }
            return
        }
        // A dangling or unrelated symlink must not be silently replaced.
        if (try? fm.destinationOfSymbolicLink(atPath: current.path)) != nil {
            throw StepFailure(step: "Upgrade SteamGPTK", detail: "The new support path is an existing symlink. It was preserved.")
        }
        try checkCanWrite()
        try fm.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: current, withDestinationURL: old)
    }

    private static func mappings(in text: String) throws -> String {
        guard text.contains("\"\(oldName)") else { return text }
        let regex = try NSRegularExpression(pattern: #"//[^\r\n]*|"(?:\\.|[^"\\])*"|[{}]"#)
        let source = text as NSString
        var stack: [String] = []
        var key: String?
        var replacements: [(NSRange, String)] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let token = source.substring(with: match.range)
            if token.hasPrefix("//") { continue }
            if token == "{" {
                guard let next = key else { throw invalidConfig() }
                stack.append(next.lowercased()); key = nil
            } else if token == "}" {
                guard key == nil, !stack.isEmpty else { throw invalidConfig() }
                stack.removeLast()
            } else {
                let value = String(token.dropFirst().dropLast())
                if let field = key {
                    if field.lowercased() == "name", stack.contains("compattoolmapping") {
                        let renamed = value == oldName ? "steamgptk-proton" : value == "\(oldName).none" ? "steamgptk.none" : nil
                        if let renamed { replacements.append((match.range, "\"\(renamed)\"")) }
                    }
                    key = nil
                } else { key = value }
            }
        }
        guard stack.isEmpty, key == nil else { throw invalidConfig() }
        let updated = NSMutableString(string: text)
        for (range, value) in replacements.reversed() { updated.replaceCharacters(in: range, with: value) }
        return updated as String
    }

    private static func invalidConfig() -> StepFailure {
        StepFailure(step: "Upgrade SteamGPTK", detail: "Steam configuration could not be parsed safely. The file was preserved.")
    }
}
