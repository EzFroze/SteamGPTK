// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation
import Testing
@testable import NotProtonApp

@Suite("Real free installation", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["NOTPROTON_INSTALL_SMOKE"] == "1"))
struct FreeInstallSmokeTests {
    @Test("A fresh Wine install requires user GPTK, imports it, runs Wine and survives repair")
    func realInstallAndRepair() async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "notproton-install-smoke-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let root = work.appending(path: "runners/sikarugir-11")
        try await FreeRunnerInstaller.prepare(root: root)
        let renderer = root.appending(path: GPTKImport.relativePath)
        #expect(!fm.fileExists(atPath: renderer.path))
        #expect(!fm.fileExists(atPath: root.appending(path: "Frameworks/renderer/apple_gptk").path))
        #expect(fm.fileExists(atPath: root.appending(path: "Frameworks/renderer/dxmt/wine/x86_64-windows/d3d11.dll").path))
        #expect(fm.fileExists(atPath: root.appending(path: "Frameworks/renderer/dxvk/wine/x86_64-windows/d3d11.dll").path))
        #expect(GPTKImport.version(in: renderer) == nil)
        let dmg = try #require(ProcessInfo.processInfo.environment["NOTPROTON_GPTK_DMG"])
        try GPTKImport.importDMG(URL(filePath: dmg), runner: root)
        #expect(GPTKImport.version(in: renderer) == "4.0b3")
        let payload = try InstallPayload.root()
        let bridge = work.appending(path: "bridge")
        let tool = work.appending(path: "compatibilitytools.d/notproton")
        try FreeRunnerInstaller.configure(root: root, bridge: bridge, payload: payload, tool: tool)
        #expect(FreeRuntime.verify(root: root).isEmpty)
        #expect(FreeRuntime.cloudProfilesReady(tool: tool))
        let before = try Digest.sha256(of: renderer.appending(path: "external/libd3dshared.dylib"))
        // Install / Repair must rebuild damaged Wine while retaining imported GPTK.
        try fm.removeItem(at: root.appending(path: "lib/wine/x86_64-windows/ntdll.dll"))
        try await FreeRunnerInstaller.prepare(root: root)
        try FreeRunnerInstaller.configure(root: root, bridge: bridge, payload: payload, tool: tool)
        #expect(FreeRuntime.verify(root: root).isEmpty)
        #expect(try Digest.sha256(of: renderer.appending(path: "external/libd3dshared.dylib")) == before)
        // Prefix tools use the same engine and create the Steam Cloud profile layout.
        let prefix = WinePrefix(appID: "480", name: nil, library: SteamLibrary(root: work), lastUsed: nil)
        try fm.createDirectory(at: prefix.root, withIntermediateDirectories: true)
        defer {
            _ = try? Shell.run(root.appending(path: "bin/wineserver").path, ["-k"],
                               environment: PrefixTools.environment(prefix: prefix, runner: root))
        }
        try PrefixTools.recreate(prefix, runner: root)
        let users = prefix.pfx.appending(path: "drive_c/users")
        #expect(users.appending(path: NSUserName()).resolvingSymlinksInPath() == users.appending(path: "steamuser").resolvingSymlinksInPath())
    }
}
