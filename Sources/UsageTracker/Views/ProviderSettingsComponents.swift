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
                // Label hidden: inside a grouped Form a titled field renders its title as a row label.
                SecureField(placeholder, text: $key, prompt: Text(placeholder))
                    .labelsHidden()
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
                    Button {
                        onSave()
                    } label: {
                        if saved {
                            Label("Saved", systemImage: "checkmark")
                        } else {
                            Text("Save")
                        }
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
                        .font(.system(size: 11))
                        .foregroundStyle(UsageLevel.critical.color)
                } else if case .valid = validationState {
                    Text("Key valid")
                        .font(.system(size: 11))
                        .foregroundStyle(UsageLevel.normal.color)
                } else {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let linkURL = linkURL {
                        Link(linkTitle, destination: linkURL)
                            .font(.system(size: 11))
                    }
                }
            }
        }
    }

    private var borderColor: Color {
        switch validationState {
        case .invalid: return UsageLevel.critical.color.opacity(0.8)
        case .valid: return UsageLevel.normal.color.opacity(0.8)
        default: return Color.primary.opacity(0.15)
        }
    }

    private var isValid: Bool {
        if case .invalid = validationState { return false }
        return true
    }

    private var buttonTint: Color {
        if saved { return UsageLevel.normal.color }
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
