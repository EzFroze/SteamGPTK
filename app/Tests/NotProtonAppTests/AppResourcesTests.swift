// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Foundation
import Testing
@testable import NotProtonApp

@Suite("Packaged resource lookup")
struct AppResourcesTests {
    @Test("App resources load with native and Swift Build bundle layouts", arguments: [false, true])
    func loadsPackagedLayouts(structured: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "steamgptk-resource-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleRoot = directory.appending(path: AppResources.bundleName)
        let resources = structured ? bundleRoot.appending(path: "Contents/Resources") : bundleRoot
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        if structured {
            let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "test.steamgptk.resources", "CFBundlePackageType": "BNDL"], format: .xml, options: 0)
            try info.write(to: bundleRoot.appending(path: "Contents/Info.plist"))
        }
        try Data("packaged".utf8).write(to: resources.appending(path: "probe.txt"))
        let bundle = try #require(AppResources.packagedBundle(in: directory))
        let file = try #require(bundle.url(forResource: "probe", withExtension: "txt"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "packaged")
        #expect(bundle.bundleURL.resolvingSymlinksInPath() == bundleRoot.resolvingSymlinksInPath())
    }

    @Test("Unpackaged test executables can use the SwiftPM fallback")
    func noPackagedBundle() {
        #expect(AppResources.packagedBundle(in: nil) == nil)
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(AppResources.packagedBundle(in: missing) == nil)
    }
}
