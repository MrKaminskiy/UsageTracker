import SwiftUI
import AppKit

/// Validation state for API keys
enum KeyValidationState {
    case idle
    case checking
    case valid
    case invalid(String)
}

/// API key entry UI with auto-validation.
struct APIKeyInput: View {
    let placeholder: String
    let hint: String
    let linkTitle: String
    let linkURL: URL?
    @Binding var key: String
    @Binding var saved: Bool
    let onSave: () -> Void
    let validateKey: (String) async -> (Bool, String?)

    @State private var validationState: KeyValidationState = .idle
    @State private var validationTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                SecureField(placeholder, text: $key)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .onChange(of: key) { _, newValue in
                        saved = false
                        validateKeyDebounced(newValue)
                    }

                if case .checking = validationState {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 44, height: 24)
                } else {
                    Button(buttonLabel) {
                        onSave()
                    }
                    .disabled(key.isEmpty || !isValid)
                    .buttonStyle(.borderedProminent)
                    .tint(buttonTint)
                    .controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                if case .invalid(let message) = validationState {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                } else if case .valid = validationState {
                    Text("Key valid")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                } else {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let linkURL = linkURL {
                        Link(linkTitle, destination: linkURL)
                            .font(.system(size: 10))
                    }
                }
            }
        }
    }

    private var borderColor: Color {
        switch validationState {
        case .invalid: return Color.red.opacity(0.8)
        case .valid: return Color.green.opacity(0.8)
        default: return Color.gray.opacity(0.3)
        }
    }

    private var isValid: Bool {
        if case .invalid = validationState { return false }
        return true
    }

    private var buttonLabel: String {
        if saved { return "✓" }
        if case .valid = validationState { return "Save" }
        return "Save"
    }

    private var buttonTint: Color {
        if saved { return .green }
        if case .valid = validationState { return .blue }
        return .gray
    }

    private func validateKeyDebounced(_ newKey: String) {
        validationTask?.cancel()

        guard !newKey.isEmpty else {
            validationState = .idle
            return
        }

        validationTask = Task {
            // Debounce - wait before validating
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run { validationState = .checking }

            let (isValid, errorMessage) = await validateKey(newKey)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isValid {
                    validationState = .valid
                } else {
                    validationState = .invalid(errorMessage ?? "Invalid key")
                }
            }
        }
    }
}

/// Provider toggle row with icon and hint text.
struct ProviderToggle: View {
    let icon: String
    let name: String
    let hint: String
    let id: String
    @ObservedObject var appState: AppState

    var body: some View {
        HStack {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(Color.gray.opacity(0.5))
                .frame(width: 16)

            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { appState.config.isProviderEnabled(id) },
                set: { appState.updateProviderEnabled(id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}

/// Provider row that groups toggle and optional API key input.
struct ProviderSettingsRow: View {
    let provider: ProviderSettingsItem
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProviderToggle(
                icon: provider.icon,
                name: provider.name,
                hint: provider.hint,
                id: provider.id,
                appState: appState
            )

            if let keyConfig = provider.keyConfig {
                APIKeyInput(
                    placeholder: keyConfig.placeholder,
                    hint: keyConfig.hint,
                    linkTitle: keyConfig.linkTitle,
                    linkURL: keyConfig.linkURL,
                    key: keyConfig.key,
                    saved: keyConfig.saved,
                    onSave: keyConfig.onSave,
                    validateKey: keyConfig.validateKey
                )
                .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Provider metadata for the settings UI.
struct ProviderSettingsItem: Identifiable {
    let id: String
    let icon: String
    let name: String
    let hint: String
    let keyConfig: ProviderKeyConfig?
}

/// API key settings payload for a provider.
struct ProviderKeyConfig {
    let placeholder: String
    let hint: String
    let linkTitle: String
    let linkURL: URL?
    let key: Binding<String>
    let saved: Binding<Bool>
    let onSave: () -> Void
    let validateKey: (String) async -> (Bool, String?)
}

/// Drop delegate for provider reordering
struct ProviderDropDelegate: DropDelegate {
    let item: String
    let appState: AppState

    func performDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = info.itemProviders(for: [.text]).first else { return }

        draggedItem.loadObject(ofClass: NSString.self) { reading, _ in
            guard let draggedId = reading as? String, draggedId != item else { return }

            DispatchQueue.main.async {
                var order = appState.config.providerOrder
                guard let fromIndex = order.firstIndex(of: draggedId),
                      let toIndex = order.firstIndex(of: item) else { return }

                withAnimation {
                    order.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                    appState.updateProviderOrder(order)
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}
