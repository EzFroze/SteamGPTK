// SteamGPTK fork modifications, 2026-10-16. Existing component licenses apply.
import Foundation
import Testing
@testable import SteamGPTKApp

@Suite("Automatic game profiles")
struct GameProfileTests {
    private let patched32 = "2cf10ac8d935abc81b4bbc0ee85a5199728c6a60ba3b1e6250cdc3e405fde781"

    private func fixture() throws -> (work: URL, root: URL, bridge: URL, tool: URL) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "steamgptk-game-profile-\(UUID().uuidString)")
        let root = work.appending(path: "runners/sikarugir-11")
        let icds = root.appending(path: "vulkan/icd.d")
        try fm.createDirectory(at: icds, withIntermediateDirectories: true)
        let ntdll = root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        try fm.createDirectory(at: ntdll.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3, 4]).write(to: ntdll)
        try fm.createDirectory(at: root.appending(path: "Frameworks"), withIntermediateDirectories: true)
        for (name, library) in [("kosmickrisp_mesa_icd.json", "libvulkan_kosmickrisp.dylib"),
                                ("MoltenVK_icd.json", "libMoltenVK.dylib")] {
            try Data("{\"ICD\":{\"library_path\":\"../../../Frameworks/\(library)\"}}".utf8)
                .write(to: icds.appending(path: name))
            try Data("driver fixture".utf8).write(to: root.appending(path: "Frameworks/\(library)"))
        }
        return (work, root, work.appending(path: "bridge"), work.appending(path: "tool"))
    }

    private func configure(_ f: (work: URL, root: URL, bridge: URL, tool: URL), payload: URL? = nil) throws {
        let patch = FreeNtdllPatch(clean_sha256: Digest.sha256(of: Data([1, 2, 3, 4])),
                                  patched_sha256: Digest.sha256(of: Data([1, 255, 3, 4])),
                                  ranges: [.init(offset: 1, bytes: "ff")])
        try FreeRunnerInstaller.configure(root: f.root, bridge: f.bridge,
            payload: try payload ?? InstallPayload.root(), tool: f.tool, patch: patch)
    }

    // Execute the installed launcher's real initialization and bridge staging.
    // Only the two fixed support-directory paths are redirected to the fixture.
    // Stop before wineboot / UI / game execution: no live Steam or Wine is used.
    private func launch(_ f: (work: URL, root: URL, bridge: URL, tool: URL), appID: String = "220",
                        options: [String] = [], stageBridge: Bool = false,
                        forwardedOnly: Bool = false) throws -> [String: String] {
        let script = try String(contentsOf: f.tool.appending(path: "run"), encoding: .utf8)
        let initialization = script.components(separatedBy: "\nprefix_machine() {")
        try #require(initialization.count == 2, "Initialization boundary must exist before executing a launcher fixture")
        let startup = initialization[0]
            .replacingOccurrences(of: "CX_ROOT=\"$HOME/Library/Application Support/steamgptk/runners/current\"",
                                  with: "CX_ROOT=\"$TEST_RUNNER_ROOT\"")
        let bridgeStage: String
        if stageBridge {
            let section = try #require(script.components(separatedBy: "\nbridge_src=").dropFirst().first)
            bridgeStage = ("\nbridge_src=" + section.components(separatedBy: "\n  native_client=")[0] + "\nfi\n")
                .replacingOccurrences(of: "bridge_src=\"$HOME/Library/Application Support/steamgptk/bridge\"",
                                      with: "bridge_src=\"$TEST_BRIDGE_ROOT\"")
        } else { bridgeStage = "" }
        let prefix = f.work.appending(path: "compatdata/\(appID)/pfx")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
        let output: String
        if forwardedOnly {
            let lines = script.components(separatedBy: "\n")
            let start = try #require(lines.firstIndex { $0.hasPrefix("for name in $(env |") })
            let end = try #require(lines[(start + 1)...].firstIndex { $0 == "set -- \\" })
            output = "\nset -- --args game.exe\n" + lines[start..<end].joined(separator: "\n")
                + "\nprintf '%s\\n' \"$@\"\n"
        } else { output = "\nenv\n" }
        let result = try Shell.run("/bin/sh", ["-c", startup + bridgeStage + output,
            "sh", "waitforexitandrun", "game.exe"] + options, environment: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TEST_RUNNER_ROOT": f.root.path,
                "TEST_BRIDGE_ROOT": f.bridge.path,
                "STEAM_COMPAT_APP_ID": appID, "STEAM_COMPAT_DATA_PATH": prefix.deletingLastPathComponent().path,
                "WINEPREFIX": prefix.path,
            ])
        #expect(result.status == 0, "\(result.stdout)\n\(result.stderr)")
        return Dictionary(result.stdout.split(separator: "\n").compactMap { line -> (String, String)? in
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            return (String(pair[0]), String(pair[1]))
        }, uniquingKeysWith: { _, last in last })
    }

    @Test("HL2 automatically receives its renderer and VSync settings, without diagnostic HUDs")
    func automaticHL2Defaults() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.work) }
        try configure(f)
        let env = try launch(f)
        #expect(env["CX_GRAPHICS_BACKEND"] == "dxvk")
        #expect(env["WINEDLLPATH_D9VK"] == f.root.appending(path: "Frameworks/renderer/d9vk/wine").path)
        #expect(env["VK_DRIVER_FILES"] == f.root.appending(path: "vulkan/icd.d/kosmickrisp_mesa_icd.json").path)
        #expect(env["DXVK_CONFIG"] == "d3d9.presentInterval = 0")
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "0")
        #expect(env["DXVK_HUD"] == nil)
        #expect(env["MTL_HUD_ENABLED"] == nil)
        #expect(env["DXVK_CONFIG_FILE"] == nil, "The profile must not depend on a temporary config file")
    }

    @Test("Explicit launch options override the game profile and runner defaults")
    func manualOverridesWin() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.work) }
        try configure(f)
        let env = try launch(f, options: ["WINEDLLPATH_D9VK=/Custom Renderer/wine",
            "VK_DRIVER_FILES=/Custom Driver/icd.json", "DXVK_CONFIG=d3d9.presentInterval = 1",
            "ROSETTA_ADVERTISE_AVX=1", "DXVK_HUD=compiler"])
        #expect(env["WINEDLLPATH_D9VK"] == "/Custom Renderer/wine")
        #expect(env["VK_DRIVER_FILES"] == "/Custom Driver/icd.json")
        #expect(env["DXVK_CONFIG"] == "d3d9.presentInterval = 1")
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(env["DXVK_HUD"] == "compiler")
        let software = try launch(f, options: ["CX_GRAPHICS_BACKEND=wined3d"])
        #expect(software["WINEDLLPATH_D9VK"] == nil)
        #expect(software["WINEDLLPATH_D3DMETAL"] == nil)
        let configFile = try launch(f, options: ["DXVK_CONFIG_FILE=Z:/User Settings/dxvk.conf"])
        #expect(configFile["DXVK_CONFIG"] == nil, "A user config file must not be overridden by inline profile settings")
        #expect(configFile["DXVK_CONFIG_FILE"] == "Z:/User Settings/dxvk.conf")
    }

    @Test("Profile settings and either manual Vulkan driver variable reach the Wine app loader")
    func forwardsToLoader() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.work) }
        try configure(f)
        let defaults = try launch(f, forwardedOnly: true)
        #expect(defaults["DXVK_CONFIG"] == "d3d9.presentInterval = 0")
        #expect(defaults["ROSETTA_ADVERTISE_AVX"] == "0")
        #expect(defaults["WINEDLLPATH_D9VK"] == f.root.appending(path: "Frameworks/renderer/d9vk/wine").path)
        let manual = try launch(f, options: ["VK_ICD_FILENAMES=/Manual Driver/MoltenVK.json"], forwardedOnly: true)
        #expect(manual["VK_DRIVER_FILES"] == nil)
        #expect(manual["VK_ICD_FILENAMES"] == "/Manual Driver/MoltenVK.json")
    }

    @Test("An opt-out or an unknown game retains ordinary runner defaults")
    func unknownAndDisabledProfiles() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.work) }
        try configure(f)
        for env in [try launch(f, appID: "480"), try launch(f, options: ["STEAMGPTK_GAME_PROFILE=0"])] {
            #expect(env["CX_GRAPHICS_BACKEND"] == nil)
            #expect(env["DXVK_CONFIG"] == nil)
            #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
            #expect(env["WINEDLLPATH_PREPEND"] == f.root.appending(path: "Frameworks/renderer/d3dmetal/wine").path)
        }
    }

    @Test("Repair followed by Valve installation keeps the HL2 bridge, cache and manual overrides")
    func repairKeepsProfile() throws {
        let f = try fixture()
        let fm = FileManager.default
        defer { try? fm.removeItem(at: f.work) }
        let extracted = f.work.appending(path: "valve")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        let files = try ["steamclient.dll", "steamclient64.dll"].map { name in
            let bytes = Data("Valve original \(name)".utf8)
            try bytes.write(to: extracted.appending(path: name))
            return ValveFile(bridgePath: name, package: "fixture", innerPath: name, sha256: Digest.sha256(of: bytes))
        }
        let manifest = ValvePackageManifest(bases: [], packages: [], files: files, bundle: nil)
        let cache = f.work.appending(path: "compatdata/220/pfx/drive_c/users/steamuser/AppData/Local/dxvk/cache.bin")
        try fm.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("compiled shaders".utf8).write(to: cache)
        for _ in 0..<2 {
            try configure(f)
            // Same order as SystemStatus.installIntoSteam: Valve fetch is last.
            _ = try ValveFetcher.install(manifest, from: extracted, into: f.bridge)
            let env = try launch(f, stageBridge: true)
            #expect(env["DXVK_CONFIG"] == "d3d9.presentInterval = 0")
            let prefixSteam = f.work.appending(path: "compatdata/220/pfx/drive_c/Program Files (x86)/Steam")
            #expect(Digest.sha256IfPresent(prefixSteam.appending(path: "steamclient.dll")) == patched32)
            #expect(Digest.sha256IfPresent(f.root.appending(path: "lib/wine/i386-windows/lsteamclient.dll")) == patched32)
            #expect(Digest.sha256IfPresent(prefixSteam.appending(path: "steamclient64.dll")) == files[1].sha256)
            #expect(Digest.sha256IfPresent(f.bridge.appending(path: "steamclient.dll")) == files[0].sha256)
            #expect(try Data(contentsOf: cache) == Data("compiled shaders".utf8))
            let custom = try launch(f, options: ["WINEDLLPATH_D9VK=/User Choice/wine"])
            #expect(custom["WINEDLLPATH_D9VK"] == "/User Choice/wine")
        }
        _ = try launch(f, appID: "480", stageBridge: true)
        let other = f.work.appending(path: "compatdata/480/pfx/drive_c/Program Files (x86)/Steam/steamclient.dll")
        #expect(Digest.sha256IfPresent(other) == files[0].sha256, "An unprofiled game keeps its existing bridge route")
    }

    @Test("An unknown 32-bit bridge payload stops setup before the runner is changed")
    func unknownBridgeIsRefused() throws {
        let f = try fixture()
        let fm = FileManager.default
        defer { try? fm.removeItem(at: f.work) }
        let payload = f.work.appending(path: "payload")
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        try fm.copyItem(at: try InstallPayload.root().appending(path: "bridge"), to: payload.appending(path: "bridge"))
        try Data("unknown build".utf8).write(to: payload.appending(path: "bridge/i386-windows-lsteamclient.dll"))
        #expect(throws: StepFailure.self) { try configure(f, payload: payload) }
        #expect(!fm.fileExists(atPath: f.tool.path))
        #expect(try Data(contentsOf: f.root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")) == Data([1, 2, 3, 4]))
    }
}
