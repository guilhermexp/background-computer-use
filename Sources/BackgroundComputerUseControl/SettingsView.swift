import AppKit
import BackgroundComputerUseControlShared
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ControlViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BCU Control")
                .font(.title2.bold())
            Text("Apps permitidos e negados por assinatura de código verificada.")
                .foregroundStyle(.secondary)
            Toggle(
                "Mostrar cartão de atividades",
                isOn: Binding(
                    get: { model.activityCardEnabled },
                    set: { model.setActivityCardEnabled($0) }
                )
            )
            .accessibilityHint("Quando desativado, o cartão flutuante não aparece, mas o histórico de atividades continua sendo registrado.")
            Toggle(
                "Continuar tarefa com a tela bloqueada",
                isOn: Binding(
                    get: { model.lockedUseOptIn },
                    set: { model.setLockedUseOptIn($0) }
                )
            )
            .accessibilityHint("Requer broker e plug-in qualificados; qualquer entrada local religa a tela bloqueada.")
            GroupBox("Permissões do macOS") {
                VStack(alignment: .leading, spacing: 10) {
                    permissionRow(
                        pane: .accessibility,
                        granted: model.permissionSnapshot.accessibilityGranted
                    )
                    permissionRow(
                        pane: .screenRecording,
                        granted: model.permissionSnapshot.screenRecordingGranted
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.policies.isEmpty {
                ContentUnavailableView(
                    "Nenhuma política salva",
                    systemImage: "checkmark.shield",
                    description: Text("Novos apps sempre pedem autorização explícita.")
                )
            } else {
                List(model.policies) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.identity.bundleID)
                            Text("Team ID: \(row.identity.teamID) • \(row.decision.rawValue)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Revogar") { model.revoke(row.identity) }
                            .accessibilityLabel("Revogar acesso de \(row.identity.bundleID)")
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 380)
        .accessibilityElement(children: .contain)
    }

    private func permissionRow(pane: ControlPermissionPane, granted: Bool) -> some View {
        HStack {
            Label(
                pane.title,
                systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            Spacer()
            Text(granted ? "Concedida" : "Necessária")
                .foregroundStyle(granted ? .green : .orange)
            if granted == false, let url = pane.settingsURL {
                Button("Abrir Ajustes") {
                    NSWorkspace.shared.open(url)
                }
                .accessibilityLabel("Abrir ajustes de \(pane.title)")
            }
        }
    }
}
