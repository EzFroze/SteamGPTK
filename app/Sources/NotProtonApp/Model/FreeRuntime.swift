// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

// The free runner has its own identity and file layout. Apple components are
// imported from a user-selected DMG and are never resources of this application.
enum FreeRuntime {
    static let id = "sikarugir-11"
    static let cleanNtdll = "654a39115c3fad3d57716f664a96ddcf580f1e76e852e85a6d7d42017c741ff2"
    static let patchedNtdll = "5429ba1fcd340b4f9bd39e19c9fed38771578203e8574421b44c806a8f6da529"
    static let build = RunnerBuild(
        bundleVersion: id, releaseVersion: "Wine 11", flavor: nil,
        loaderSHA256: "f309b89a9726ea21dbe1fb60a8cc11aaf11168a952a6cf1a08e6823651acc7dd",
        cleanNtdll: [.x86_64Windows: cleanNtdll],
        patchedNtdll: [.x86_64Windows: patchedNtdll]
    )

    static var root: URL { SupportPaths.runners.appending(path: id) }
    static var downloads: URL {
        SupportPaths.home.appending(path: "Library/Caches/notproton-free/downloads")
    }

    static func cloudProfilesReady(tool: URL = SupportPaths.Steam.compatTool) -> Bool {
        guard let bundled = AppResources.bundle.url(forResource: "compat_run", withExtension: "sh"),
              let expected = Digest.sha256IfPresent(bundled) else { return false }
        return Digest.sha256IfPresent(tool.appending(path: "run")) == expected
    }

    static func requireIdle() throws {
        guard !SteamBundle.isRunning,
              !PrefixStore.all(libraries: PrefixStore.libraries()).contains(where: { PrefixStore.isInUse($0) }) else {
            throw StepFailure(step: "Install Wine / GPTK", detail: "Steam or a Windows program was started. Quit it and try again; the active files were preserved.")
        }
    }

    static func loaderWorks(root: URL) -> Bool {
        var env = ProcessInfo.processInfo.environment
        env.merge(environment(root: root)) { _, value in value }
        for (file, argument) in [("bin/wine", "--version"), ("bin/wineserver", "-v")] {
            guard (try? Shell.run(root.appending(path: file).path, [argument], environment: env).succeeded) == true else { return false }
        }
        return true
    }

    static func environment(root: URL) -> [String: String] {
        let r = root.path(percentEncoded: false)
        let f = r + "/Frameworks"
        let d = f + "/renderer/d3dmetal"
        return [
            "SikarugirAppWine11": "1",
            "DYLD_FALLBACK_LIBRARY_PATH": "\(r)/lib:\(f):\(f)/GStreamer.framework/Libraries:/usr/lib",
            "GST_PLUGIN_PATH": f + "/GStreamer.framework/Libraries/gstreamer-1.0",
            "WINEDLLPATH_D3DMETAL": d + "/wine",
            "WINEDLLPATH_PREPEND": d + "/wine",
            "CX_D3DMETALPATH": d,
            "CX_APPLEGPT_LIBD3DSHARED_PATH": d + "/external/libd3dshared.dylib",
            "CX_APPLEGPTK_LIBD3DSHARED_PATH": d + "/external/libd3dshared.dylib",
            "CX_FWD_COMPAT_GL_CTX": "1", "DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN": "1",
            "MVK_CONFIG_RESUME_LOST_DEVICE": "1", "ROSETTA_ADVERTISE_AVX": "1",
            "VK_DRIVER_FILES": r + "/vulkan/icd.d/kosmickrisp_mesa_icd.json",
            "WINEBOOT_HIDE_DIALOG": "1", "D3DM_SUPPORT_DXR": "0",
        ]
    }

    static func verify(root: URL) -> [String] {
        let fm = FileManager.default
        var problems: [String] = []
        for file in ["bin/wine", "bin/wineserver"] {
            if !fm.isExecutableFile(atPath: root.appending(path: file).path) {
                problems.append("\(file) is missing or not executable")
            }
        }
        if Digest.sha256IfPresent(root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")) != patchedNtdll {
            problems.append("Wine 11 ntdll needs the Steam bridge patch")
        }
        if !fm.fileExists(atPath: root.appending(path: "runner.env").path) {
            problems.append("Wine environment is missing")
        }
        for file in ["lib/wine/x86_64-windows/lsteamclient.dll", "lib/wine/x86_64-unix/lsteamclient.so"] {
            if !fm.fileExists(atPath: root.appending(path: file).path) { problems.append("\(file) is missing") }
        }
        if problems.isEmpty, !loaderWorks(root: root) { problems.append("Wine cannot load its support libraries") }
        return problems
    }
}
