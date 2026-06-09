import SwiftUI

/// One-time call to action: grant Full Disk Access so scans never trigger per-folder
/// permission prompts. Shown until the access is detected (or dismissed for the session).
struct PermissionBanner: View {
    @EnvironmentObject var model: AppModel
    @State private var dismissed = false

    var body: some View {
        if !model.permissions.hasFullDiskAccess && !dismissed {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Accordez l'Accès complet au disque — une seule fois")
                        .font(.callout.bold())
                    Text("Sans lui, macOS demande l'autorisation dossier par dossier. Avec lui, Spaceful analyse tout votre Mac sans aucune interruption.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(spacing: 6) {
                    Button {
                        model.permissions.openFullDiskAccessSettings()
                    } label: {
                        Label("Ouvrir les Réglages", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent)
                    HStack(spacing: 8) {
                        Button("J'ai accordé — revérifier") { model.permissions.refresh() }
                            .controlSize(.small)
                        Button("Plus tard") { dismissed = true }
                            .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .background(.orange.opacity(0.10))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.orange.opacity(0.35)), alignment: .bottom)
        }
    }
}
