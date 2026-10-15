// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
import Sparkle

@MainActor
final class AppUpdater {

    private let controller: SPUStandardUpdaterController

    init() {
        // Fork builds never consume upstream CrossOver-only app updates.
        let scheduling = false
        controller = SPUStandardUpdaterController(
            startingUpdater: scheduling,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func check() {
        // Updates are distributed from the SteamGPTK fork's releases.
    }
}
