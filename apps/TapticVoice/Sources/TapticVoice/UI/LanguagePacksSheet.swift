import SwiftUI
import TapticCore

/// Modal sheet displaying built-in tiny voices and downloadable offline Piper TTS packs.
public struct LanguagePacksSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.t(.packsSheetTitle))
                        .font(.system(size: 16, weight: .bold))
                    Text(state.t(.packsSheetSubtitle))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(state.t(.doneButton)) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            if let err = state.packManager.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            List {
                Section(state.t(.builtInSectionTitle)) {
                    ForEach(LanguagePackManager.catalog.filter { $0.isBuiltIn }) { pack in
                        packRow(pack)
                    }
                }

                Section(state.t(.downloadableSectionTitle)) {
                    ForEach(LanguagePackManager.catalog.filter { !$0.isBuiltIn }) { pack in
                        packRow(pack)
                    }
                }
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(18)
        .frame(width: 520, height: 480)
        .environment(\.layoutDirection, state.uiLanguage.layoutDirection)
    }

    @ViewBuilder
    private func packRow(_ pack: VoicePack) -> some View {
        let isInstalled = state.packManager.installedPackIDs.contains(pack.id)
        let progress = state.packManager.activeDownloads[pack.id]

        HStack(spacing: 10) {
            Text(pack.nativeFlag)
                .font(.system(size: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.localizedTitle(for: state.uiLanguage))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(String(format: "%.1f MB  •  %@", pack.downloadSizeMB, pack.id))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if pack.isBuiltIn {
                badge(state.t(.alwaysAvailableBadge), color: .green)
            } else if let progress {
                HStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .frame(width: 80)
                    Button {
                        state.packManager.cancelDownload(packId: pack.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else if isInstalled {
                HStack(spacing: 8) {
                    badge(state.t(.installedBadge), color: .blue)
                    Button(state.t(.removeButton)) {
                        if state.selectedVoiceMode == pack.id {
                            state.selectedVoiceMode = "auto"
                        }
                        state.packManager.removePack(pack)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button(state.t(.downloadButton)) {
                    state.packManager.downloadPack(pack)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}
