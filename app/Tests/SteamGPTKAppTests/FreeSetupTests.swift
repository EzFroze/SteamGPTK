// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation
import Testing
@testable import SteamGPTKApp

@Suite("Free runtime installation")
struct FreeSetupTests {
    @Test("Setup retains user GPTK while installing the free environment and compatibility tool")
    func configuresFreeRuntime() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let root = dir.appending(path: "runners/sikarugir-11")
        let ntdll = root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        try fm.createDirectory(at: ntdll.deletingLastPathComponent(), withIntermediateDirectories: true)
        let payload = try InstallPayload.root()
        try Data([1, 2, 3, 4]).write(to: ntdll)
        let patch = FreeNtdllPatch(clean_sha256: "9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a", patched_sha256: "3b5c6e3f50327e86c4e19d7fa3b5719f0f9b0e4f0f01f8ad47d4b520a5ba8612", ranges: [.init(offset: 1, bytes: "ff")])
        let retained = root.appending(path: "Frameworks/renderer/d3dmetal/keep-me")
        try fm.createDirectory(at: retained.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("user supplied".utf8).write(to: retained)
        let icds = root.appending(path: "vulkan/icd.d")
        try fm.createDirectory(at: icds, withIntermediateDirectories: true)
        for (name, library) in [("kosmickrisp_mesa_icd.json", "libvulkan_kosmickrisp.dylib"),
                                ("MoltenVK_icd.json", "libMoltenVK.dylib")] {
            let manifest: [String: Any] = ["file_format_version": "1.0.1", "ICD": [
                "api_version": "1.4.0", "library_path": "../../../Frameworks/\(library)",
                "is_portability_driver": true,
            ]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: icds.appending(path: name))
            try Data("driver fixture".utf8).write(to: root.appending(path: "Frameworks/\(library)"))
        }
        for arch in ["i386-windows", "x86_64-windows"] {
            let dll = root.appending(path: "Frameworks/renderer/d9vk/wine/\(arch)/d3d9.dll")
            try fm.createDirectory(at: dll.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("D3D9 fixture".utf8).write(to: dll)
        }
        let tool = dir.appending(path: "compatibilitytools.d/steamgptk-proton")
        try FreeRunnerInstaller.configure(root: root, bridge: dir.appending(path: "bridge"), payload: payload, tool: tool, patch: patch)
        #expect(try Data(contentsOf: ntdll) == Data([1, 255, 3, 4]))
        #expect(try Data(contentsOf: ntdll.appendingPathExtension("steamgptk-orig")) == Data([1, 2, 3, 4]))
        #expect(fm.isExecutableFile(atPath: tool.appending(path: "run").path))
        #expect((try String(contentsOf: tool.appending(path: "compatibilitytool.vdf"), encoding: .utf8)).contains("Wine / GPTK"))
        #expect(try fm.destinationOfSymbolicLink(atPath: root.deletingLastPathComponent().appending(path: "current").path) == "sikarugir-11")
        #expect((try String(contentsOf: retained, encoding: .utf8)) == "user supplied")
        for (backend, folder) in [("d3dmetal", "d3dmetal"), ("dxmt", "dxmt"), ("dxvk", "dxvk")] {
            var env = ProcessInfo.processInfo.environment
            env["CX_ROOT"] = root.path
            env["CX_GRAPHICS_BACKEND"] = backend
            env["ROSETTA_ADVERTISE_AVX"] = "0"
            let result = try Shell.check("/bin/sh", ["-c", ". \"$1\"; printf '%s\\n%s\\n%s' \"$ROSETTA_ADVERTISE_AVX\" \"$WINEDLLPATH_PREPEND\" \"$WINEDLLPATH_D9VK\"", "sh", root.appending(path: "runner.env").path], environment: env)
            #expect(result == "0\n" + root.appending(path: "Frameworks/renderer/\(folder)/wine").path
                + "\n" + root.appending(path: "Frameworks/renderer/d9vk/wine").path)
        }
        var softwareEnv = ProcessInfo.processInfo.environment
        softwareEnv["CX_ROOT"] = root.path
        softwareEnv["CX_GRAPHICS_BACKEND"] = "wined3d"
        let software = try Shell.check("/bin/sh", ["-c", ". \"$1\"; printf '%s%s%s' \"$WINEDLLPATH_D9VK\" \"$WINEDLLPATH_D3DMETAL\" \"$WINEDLLPATH_PREPEND\"", "sh", root.appending(path: "runner.env").path], environment: softwareEnv)
        #expect(software.isEmpty, "An explicit WineD3D choice must disable the automatic renderers")
        // Both first setup and repair must leave paths relative to the relocated
        // manifest, not to the original wrapper's Contents/Resources directory.
        for _ in 0..<2 {
            for name in ["kosmickrisp_mesa_icd.json", "MoltenVK_icd.json"] {
                let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: icds.appending(path: name))) as? [String: Any])
                let icd = try #require(manifest["ICD"] as? [String: Any])
                let library = try #require(icd["library_path"] as? String)
                #expect(fm.fileExists(atPath: icds.appending(path: library).standardizedFileURL.path))
                #expect(icd["is_portability_driver"] as? Bool == true)
                #expect(icd["api_version"] as? String == "1.4.0")
            }
            try FreeRunnerInstaller.configure(root: root, bridge: dir.appending(path: "bridge"), payload: payload, tool: tool, patch: patch)
        }
    }

    @Test("An unknown Wine version is refused before files are changed")
    func rejectsUnknownWine() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: dir) }
        let root = dir.appending(path: "sikarugir-11")
        let ntdll = root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")
        try fm.createDirectory(at: ntdll.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unknown wine".utf8).write(to: ntdll)
        let tool = dir.appending(path: "tool")
        #expect(throws: (any Error).self) {
            try FreeRunnerInstaller.configure(root: root, bridge: dir.appending(path: "bridge"), payload: try InstallPayload.root(), tool: tool)
        }
        #expect(!fm.fileExists(atPath: tool.path))
        #expect((try String(contentsOf: ntdll, encoding: .utf8)) == "unknown wine")
    }
}
