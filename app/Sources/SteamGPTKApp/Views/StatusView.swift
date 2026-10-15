// SteamGPTK fork modifications, 2026-10-15. Existing component licenses apply.
// 'Status' view, see SystemStatus for actual logic

import SwiftUI

enum StatusTone: Sendable {
    case ok, info, warning, bad, neutral

    var symbol: String {
        switch self {
        case .ok: "circle.fill"
        case .info: "circle"
        case .warning: "circle.fill"
        case .bad: "circle.fill"
        case .neutral: "circle"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .info: .secondary
        case .warning: .orange
        case .bad: .red
        case .neutral: .secondary
        }
    }
}

struct StatusAction {
    let label: String
    var isProminent = false
    var role: ButtonRole?
    var help: String?
    var isEnabled = true
    let perform: () -> Void
}

enum StatusMetrics {
    static let symbolWidth: CGFloat = 10
    static let symbolSpacing: CGFloat = 8
    static var textInset: CGFloat { symbolWidth + symbolSpacing }
}

struct StatusRow: View {

    @Environment(\.colorSchemeContrast) private var contrast

    let title: String
    var value: String?

    var tone: StatusTone?
    var detail: String?
    var secondaryAction: StatusAction?
    var action: StatusAction?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: StatusMetrics.symbolSpacing) {
                if let tone {
                    Image(systemName: tone.symbol)
                        .font(.system(size: 8))
                        .foregroundStyle(tone.color)
                        .frame(width: StatusMetrics.symbolWidth)
                        .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: StatusMetrics.symbolWidth, height: 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let value {
                        Text(value)
                            .foregroundStyle(.secondary)
                    }
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(contrast == .increased ? .secondary : .tertiary)
                            .textSelection(.enabled)
                    }
                }
            }

            if secondaryAction != nil || action != nil {
                Spacer(minLength: 12)
            }
            if let secondaryAction {
                button(secondaryAction)
                    .disabled(!secondaryAction.isEnabled)
                    .help(secondaryAction.help ?? "")
                    .accessibilityLabel("\(secondaryAction.label), \(title)")
                    .padding(.trailing, 8)
            }
            if let action {
                button(action)
                    .disabled(!action.isEnabled)
                    .help(action.help ?? "")
                    .accessibilityLabel("\(action.label), \(title)")
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func button(_ action: StatusAction) -> some View {
        if action.isProminent {
            Button(action.label, role: action.role, action: action.perform)
                .buttonStyle(.borderedProminent)
        } else {
            Button(action.label, role: action.role, action: action.perform)
                .buttonStyle(.bordered)
        }
    }
}

struct StatusView: View {
    @Environment(SystemStatus.self) private var status
    @Environment(PrefixesModel.self) private var prefixes

    private var canInstall: Bool { status.isIdle && !prefixes.isBusy && status.snapshot?.steamRunning == false }

    var body: some View {
        Group {
            if let snapshot = status.snapshot { form(snapshot) }
            else { ProgressView("Checking Wine / GPTK").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .navigationTitle("Wine / GPTK")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await status.refresh() } }
                    .disabled(!status.isIdle)
            }
        }
        .task { if status.snapshot == nil { await status.refresh() } }
        .confirmationDialog("Block Steam client updates?", isPresented: asking(.blockUpdates), titleVisibility: .visible) {
            Button("Block Updates", role: .destructive) { Task { await status.setUpdateBlock(true) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Steam updates can change the functions SteamGPTK integrates with. You can enable updates again here.") }
        .confirmationDialog("Restore the original Steam application?", isPresented: asking(.replaceSteam), titleVisibility: .visible) {
            Button("Restore Steam", role: .destructive) { Task { await status.repairSteam() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes the SteamGPTK integration from Steam. Game installations and saves are kept.") }
        .confirmationDialog("Remove SteamGPTK and its runtime?", isPresented: asking(.removeEverything), titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await status.removeEverything() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Wine, imported GPTK, support components and SteamGPTK backups are removed. Steam game prefixes and their saves are kept.") }
    }

    private func asking(_ value: SystemStatus.Confirmation) -> Binding<Bool> {
        Binding(get: { status.pendingConfirmation == value }, set: { if !$0 { status.pendingConfirmation = nil } })
    }

    private func form(_ snapshot: StatusSnapshot) -> some View {
        Form {
            if let failure = status.failure {
                StatusRow(title: "Could not finish", value: failure, tone: .bad)
            } else if let outcome = status.outcome {
                StatusRow(title: "Done", value: outcome, tone: .ok)
            }
            if let activity = status.activity {
                HStack { ProgressView().controlSize(.small); Text(activity).foregroundStyle(.secondary) }
            }
            Section("Steam") {
                steamRow(snapshot)
                if snapshot.steamRunning {
                    StatusRow(title: "Steam is running", value: "Close Steam before installing or importing GPTK.", tone: .info)
                }
                Toggle(isOn: Binding(get: { snapshot.updateBlocked }, set: { blocked in
                    if blocked { status.pendingConfirmation = .blockUpdates }
                    else { Task { await status.setUpdateBlock(false) } }
                })) {
                    VStack(alignment: .leading) {
                        Text("Block Steam client updates").font(.headline)
                        Text("Steam updates may require an updated SteamGPTK build.").foregroundStyle(.secondary)
                    }.padding(.leading, StatusMetrics.textInset)
                }.disabled(!status.isIdle)
            }
            Section {
                wineRow(snapshot.runner)
                StatusRow(title: "Rosetta 2", value: snapshot.rosettaAvailable ? "Ready." : "Install Rosetta 2 to run Windows games.",
                          tone: snapshot.rosettaAvailable ? .ok : .warning)
                StatusRow(title: "Apple GPTK / D3DMetal",
                          value: snapshot.gptkVersion.map { "Version \($0), imported locally." } ?? "Choose a GPTK 4 DMG downloaded from Apple.",
                          tone: snapshot.gptkVersion == nil ? .neutral : .ok,
                          detail: status.selectedGPTKDMG?.lastPathComponent,
                          action: StatusAction(label: snapshot.gptkVersion == nil ? "Choose DMG…" : "Import Another…",
                                               isEnabled: canInstall) { Task { await status.importGPTK() } })
                Link("Download Game Porting Toolkit from Apple", destination: GPTKImport.downloadURL)
                    .padding(.leading, StatusMetrics.textInset)
            } header: { Text("Windows Games") }
              footer: { Text("Wine 11 runs Windows programs through Rosetta. GPTK translates DirectX to Metal. Apple files are supplied by you and are not included in SteamGPTK.") }
            Section("SteamGPTK Components") {
                StatusRow(title: "Steam bridge", value: snapshot.payload.isComplete ? "Ready." : "Installation or repair required.",
                          tone: snapshot.payload.isComplete ? .ok : .warning,
                          detail: componentDetail(snapshot.payload))
                StatusRow(title: "Steam Cloud paths", value: snapshot.cloudProfilesReady ? "Unified Windows profile support installed." : "Install the updated launch script.",
                          tone: snapshot.cloudProfilesReady ? .ok : .warning,
                          detail: "Steam handles uploads and downloads. This checks the launch script, not cloud sync status.")
            }
            Section("Maintenance") {
                StatusRow(title: "Wine / GPTK integration", value: "Install or repair the Steam bridge and runtime. Existing game prefixes and saves are kept.",
                          action: StatusAction(label: "Install / Repair", isProminent: true, isEnabled: canInstall) {
                              Task { await status.requestInstall() }
                          })
                StatusRow(title: "Original Steam", value: "Restore Steam without the SteamGPTK integration.",
                          action: StatusAction(label: "Restore…", role: .destructive, isEnabled: canInstall) { status.pendingConfirmation = .replaceSteam })
                StatusRow(title: "Remove SteamGPTK", value: "Remove the runtime and imported GPTK from this account.",
                          action: StatusAction(label: "Remove…", role: .destructive, isEnabled: canInstall) { status.pendingConfirmation = .removeEverything })
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func steamRow(_ snapshot: StatusSnapshot) -> StatusRow {
        let action = StatusAction(label: "Install / Repair", isEnabled: canInstall) { Task { await status.requestInstall() } }
        switch snapshot.steam {
        case .steamMissing: return StatusRow(title: "SteamGPTK", value: "Install Steam for macOS first.", tone: .warning)
        case .notInstalled: return StatusRow(title: "SteamGPTK", value: "Not installed into Steam.", tone: .neutral, action: action)
        case .installed(let version):
            return StatusRow(title: "SteamGPTK", value: "Installed" + (version.map { " (\($0))" } ?? "") + ".",
                             tone: snapshot.payload.isComplete ? .ok : .warning)
        case .outdated: return StatusRow(title: "SteamGPTK", value: "Installed version differs from this application.", tone: .warning, action: action)
        case .foreign: return StatusRow(title: "SteamGPTK", value: "Steam uses another injected library.", tone: .warning)
        }
    }

    private func wineRow(_ state: RunnerState) -> StatusRow {
        switch state {
        case .cloned(let build, let supported) where build == FreeRuntime.id:
            return StatusRow(title: "Wine 11 (Sikarugir)", value: supported ? "Ready." : "Needs repair.", tone: supported ? .ok : .warning)
        case .unpatched(let build, let problems) where build == FreeRuntime.id:
            return StatusRow(title: "Wine 11 (Sikarugir)", value: "Needs repair.", tone: .warning, detail: problems.joined(separator: "; "))
        case .none: return StatusRow(title: "Wine 11 (Sikarugir)", value: "Not installed.", tone: .neutral)
        case .broken(let detail): return StatusRow(title: "Wine 11 (Sikarugir)", value: "Needs repair.", tone: .warning, detail: detail)
        default: return StatusRow(title: "Wine 11 (Sikarugir)", value: "Another runtime is selected. Install to use Wine / GPTK.", tone: .info)
        }
    }

    private func componentDetail(_ payload: PayloadState) -> String? {
        if let problem = payload.manifestProblem { return problem }
        if !payload.missing.isEmpty { return "Missing: " + payload.missing.map(\.path).joined(separator: ", ") }
        return nil
    }
}
