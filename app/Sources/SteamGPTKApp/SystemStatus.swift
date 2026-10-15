// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
// Logic behind Status view

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum AppVersion {
    static let fallback = "0.1.0-dev"

    static var bundled: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallback
    }
}

struct StatusSnapshot: Sendable {
    var steam: SteamDeployment
    var steamRunning: Bool
    var updateBlocked: Bool
    var crossOver: [CrossOverInstall]
    var crossOverLicense: [String: CrossOverLicense.Status] = [:]
    var runner: RunnerState
    var payload: PayloadState
    var installedRunners: [RunnerBuild] = []
    var orphanedRunners: [String] = []
    var damagedRunners: [String] = []
    var gptkVersion: String? = nil
    var rosettaAvailable = false
    var cloudProfilesReady = false

    static func capture(bundledVersion: String) -> StatusSnapshot {
        let installs = CrossOverSource.discover()
        var licenses: [String: CrossOverLicense.Status] = [:]
        for install in installs where install.isUsable {
            licenses[install.id] = CrossOverLicense.check(crossOverRoot: install.crossOverRoot)
        }

        let runner = RunnerStore.state()

        return StatusSnapshot(
            steam: SteamBundle.deployment(bundledVersion: bundledVersion),
            steamRunning: SteamBundle.isRunning,
            updateBlocked: UpdateBlock.isPresent(),
            crossOver: installs,
            crossOverLicense: licenses,
            runner: runner,
            payload: PayloadInspector.inspect(
                build: runner.buildIdentifier.flatMap(SupportedRunners.build(id:))
            ),
            installedRunners: RunnerStore.installedBuilds(),
            orphanedRunners: RunnerStore.orphanedClones(),
            damagedRunners: RunnerStore.damagedClones(),
            gptkVersion: GPTKImport.version(in: FreeRuntime.root.appending(path: GPTKImport.relativePath)),
            rosettaAvailable: (try? Shell.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).succeeded) == true,
            cloudProfilesReady: FreeRuntime.cloudProfilesReady()
        )
    }
}

@MainActor
@Observable
final class SystemStatus {

    var selectedGPTKDMG: URL?
    var snapshot: StatusSnapshot?
    var isRefreshing = false
    var activity: String?
    var outcome: String?
    private(set) var failure: String?
    private(set) var failureRemedy: Remedy?

    private var runInFlight = false
    private var checkingLicense = false

    var isBusy: Bool { activity != nil || runInFlight || checkingLicense }
    var isIdle: Bool { !isBusy && !isRefreshing }

    enum Confirmation: Identifiable, Hashable {
        case replaceSteam
        case blockUpdates
        case installUnlicensed
        case toolUnlicensed
        case removeBuild
        case removeEverything

        var id: Self { self }
    }

    var pendingConfirmation: Confirmation?
    var generation = 0

    func beginRun(_ label: String) -> Int {
        activity = label
        AppLog.note("run begin: \(label)")
        return generation
    }

    func report(_ run: Int, _ label: String) {
        guard run == generation else { return }
        activity = label
        AppLog.note("run step: \(label)")
    }

    func endRun() {
        generation += 1
        activity = nil
        AppLog.note("run end\(failure == nil ? "" : " (failed)")")
    }

    private func record(_ error: Error) {
        setFailure(error)
        if let refusal = error as? WriteRefused {
            AppLog.note("run failed: cannot write \(refusal.path)")
        } else {
            AppLog.note("run failed: \(error.localizedDescription)")
        }
    }

    func setFailure(_ message: String) {
        failure = message
        failureRemedy = nil
    }

    func setFailure(_ error: Error) {
        let report = FailureReport([error])
        failure = report?.message
        failureRemedy = report?.remedy
    }

    func clearFailure() {
        failure = nil
        failureRemedy = nil
    }

    var usableCrossOver: CrossOverInstall? {
        snapshot?.crossOver.first(where: \.isUsable)
    }

    var usableCrossOvers: [CrossOverInstall] {
        snapshot?.crossOver.filter(\.isUsable) ?? []
    }

    var crossOverRowsOfferSetUp: Bool {
        let usable = usableCrossOvers
        guard usable.count > 1 else { return false }
        let installed = snapshot?.installedRunners ?? []
        return usable.contains { install in
            if case .supported(let build) = install.support { return !installed.contains(build) }
            return false
        }
    }

    struct AvailableBuild: Identifiable {
        let install: CrossOverInstall
        let build: RunnerBuild

        var id: String { build.id }
    }

    var repairSource: CrossOverInstall? {
        let current = snapshot?.runner.buildIdentifier
        return usableCrossOvers.first { install in
            if case .supported(let build) = install.support { return build.id == current }
            return false
        }
    }

    var setupSource: CrossOverInstall? { repairSource ?? usableCrossOver }

    var setupSourceIsDeployed: Bool {
        guard case .supported(let build)? = setupSource?.support else { return false }
        return snapshot?.installedRunners.contains(build) ?? false
    }

    var availableBuilds: [AvailableBuild] {
        let installed = snapshot?.installedRunners ?? []
        guard !installed.isEmpty else { return [] }
        return usableCrossOvers.compactMap { install in
            guard case .supported(let build) = install.support,
                  !installed.contains(build) else { return nil }
            return AvailableBuild(install: install, build: build)
        }
    }

    func checkLicense(for chosen: CrossOverInstall? = nil) async -> CrossOverLicense.Status? {
        guard let install = chosen ?? usableCrossOver else { return nil }
        let status = await Task.detached(priority: .userInitiated) {
            CrossOverLicense.check(crossOverRoot: install.crossOverRoot)
        }.value
        snapshot?.crossOverLicense[install.id] = status
        return status
    }

    enum Request {
        case install
        case compatibilityTool
    }

    nonisolated static func activationQuestion(
        _ request: Request, licensed: Bool?, runner: RunnerState
    ) -> Confirmation? {
        guard licensed == false else { return nil }
        switch request {
        case .install: return runner == RunnerState.none ? .installUnlicensed : nil
        case .compatibilityTool: return .toolUnlicensed
        }
    }

    func requestInstall() async {
        guard isIdle, maintenanceIsAllowed() else { return }
        if snapshot?.gptkVersion == nil, selectedGPTKDMG == nil {
            guard chooseGPTKFile() else { return }
        }
        await installIntoSteam()
    }

    func requestCompatibilityTool(
        from chosen: CrossOverInstall? = nil, replacingExisting: Bool = false
    ) async {
        await requestInstall()
    }

    private func maintenanceIsAllowed() -> Bool {
        guard !SteamBundle.isRunning else {
            setFailure("Quit Steam before installing or importing GPTK. Games and saves have not been changed.")
            return false
        }
        let active = PrefixStore.all(libraries: PrefixStore.libraries()).contains { PrefixStore.isInUse($0) }
        guard !active else {
            setFailure("Quit Windows games and Wine tools before continuing.")
            return false
        }
        return true
    }

    @discardableResult
    private func chooseGPTKFile() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "dmg")!]
        panel.message = "Choose Game Porting Toolkit 4 downloaded from Apple. Apple files are imported locally and are not included with SteamGPTK."
        panel.prompt = "Choose GPTK"
        guard panel.runModal() == .OK, let file = panel.url else { return false }
        selectedGPTKDMG = file
        return true
    }

    func importGPTK() async {
        guard isIdle, maintenanceIsAllowed(), chooseGPTKFile(), let dmg = selectedGPTKDMG else { return }
        await perform(from: "Preparing Wine for GPTK") { progress in
            try await FreeRunnerInstaller.prepare(report: progress, checkCanWrite: FreeRuntime.requireIdle)
            progress("Importing GPTK from your DMG")
            try await Task.detached(priority: .userInitiated) {
                try GPTKImport.importDMG(dmg, runner: FreeRuntime.root, checkCanWrite: FreeRuntime.requireIdle)
            }.value
            selectedGPTKDMG = nil
            return "GPTK imported locally. Previous renderer files were kept in a backup."
        }
    }

    private(set) var pendingRemoval: String?

    func requestBuildRemoval(_ build: String) {
        guard isIdle else { return }
        pendingRemoval = build
        pendingConfirmation = .removeBuild
    }

    func cancelBuildRemoval() {
        pendingRemoval = nil
    }

    func removePendingBuild() async {
        guard let build = pendingRemoval else { return }
        pendingRemoval = nil
        await perform(from: RunnerInstaller.removeStep) { _ in
            try await Task.detached(priority: .userInitiated) {
                try RunnerInstaller.removeClone(forBuild: build)
            }.value
            return "Removed build \(SupportedRunners.displayVersion(forID: build))."
        }
    }

    func switchRunner(to build: RunnerBuild) async {
        guard isIdle else { return }
        guard build.id != snapshot?.runner.buildIdentifier else { return }
        await perform(from: RunnerSetup.Phase.staging.label) { progress in
            let result = try await Task.detached(priority: .userInitiated) {
                try RunnerSetup.activate(build, report: { progress($0.label) })
            }.value
            return "Now using build \(result.build.displayVersion)."
        }
    }

    var chosenCrossOver: URL? { CrossOverSource.manualBundle }

    // Lets the user pick a copy of CrossOver the search did not find/auto-select
    func chooseCrossOver() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        panel.message = "Select a copy of CrossOver."
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)

        guard panel.runModal() == .OK, let picked = panel.url else { return }

        clearFailure()
        outcome = nil

        guard CrossOverSource.looksLikeCrossOver(picked) else {
            setFailure("\(picked.lastPathComponent) is not a valid copy of CrossOver.")
            AppLog.note("crossOver choice refused: \(picked.path(percentEncoded: false))")
            return
        }

        CrossOverSource.manualBundle = picked
        AppLog.note("crossOver choice: \(picked.path(percentEncoded: false))")
        await refresh()
    }

    func clearCrossOverChoice() async {
        clearFailure()
        outcome = nil
        CrossOverSource.manualBundle = nil
        AppLog.note("crossOver choice cleared")
        await refresh()
    }

    private func runnerOutcome(_ result: RunnerSetup.Outcome) -> String {
        result.stagedNothing ? "Compatibility tool is already set up." : "Compatibility tool ready."
    }

    func perform(
        from first: String,
        _ body: (_ progress: @escaping @Sendable (String) -> Void) async throws -> String?
    ) async {
        guard !runInFlight else {
            AppLog.note("run refused: '\(first)' overlaps a run already in flight")
            return
        }
        runInFlight = true
        defer { runInFlight = false }

        clearFailure()
        outcome = nil
        let run = beginRun(first)
        defer { endRun() }

        do {
            outcome = try await body { label in
                Task { @MainActor in self.report(run, label) }
            }
        } catch {
            record(error)
        }

        await refresh()
    }

    private func setUpRunner(from install: CrossOverInstall?, replacingExisting: Bool = false) async {
        guard let install else {
            setFailure("No supported copy of CrossOver found.")
            AppLog.note("run refused: no supported CrossOver")
            outcome = nil
            return
        }

        await perform(from: RunnerSetup.Phase.cloning.label) { progress in
            let result = try await Task.detached(priority: .userInitiated) {
                try RunnerSetup.run(from: install, replacingExisting: replacingExisting) {
                    progress($0.label)
                }
            }.value

            return runnerOutcome(result)
        }
    }

    func fetchValveBinaries() async {
        await perform(from: ValveFetcher.Phase.verifying.label) { progress in
            let result = try await ValveFetcher.run { progress($0.label) }
            return result.wroteNothing ? nil : "Downloaded missing components."
        }
    }

    private static let restartHint = "Steam was stopped, so start it again."

    private static let toolNotActivated =
        "The compatibility tool was not set up because CrossOver is not activated."

    func installIntoSteam() async {
        guard maintenanceIsAllowed() else { return }
        let dmg = selectedGPTKDMG
        await perform(from: "Preparing Wine 11") { progress in
            guard (try? Shell.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).succeeded) == true else {
                throw StepFailure(step: "Check Rosetta", detail: "Install Rosetta 2, then try again: softwareupdate --install-rosetta")
            }
            try LegacyInstallation.prepare(home: SupportPaths.home, checkCanWrite: FreeRuntime.requireIdle)
            try await FreeRunnerInstaller.prepare(report: progress, checkCanWrite: FreeRuntime.requireIdle)
            if let dmg {
                progress("Importing your GPTK DMG")
                try await Task.detached(priority: .userInitiated) {
                    try GPTKImport.importDMG(dmg, runner: FreeRuntime.root, checkCanWrite: FreeRuntime.requireIdle)
                }.value
            }
            guard GPTKImport.version(in: FreeRuntime.root.appending(path: GPTKImport.relativePath)) != nil else {
                throw StepFailure(step: "Check GPTK", detail: "Import a GPTK 4 DMG downloaded from Apple first.")
            }
            progress("Installing Steam integration")
            _ = try await Task.detached(priority: .userInitiated) {
                try FreeRuntime.requireIdle()
                // Validate the patch before modifying Steam.
                _ = try FreeNtdllPatch.bundled().apply(to: Data(contentsOf: FreeRuntime.root.appending(path: "lib/wine/x86_64-windows/ntdll.dll")))
                return try SteamInstaller.run(stopClient: { _, _ in
                    try FreeRuntime.requireIdle()
                    return false
                }, report: { progress($0.label) })
            }.value
            progress("Configuring Wine and Steam Cloud paths")
            try await Task.detached(priority: .userInitiated) {
                try FreeRuntime.requireIdle()
                try FreeRunnerInstaller.configure(root: FreeRuntime.root, bridge: SupportPaths.bridge,
                    payload: InstallPayload.root(), tool: SupportPaths.Steam.compatTool)
                try FreeSteamSignature.installIfNeeded()
                try LegacyInstallation.migrate(home: SupportPaths.home, checkCanWrite: FreeRuntime.requireIdle)
            }.value
            progress("Verifying Valve components")
            _ = try await ValveFetcher.run { progress($0.label) }
            selectedGPTKDMG = nil
            return "Wine / GPTK is installed. Start Steam to play. Existing game prefixes and saves were kept."
        }
    }

    func setUpdateBlock(_ blocked: Bool) async {
        await perform(from: blocked ? "Blocking Steam client updates"
                                    : "Allowing Steam client updates") { _ in
            if blocked {
                try UpdateBlock.write()
                return "Steam client updates are blocked."
            }

            try UpdateBlock.remove()
            return "Steam client updates are allowed."
        }
    }

    func repairSteam() async {
        await perform(from: RepairPhase.checking.label) { progress in
            let result = try await SteamRepair.run { progress($0.label) }

            var parts = ["Steam restored to its original state."]
            if result.stoppedClient { parts.append(Self.restartHint) }
            return parts.joined(separator: " ")
        }
    }

    func removeEverything() async {
        await perform(from: UninstallPhase.stoppingClient.label) { progress in
            let result = try await Uninstall.run { progress($0.label) }

            return result.restoredValveSignature
                ? "SteamGPTK has been removed."
                : "SteamGPTK has been removed. Steam needs to be redownloaded. "
                    + "Please run Repair Steam again once you are online."
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let version = AppVersion.bundled
        let captured = await Task.detached(priority: .userInitiated) {
            StatusSnapshot.capture(bundledVersion: version)
        }.value
        snapshot = captured
        AppLog.note(captured)
        await measureRunnerSizes()
    }

    private(set) var runnerSizes: [String: Int64] = [:]

    func measureRunnerSizes() async {
        let known = Set(runnerSizes.keys)
        let present = await Task.detached(priority: .utility) {
            Set(RunnerStore.clonedBuilds())
        }.value

        for stale in known.subtracting(present) { runnerSizes[stale] = nil }

        for build in present.subtracting(known) {
            runnerSizes[build] = await Task.detached(priority: .utility) {
                RunnerStore.cloneSize(forBuild: build)
            }.value
        }
    }
}
