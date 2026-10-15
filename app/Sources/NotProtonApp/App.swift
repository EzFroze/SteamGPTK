// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
// Self-explanatory

import SwiftUI
import Darwin

@main
enum SteamGPTKEntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--check-resources") {
            do {
                try PackagedResourceCheck.run()
                print("Packaged resources OK")
            } catch {
                FileHandle.standardError.write(Data(("Resource check failed: \(error.localizedDescription)\n").utf8))
                exit(1)
            }
            return
        }
        NotProtonApp.main()
    }
}

struct NotProtonApp: App {

    @State private var status = SystemStatus()
    @State private var prefixes = PrefixesModel()
    @State private var pane: Pane = .status

    init() {
        AppLog.start()
    }

    var body: some Scene {
        Window("SteamGPTK · Wine / GPTK", id: "main") {
            RootView(pane: $pane)
                .environment(status)
                .environment(prefixes)
                .frame(minWidth: 720, minHeight: 460)
                .onChange(of: pane) { prefixes.forgetOutcome() }
        }
        .defaultSize(width: 980, height: 860)
        .commands { menus }
    }

    @CommandsBuilder
    private var menus: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .sidebar) {
            Button("Status") { pane = .status }
                .keyboardShortcut("1", modifiers: .command)
            Button("Prefixes") { pane = .prefixes }
                .keyboardShortcut("2", modifiers: .command)
            Button("Prefix Backups") { pane = .backups }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Refresh") {
                Task {
                    switch pane {
                    case .status: await status.refresh()
                    case .prefixes, .backups: await prefixes.load()
                    }
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(pane == .status ? !status.isIdle : prefixes.isLoading)

            Divider()
        }

        CommandMenu("Setup") {
            Button("Install") { Task { await status.requestInstall() } }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(!status.isIdle || prefixes.isBusy)

            Button("Set Up Compatibility Tool") { Task { await status.requestCompatibilityTool() } }
                .disabled(!status.isIdle || prefixes.isBusy || status.snapshot?.steamRunning == true)

            Button("Import GPTK DMG…") { Task { await status.importGPTK() } }
                .disabled(!status.isIdle || prefixes.isBusy || status.snapshot?.steamRunning == true)

            Button("Fetch Valve Binaries") { Task { await status.fetchValveBinaries() } }
                .disabled(!status.isIdle || prefixes.isBusy)

            Divider()

            updateBlockCommand

            Button("Repair Steam") { status.pendingConfirmation = .replaceSteam }
                .disabled(!status.isIdle || prefixes.isBusy)

            Divider()

            Button("Reveal Log in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([AppLog.file])
            }
        }

        prefixMenu
    }

    @CommandsBuilder
    private var prefixMenu: some Commands {
        CommandMenu("Prefix") {
            Button("Run Program…") {
                if let prefix = prefixTarget { prefixes.chooseExecutable(for: prefix) }
            }
            .disabled(prefixTarget == nil)

            Divider()

            ForEach(WineTool.allCases, id: \.self) { tool in
                Button(tool.label) {
                    if let prefix = prefixes.selectedPrefix { prefixes.open(tool, for: prefix) }
                }
                .disabled(prefixTarget == nil)
            }

            Divider()

            Button("Reveal in Finder") {
                if let prefix = prefixes.selectedPrefix { prefixes.reveal(prefix) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(prefixes.selectedPrefix == nil)

            Divider()

            Button(PrefixPrompt.backUpButton(selectionTargets)) {
                if !selectionTargets.isEmpty {
                    prefixes.pendingConfirmation = .backUp(selectionTargets)
                }
            }
            .disabled(selectionTargets.isEmpty)

            Button(PrefixPrompt.rebuildButton(selectionTargets)) {
                if !selectionTargets.isEmpty {
                    prefixes.pendingConfirmation = .rebuild(selectionTargets)
                }
            }
            .disabled(selectionTargets.isEmpty)

            Button(PrefixPrompt.deleteButton(selectionTargets)) {
                if !selectionTargets.isEmpty {
                    prefixes.pendingConfirmation = .delete(selectionTargets)
                }
            }
            .disabled(selectionTargets.isEmpty)
        }
    }

    private var prefixTarget: WinePrefix? {
        prefixes.isBusy || status.isBusy ? nil : prefixes.selectedPrefix
    }

    private var selectionTargets: [WinePrefix] {
        prefixes.isBusy || status.isBusy ? [] : prefixes.selectedPrefixes
    }

    @ViewBuilder
    private var updateBlockCommand: some View {
        if status.snapshot?.updateBlocked == true {
            Button("Allow Client Updates") { Task { await status.setUpdateBlock(false) } }
                .disabled(!status.isIdle || prefixes.isBusy)
        } else {
            Button("Block Client Updates") { status.pendingConfirmation = .blockUpdates }
                .disabled(!status.isIdle || status.snapshot == nil)
        }
    }
}
