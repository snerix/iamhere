import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppEnvironment.self) private var environment
    @State private var launchAtLoginError: String?
    @FocusState private var refreshFieldFocused: RefreshField?

    enum RefreshField: Hashable {
        case active
        case idle
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle(String(localized: "Launch at login"), isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { updateLaunchAtLogin($0) }
                ))

                if let err = launchAtLoginError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                RefreshIntervalRow(
                    title: String(localized: "Screen awake"),
                    value: $settings.activeRefreshIntervalValue,
                    unit: $settings.activeRefreshIntervalUnit,
                    focus: $refreshFieldFocused,
                    field: .active
                )

                RefreshIntervalRow(
                    title: String(localized: "Display asleep"),
                    value: $settings.idleRefreshIntervalValue,
                    unit: $settings.idleRefreshIntervalUnit,
                    focus: $refreshFieldFocused,
                    field: .idle
                )
            } header: {
                Text(String(localized: "IP refresh interval"))
            } footer: {
                Text(String(localized: "Network changes still trigger an immediate refresh. These intervals control the background polling loop."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            settings.launchAtLogin = environment.launchAtLogin.isEnabled
        }
        .simultaneousGesture(
            TapGesture()
                .onEnded { refreshFieldFocused = nil }
        )
    }

    private func updateLaunchAtLogin(_ newValue: Bool) {
        do {
            try environment.launchAtLogin.setEnabled(newValue)
            settings.launchAtLogin = newValue
            launchAtLoginError = nil
        } catch {
            settings.launchAtLogin = environment.launchAtLogin.isEnabled
            launchAtLoginError = (error as NSError).localizedDescription
            Log.launch.error("Toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

}

private struct RefreshIntervalRow: View {
    let title: String
    @Binding var value: Int
    @Binding var unit: RefreshIntervalUnit
    var focus: FocusState<GeneralSettingsView.RefreshField?>.Binding
    let field: GeneralSettingsView.RefreshField

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .focused(focus, equals: field)

                Picker("", selection: $unit) {
                    ForEach(RefreshIntervalUnit.allCases) { unit in
                        Text(unit.localizedTitle).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }
}
