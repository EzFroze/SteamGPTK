// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation
import Testing
@testable import SteamGPTKApp

@Suite("Upgrade from the original installation")
struct LegacyInstallationTests {
    @Test("The generated launcher exports the protocol required by the pinned bridge")
    func retainsPinnedBridgeProtocol() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "steamgptk-launcher-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
        let start = try #require(source.range(of: "cat > \"$loader_macos/launcher\" <<LAUNCHER\n"))
        let remainder = source[start.upperBound...]
        let end = try #require(remainder.range(of: "\nLAUNCHER"))
        let template = String(remainder[..<end.lowerBound])
        let bin = root.appending(path: "Contents/MacOS")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let shim = root.appending(path: "Library/Application Support/steamgptk/overlay-shim.dylib")
        try fm.createDirectory(at: shim.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("shim fixture".utf8).write(to: shim)
        let wine = root.appending(path: "wine")
        try Data("#!/bin/sh\nprintf '%s|%s' \"$STEAMGPTK_OVERLAY_SHIM\" \"$NOTPROTON_OVERLAY_SHIM\"\n".utf8).write(to: wine)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = root.path
        environment["PROBE_ROOT"] = root.path
        environment["WINELOADER"] = wine.path
        environment["DYLD_FALLBACK_LIBRARY_PATH"] = "/usr/lib"
        let command = "loader_macos=\"$PROBE_ROOT/Contents/MacOS\"\nloader_root=\"$PROBE_ROOT\"\ncat > \"$loader_macos/launcher\" <<LAUNCHER\n"
            + template + "\nLAUNCHER\n/bin/sh \"$loader_macos/launcher\"\n"
        _ = try Shell.check("/bin/sh", ["-c", command], environment: environment)
        let exported = try String(contentsOf: root.appending(path: "steamgptk-wine.log"), encoding: .utf8)
        #expect(exported == shim.path + "|" + shim.path)
    }

    @Test("Removing an upgraded installation removes its runtime and preserves library saves")
    func removesMigratedRuntime() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let base = home.appending(path: "Library/Application Support")
        let old = base.appending(path: "notproton")
        let save = base.appending(path: "Steam/steamapps/compatdata/220/pfx/save.dat")
        for dir in [old, save.deletingLastPathComponent()] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        try Data("progress".utf8).write(to: save)
        try LegacyInstallation.migrate(home: home, checkCanWrite: {})
        _ = try Uninstall.remove(legacyCompat: home.appending(path: "absent"), compatTool: home.appending(path: "absent-tool"), directories: LegacyInstallation.removalDirectories(home: home))
        #expect(!fm.fileExists(atPath: old.path))
        #expect(!fm.fileExists(atPath: base.appending(path: "steamgptk").path))
        #expect(try Data(contentsOf: save) == Data("progress".utf8))
    }

    @Test("Existing launch options still export renamed settings rather than reaching the game")
    func acceptsPreviousLaunchOptions() throws {
        let fm = FileManager.default
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
        let parser = try #require(source.components(separatedBy: "\ncase \"$verb\" in").first)
        let file = fm.temporaryDirectory.appending(path: "steamgptk-options-\(UUID().uuidString).sh")
        defer { try? fm.removeItem(at: file) }
        try Data((parser + "\nprintf '%s|%s|%s' \"$STEAMGPTK_RETINA\" \"$STEAMGPTK_HIDE_LAUNCHER_TILE\" \"$*\"\n").utf8).write(to: file)
        let result = try Shell.check("/bin/sh", [file.path, "run", "hl2.exe", "NOTPROTON_RETINA=0", "NOTPROTON_HIDE_LAUNCHER_TILE=1", "-novid"])
        #expect(result == "0|1|hl2.exe -novid")
    }

    @Test("An old Steam injection can be upgraded without accepting another module")
    func upgradesPreviousInjection() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let app = root.appending(path: "Steam.app")
        let plist = app.appending(path: "Contents/Info.plist")
        try fm.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = app.appending(path: "Contents/MacOS/notproton.dylib")
        let current = app.appending(path: "Contents/MacOS/steamgptk.dylib")
        let info: [String: Any] = ["LSEnvironment": ["DYLD_INSERT_LIBRARIES": old.path,
            "NOTPROTON_SIG": "/profiles/keep.json", "CUSTOM": "keep"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        try SteamInstaller.assertInsertIsDeployedOrAbsent(at: plist, dylib: current)
        if case .outdated = SteamBundle.deployment(bundledVersion: "0.2.0", app: app, versionFile: root.appending(path: "version")) {} else {
            Issue.record("An earlier installation should offer repair")
        }
        try SteamInstaller.setInsert(at: plist, to: current)
        let environment = try #require(SteamBundle.readInfoPlist(at: plist)?["LSEnvironment"] as? [String: String])
        #expect(environment["STEAMGPTK_SIG"] == "/profiles/keep.json")
        #expect(environment["NOTPROTON_SIG"] == nil)
        #expect(environment["CUSTOM"] == "keep")
        #expect(environment["DYLD_INSERT_LIBRARIES"] == current.path)
    }

    @Test("Upgrade retains runtime, GPTK and backups and leaves game saves untouched")
    func preservesUserData() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let support = home.appending(path: "Library/Application Support")
        let old = support.appending(path: "notproton")
        let runtime = old.appending(path: "runners/sikarugir-11/Frameworks/renderer/d3dmetal/user-gptk")
        let backup = old.appending(path: "backups/keep-me")
        let save = support.appending(path: "Steam/steamapps/compatdata/220/pfx/drive_c/users/steamuser/save.dat")
        for file in [runtime, backup, save] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.lastPathComponent.utf8).write(to: file)
        }
        try fm.createSymbolicLink(atPath: old.appending(path: "runners/current").path, withDestinationPath: "sikarugir-11")
        let saveBefore = try Data(contentsOf: save)
        #expect(LegacyInstallation.support(in: support) == old)
        for _ in 0..<2 { try LegacyInstallation.migrate(home: home, checkCanWrite: {}) }
        let current = support.appending(path: "steamgptk")
        #expect(LegacyInstallation.support(in: support) == current)
        #expect(try Data(contentsOf: current.appending(path: "runners/current/Frameworks/renderer/d3dmetal/user-gptk")) == Data("user-gptk".utf8))
        #expect(try Data(contentsOf: current.appending(path: "backups/keep-me")) == Data("keep-me".utf8))
        #expect(try Data(contentsOf: runtime) == Data("user-gptk".utf8))
        #expect(try Data(contentsOf: save) == saveBefore)
    }

    @Test("Upgrade rewrites only compatibility tool mappings and backs up the configuration")
    func migratesMappings() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let config = home.appending(path: "Library/Application Support/Steam/config/config.vdf")
        try fm.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"""
        "InstallConfigStore" {
          "unrelated" { "name" "notproton" }
          "CompatToolMapping" {
            "220" { "name" "notproton" "config" "" "priority" "250" }
            "1091500" { "name" "notproton.none" "priority" "250" }
            "42" { "name" "proton_experimental" }
          }
          // "name" "notproton" must remain inside this comment
          "LaunchOptions" "-novid CUSTOM=\"hello world\""
        }
        """#
        try Data(original.utf8).write(to: config)
        let declaration = config.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "compatibilitytools.d/steamgptk-proton/compatibilitytool.vdf")
        try fm.createDirectory(at: declaration.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\"compat_tools\" { \"steamgptk-proton\" {} }".utf8).write(to: declaration)
        for _ in 0..<2 { try LegacyInstallation.migrate(home: home, checkCanWrite: {}) }
        let result = try String(contentsOf: config, encoding: .utf8)
        #expect(result.contains(#""220" { "name" "steamgptk-proton""#))
        #expect(result.contains(#""1091500" { "name" "steamgptk.none""#))
        #expect(result.contains(#""unrelated" { "name" "notproton" }"#))
        #expect(result.contains(#""42" { "name" "proton_experimental" }"#))
        #expect(result.contains(#"// "name" "notproton" must remain"#))
        #expect(result.contains(#""LaunchOptions" "-novid CUSTOM=\"hello world\""#))
        #expect(try String(contentsOf: config.appendingPathExtension("before-steamgptk-0.2.0"), encoding: .utf8) == original)
    }

    @Test("Different old and new data directories are preserved instead of merged")
    func refusesConflictingData() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let support = home.appending(path: "Library/Application Support")
        for name in ["notproton", "steamgptk"] {
            let dir = support.appending(path: name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: dir.appending(path: "keep"))
        }
        #expect(throws: (any Error).self) { try LegacyInstallation.migrate(home: home, checkCanWrite: {}) }
        for name in ["notproton", "steamgptk"] {
            #expect(try String(contentsOf: support.appending(path: "\(name)/keep"), encoding: .utf8) == name)
        }
    }

    @Test("A process starting during upgrade prevents migration writes")
    func requiresIdle() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: home) }
        let support = home.appending(path: "Library/Application Support")
        try fm.createDirectory(at: support.appending(path: "notproton"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) {
            try LegacyInstallation.migrate(home: home, checkCanWrite: { throw CocoaError(.userCancelled) })
        }
        #expect(!fm.fileExists(atPath: support.appending(path: "steamgptk").path))
    }
}
