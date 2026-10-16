// SteamGPTK fork modifications, 2026-10-16. Existing component licenses apply.
import Foundation
import Testing
@testable import SteamGPTKApp

@Suite("Wine game session lifetime")
struct GameSessionTests {
    @Test("Real games are detected, wrappers are ignored, and a closed game ends its session")
    func sessionProcessDetection() throws {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let result = try Shell.run("/bin/sh", [repo.appending(path: "dylib/tests/gamecheck.sh").path,
                                              repo.appending(path: "dylib/feats/compat_run.sh").path])
        #expect(result.status == 0, "\(result.stdout)\n\(result.stderr)")
    }
}
