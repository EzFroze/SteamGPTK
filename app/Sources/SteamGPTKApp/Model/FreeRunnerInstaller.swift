// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation

enum FreeRunnerInstaller {
    static let step = "Set up Wine / GPTK"

    // Only Wine and its support libraries are downloaded. D3DMetal is excluded
    // during extraction; GPTK is imported separately from the user's Apple DMG.
    static func prepare(root: URL = FreeRuntime.root, downloads: URL = FreeRuntime.downloads,
                        report: @escaping @Sendable (String) -> Void = { _ in },
                        checkCanWrite: @escaping @Sendable () throws -> Void = {}) async throws {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: root.appending(path: "bin/wine").path),
           fm.isExecutableFile(atPath: root.appending(path: "bin/wineserver").path),
           fm.fileExists(atPath: root.appending(path: "Frameworks/GStreamer.framework").path),
           fm.fileExists(atPath: root.appending(path: "Frameworks/libinotify.0.dylib").path),
           FreeRuntime.d9vkFiles.allSatisfy({ fm.fileExists(atPath: root.appending(path: $0).path) }),
           VulkanDrivers.isComplete(root: root),
           [FreeRuntime.cleanNtdll, FreeRuntime.patchedNtdll].contains(Digest.sha256IfPresent(root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")) ?? ""),
           FreeRuntime.loaderWorks(root: root) { return }
        report("Downloading Wine 11")
        let engine = try await PinnedDownload.obtain(
            file: "WS12WineSikarugir11.0_1.tar.xz",
            sha256: "67e29fb3d74f363af39c69ba11f9b13a79812c5db07cf4748672658e4a200a0e",
            bases: [URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0")!],
            into: downloads, step: step)
        report("Preparing Wine support libraries")
        let template = try await PinnedDownload.obtain(
            file: "Template-1.0.21.tar.xz",
            sha256: "bbe996e4e4375318485953d0c7818b7b4b0a4dc1f13303bcc584f99f7602f78d",
            bases: [URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0")!],
            into: downloads, step: step)
        try await Task.detached(priority: .userInitiated) {
            let staging = fm.temporaryDirectory.appending(path: "steamgptk-wine-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            _ = try Shell.check("/usr/bin/tar", ["-xJf", engine.path, "-C", staging.path])
            _ = try Shell.check("/usr/bin/tar", ["-xJf", template.path, "-C", staging.path,
                "--exclude", "*/Frameworks/renderer/d3dmetal", "--exclude", "*/Frameworks/renderer/d3dmetal/*",
                "--exclude", "*/Frameworks/renderer/apple_gptk", "--exclude", "*/Frameworks/renderer/apple_gptk/*",
                "Template-1.0.21.app/Contents/Frameworks", "Template-1.0.21.app/Contents/Resources/vulkan"])
            let assembled = staging.appending(path: "wswine.bundle")
            let support = staging.appending(path: "Template-1.0.21.app/Contents")
            try fm.copyItem(at: support.appending(path: "Frameworks"), to: assembled.appending(path: "Frameworks"))
            try fm.copyItem(at: support.appending(path: "Resources/vulkan"), to: assembled.appending(path: "vulkan"))
            let previousGPTK = root.appending(path: GPTKImport.relativePath)
            if GPTKImport.version(in: previousGPTK) != nil {
                try fm.createDirectory(at: assembled.appending(path: "Frameworks/renderer"), withIntermediateDirectories: true)
                try fm.copyItem(at: previousGPTK, to: assembled.appending(path: GPTKImport.relativePath))
            }
            let targetParent = root.deletingLastPathComponent()
            try fm.createDirectory(at: targetParent, withIntermediateDirectories: true)
            let ready = targetParent.appending(path: ".wine-ready-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: ready) }
            try fm.copyItem(at: assembled, to: ready)
            try checkCanWrite()
            var backup: URL?
            if fm.fileExists(atPath: root.path) {
                let old = targetParent.appending(path: "sikarugir.backup-\(UUID().uuidString)")
                try fm.moveItem(at: root, to: old)
                backup = old
            }
            do { try fm.moveItem(at: ready, to: root) }
            catch { if let backup { try? fm.moveItem(at: backup, to: root) }; throw error }
        }.value
    }

    static func configure(root: URL, bridge: URL, payload: URL, tool: URL, patch suppliedPatch: FreeNtdllPatch? = nil) throws {
        let fm = FileManager.default
        let ntdll = root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        let patch = try suppliedPatch ?? FreeNtdllPatch.bundled()
        let originalBytes = try Data(contentsOf: ntdll)
        let patchedBytes = try patch.apply(to: originalBytes)
        guard let scriptURL = AppResources.bundle.url(forResource: "compat_run", withExtension: "sh") else {
            throw StepFailure(step: step, detail: "The Wine launch script is missing from this application.")
        }
        let script = try Data(contentsOf: scriptURL)
        let current = root.deletingLastPathComponent().appending(path: "current")
        if fm.fileExists(atPath: current.path),
           (try? fm.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType) != .typeSymbolicLink {
            throw StepFailure(step: step, detail: "runners/current is not a symlink; it was preserved.")
        }
        try VulkanDrivers.configure(root: root)
        _ = try BridgePayload.stage(located: BridgePayload.locate(root: payload.appending(path: "bridge")), bridge: bridge)
        if originalBytes != patchedBytes {
            let original = ntdll.appendingPathExtension("steamgptk-orig")
            if !fm.fileExists(atPath: original.path) { try fm.copyItem(at: ntdll, to: original) }
            try atomicReplace(ntdll, with: patchedBytes, step: step)
        }
        try atomicReplace(bridge.appending(path: "wine/x86_64-windows/ntdll.dll"), with: patchedBytes, step: step)
        for (source, target) in [("x86_64-windows/lsteamclient.dll", "lib/wine/x86_64-windows/lsteamclient.dll"),
                                 ("x86_64-unix/lsteamclient.so", "lib/wine/x86_64-unix/lsteamclient.so")] {
            try atomicReplace(root.appending(path: target), with: Data(contentsOf: bridge.appending(path: source)), step: step)
        }
        for directory in [root.appending(path: "lib/wine/x86_64-unix"), bridge.appending(path: "x86_64-unix")] {
            for name in ["steamclient.so", "steamclient64.so"] {
                let link = directory.appending(path: name)
                try? fm.removeItem(at: link)
                try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "lsteamclient.so")
            }
        }
        let env = FreeRuntime.environment(root: root).sorted(by: { $0.key < $1.key }).map { key, value in
            if key == "ROSETTA_ADVERTISE_AVX" { return "export ROSETTA_ADVERTISE_AVX=\"${ROSETTA_ADVERTISE_AVX:-1}\"" }
            return "export \(key)='" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
        }.joined(separator: "\n") + "\n" + """
        case "${CX_GRAPHICS_BACKEND:-d3dmetal}" in
          dxmt)
            unset WINEDLLPATH_D3DMETAL
            export WINEDLLPATH_DXMT="$CX_ROOT/Frameworks/renderer/dxmt/wine"
            export WINEDLLPATH_PREPEND="$WINEDLLPATH_DXMT"
            ;;
          dxvk)
            unset WINEDLLPATH_D3DMETAL
            export WINEDLLPATH_DXVK="$CX_ROOT/Frameworks/renderer/dxvk/wine"
            export WINEDLLPATH_PREPEND="$WINEDLLPATH_DXVK"
            ;;
          wined3d)
            unset WINEDLLPATH_D3DMETAL WINEDLLPATH_D9VK WINEDLLPATH_DXMT WINEDLLPATH_DXVK WINEDLLPATH_PREPEND
            ;;
        esac

        """
        try atomicReplace(root.appending(path: "runner.env"), with: Data(env.utf8), step: step)
        try atomicReplace(tool.appending(path: "run"), with: script, step: step)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.appending(path: "run").path)
        let declaration = "\"compatibilitytools\" { \"compat_tools\" { \"steamgptk-proton\" { \"install_path\" \".\" \"display_name\" \"SteamGPTK (Wine / GPTK)\" \"from_oslist\" \"windows\" \"to_oslist\" \"macos\" } } }\n"
        try atomicReplace(tool.appending(path: "compatibilitytool.vdf"), with: Data(declaration.utf8), step: step)
        try atomicReplace(tool.appending(path: "toolmanifest.vdf"), with: Data("\"manifest\" { \"version\" \"2\" \"commandline\" \"/run %verb%\" }\n".utf8), step: step)
        let stagedLink = current.deletingLastPathComponent().appending(path: ".current-\(UUID().uuidString)")
        try fm.createSymbolicLink(atPath: stagedLink.path, withDestinationPath: root.lastPathComponent)
        guard rename(stagedLink.path, current.path) == 0 else {
            try? fm.removeItem(at: stagedLink)
            throw StepFailure(step: step, detail: "The active Wine link could not be changed.")
        }
    }
}
