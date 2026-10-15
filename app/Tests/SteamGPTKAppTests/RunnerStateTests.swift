import Foundation
import Testing

@testable import SteamGPTKApp

@Suite("Runner state detection")
struct RunnerStateTests {

    // A stand in for the runners directory, built the same way the installer builds
    // the real one: a versioned directory plus a current symlink pointing into it.
    struct Fixture: ~Copyable {
        let runners: URL

        init() throws {
            runners = FileManager.default.temporaryDirectory
                .appending(path: "np-runners-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: runners, withIntermediateDirectories: true)
        }

        func makeClone(build: String, withWine: Bool = true, inBundle: Bool = false) throws -> String {
            let payload = inBundle ? "CrossOver Preview.app/Contents/SharedSupport/CrossOver" : "CrossOver"
            let relative = "crossover-\(build)/\(payload)"
            let root = runners.appending(path: relative)
            let leaf = withWine ? root.appending(path: "lib/wine") : root
            try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: true)
            return relative
        }

        func linkCurrent(to relative: String) throws {
            try FileManager.default.createSymbolicLink(
                atPath: runners.appending(path: "current").path(percentEncoded: false),
                withDestinationPath: relative
            )
        }

        deinit { try? FileManager.default.removeItem(at: runners) }
    }

    @Test("No current link means nothing is set up")
    func reportsNone() throws {
        let fixture = try Fixture()
        #expect(RunnerStore.state(runners: fixture.runners) == .none)
    }

    @Test("A supported clone is reported with its build")
    func reportsSupportedClone() throws {
        let fixture = try Fixture()
        let version = SupportedRunners.all[0].bundleVersion
        try fixture.linkCurrent(to: fixture.makeClone(build: version))

        #expect(RunnerStore.state(runners: fixture.runners, verify: { _, _ in [] })
            == .cloned(build: version, supported: true))
    }

    // The launch path only reads the runner, so a clone the app never finished patching
    // has to be caught here rather than by a game failing its ownership check.
    @Test("A clone missing a file the app installs is reported as unpatched")
    func reportsUnpatchedClone() throws {
        let fixture = try Fixture()
        let version = SupportedRunners.all[0].bundleVersion
        try fixture.linkCurrent(to: fixture.makeClone(build: version))

        #expect(RunnerStore.state(runners: fixture.runners, verify: { _, _ in ["ntdll is stock"] })
            == .unpatched(build: version, problems: ["ntdll is stock"]))
    }

    // A clone made by an older release of the app stays on disk and keeps working,
    // so it is reported rather than treated as broken.
    @Test("A clone outside the allow list is reported as unsupported")
    func reportsUnsupportedClone() throws {
        let fixture = try Fixture()
        try fixture.linkCurrent(to: fixture.makeClone(build: "1.0.0.1"))

        #expect(RunnerStore.state(runners: fixture.runners) == .cloned(build: "1.0.0.1", supported: false))
    }

    // Nothing about this clone is visibly wrong, and it runs, so only the shape says
    // the launch path has no way to install the ntdll patch into it.
    @Test("A clone still inside an .app is reported as the older layout")
    func reportsBundleShapedClone() throws {
        let fixture = try Fixture()
        let version = SupportedRunners.all[0].bundleVersion
        try fixture.linkCurrent(to: fixture.makeClone(build: version, inBundle: true))

        #expect(RunnerStore.state(runners: fixture.runners) == .bundleShaped(build: version))
    }

    @Test("A link to a tree with no lib/wine is broken")
    func detectsIncompleteTree() throws {
        let fixture = try Fixture()
        try fixture.linkCurrent(to: fixture.makeClone(build: "27.0.0.40921", withWine: false))

        guard case .broken = RunnerStore.state(runners: fixture.runners) else {
            Issue.record("expected broken, got \(RunnerStore.state(runners: fixture.runners))")
            return
        }
    }

    @Test("A dangling link is broken")
    func detectsDanglingLink() throws {
        let fixture = try Fixture()
        try fixture.linkCurrent(to: "crossover-27.0.0.40921/nothing/here")

        guard case .broken = RunnerStore.state(runners: fixture.runners) else {
            Issue.record("expected broken for a dangling link")
            return
        }
    }

    // This is the case the trailing slash bug hid: with a directory URL, lstat
    // resolves through the link and a real clone looks like a plain directory.
    @Test("A directory in place of the link is broken, not mistaken for a clone")
    func detectsDirectoryInsteadOfLink() throws {
        let fixture = try Fixture()
        try FileManager.default.createDirectory(
            at: fixture.runners.appending(path: "current/lib/wine"), withIntermediateDirectories: true
        )

        guard case .broken(let detail) = RunnerStore.state(runners: fixture.runners) else {
            Issue.record("expected broken for a directory in place of the link")
            return
        }
        #expect(detail.contains("symlink"))
    }

    @Test("Clones are listed by version")
    func listsClones() throws {
        let fixture = try Fixture()
        _ = try fixture.makeClone(build: "27.0.0.40921")
        _ = try fixture.makeClone(build: "26.0.0.1")

        #expect(RunnerStore.clonedBuilds(in: fixture.runners) == ["26.0.0.1", "27.0.0.40921"])
    }
}
