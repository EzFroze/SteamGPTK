// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation
import Testing
@testable import NotProtonApp

@Suite("User supplied GPTK")
struct GPTKImportTests {
    func fixture(in root: URL, version: String = "4.0b3") throws -> URL {
        let lib = root.appending(path: UUID().uuidString)
        let framework = lib.appending(path: "external/D3DMetal.framework/Versions/A")
        for name in ["external/libd3dshared.dylib", "external/D3DMetal.framework/Versions/A/D3DMetal", "wine/x86_64-windows/d3d11.dll", "wine/x86_64-windows/d3d12.dll", "wine/x86_64-windows/dxgi.dll", "wine/x86_64-windows/d3d12core.dll", "wine/x86_64-unix/d3d11.so", "wine/x86_64-unix/d3d12.so", "wine/x86_64-unix/d3d12core.so", "wine/x86_64-unix/dxgi.so"] {
            let url = lib.appending(path: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: url)
        }
        let plist = framework.appending(path: "Resources/Info.plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.apple.D3DMetal", "CFBundleShortVersionString": version], format: .xml, options: 0)
        try data.write(to: plist)
        return lib
    }

    @Test("A complete GPTK 4 import preserves the previous renderer in a backup")
    func importsAndKeepsBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try fixture(in: dir, version: "4.0b2")
        let runner = dir.appending(path: "runner")
        let target = runner.appending(path: "Frameworks/renderer/d3dmetal")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: old, to: target)
        let incoming = try fixture(in: dir)
        let backup = try GPTKImport.installLibrary(from: incoming, runner: runner)
        #expect(GPTKImport.version(in: target) == "4.0b3")
        #expect(GPTKImport.version(in: try #require(backup)) == "4.0b2")
    }

    @Test("An incomplete import does not change the installed GPTK")
    func refusesIncompleteImport() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let incoming = try fixture(in: dir)
        try FileManager.default.removeItem(at: incoming.appending(path: "wine/x86_64-windows/d3d12.dll"))
        #expect(throws: (any Error).self) { try GPTKImport.installLibrary(from: incoming, runner: dir.appending(path: "runner")) }
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "runner/Frameworks/renderer/d3dmetal").path))
        #expect(GPTKImport.version(in: incoming) == nil)
    }
    @Test("A GPTK missing a Unix graphics bridge is refused")
    func refusesMissingUnixBridge() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let incoming = try fixture(in: dir)
        try FileManager.default.removeItem(at: incoming.appending(path: "wine/x86_64-unix/d3d12.so"))
        #expect(GPTKImport.version(in: incoming) == nil)
        #expect(throws: (any Error).self) { try GPTKImport.installLibrary(from: incoming, runner: dir.appending(path: "runner")) }
    }

}
