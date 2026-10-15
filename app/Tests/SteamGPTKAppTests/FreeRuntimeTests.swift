// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation
import Testing
@testable import SteamGPTKApp

@Suite("Free Wine runtime")
struct FreeRuntimeTests {
    @Test("Missing or malformed Vulkan support is reported as needing runtime repair")
    func detectsDamagedVulkan() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let icds = root.appending(path: "vulkan/icd.d")
        try fm.createDirectory(at: icds, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "Frameworks"), withIntermediateDirectories: true)
        for (name, library) in [("kosmickrisp_mesa_icd.json", "libvulkan_kosmickrisp.dylib"), ("MoltenVK_icd.json", "libMoltenVK.dylib")] {
            try Data("{\"ICD\":{\"library_path\":\"../../Frameworks/\(library)\"}}".utf8).write(to: icds.appending(path: name))
            try Data("driver".utf8).write(to: root.appending(path: "Frameworks/\(library)"))
        }
        #expect(!FreeRuntime.verify(root: root).contains("Vulkan driver files need repair"))
        let manifest = icds.appending(path: "MoltenVK_icd.json")
        let saved = try Data(contentsOf: manifest)
        try fm.removeItem(at: manifest)
        #expect(FreeRuntime.verify(root: root).contains("Vulkan driver files need repair"))
        try Data("not JSON".utf8).write(to: manifest)
        #expect(FreeRuntime.verify(root: root).contains("Vulkan driver files need repair"))
        try saved.write(to: manifest)
        try fm.removeItem(at: root.appending(path: "Frameworks/libvulkan_kosmickrisp.dylib"))
        #expect(FreeRuntime.verify(root: root).contains("Vulkan driver files need repair"))
    }

    @Test("Sikarugir Wine is recognised without a CrossOver directory or license")
    func recognisesFreeRuntime() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "free-runner-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let root = dir.appending(path: "sikarugir-11")
        try fm.createDirectory(at: root.appending(path: "lib/wine"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: dir.appending(path: "current").path, withDestinationPath: "sikarugir-11")
        #expect(RunnerStore.state(runners: dir, verify: { _, _ in [] }) == .cloned(build: "sikarugir-11", supported: true))
        #expect(RunnerStore.currentBuild(runners: dir) == "sikarugir-11")
    }

    @Test("Wine tools use the free runtime's bin executables and framework libraries")
    func toolsUseFreeEnvironment() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appending(path: "free-tools-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appending(path: "bin"), withIntermediateDirectories: true)
        for name in ["wine", "wineserver"] {
            let file = dir.appending(path: "bin/\(name)")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try Data("# Sikarugir environment".utf8).write(to: dir.appending(path: "runner.env"))
        let prefix = WinePrefix(appID: "480", name: nil, library: SteamLibrary(root: dir), lastUsed: nil)
        let layout = PrefixTools.layout(runner: dir)
        #expect(layout.loader.path == dir.appending(path: "bin/wine").path)
        #expect(layout.server.path == dir.appending(path: "bin/wineserver").path)
        let env = PrefixTools.environment(prefix: prefix, runner: dir)
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]?.contains("Frameworks/GStreamer.framework/Libraries") == true)
        #expect(env["CX_D3DMETALPATH"] == dir.appending(path: "Frameworks/renderer/d3dmetal").path)
    }
}
