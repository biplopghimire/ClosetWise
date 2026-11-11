import SwiftUI

/// Settings → Gemini API key: paste your own key; it's checked with Google, then kept in the Keychain.
struct GeminiKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var working = false
    @State private var error: String?
    @State private var saved = false
    @State private var confirmRemove = false
    private var key: GeminiKey { GeminiKey.shared }

    var body: some View {
        Form {
            Section {
                if let hint = key.hint {
                    LabeledContent("Current key", value: hint)
                }
                SecureField(key.isSet ? "Paste a new key" : "Paste your key", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await save() } }
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(working ? "Checking…" : "Save key")
                        if working { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(working || input.trimmingCharacters(in: .whitespaces).isEmpty)
            } footer: {
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                } else if saved {
                    Label("Saved. AI reads now use your key.", systemImage: "checkmark.circle").foregroundStyle(Theme.primary)
                } else if !key.isSet {
                    Text("AI features (reading items from photos, purchase verdicts, outfit logging) need a key.")
                }
            }

            Section("Get a free key") {
                Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                    Label("Open Google AI Studio", systemImage: "arrow.up.right.square")
                }
                Text("Sign in with a Google account, tap **Create API key**, copy it and paste it above. Make a new key just for ClosetWise.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Text("Your key stays in this phone's Keychain. It's sent only to ClosetWise's server, which passes it to Google for each AI read and never stores it.")
                    .font(.footnote).foregroundStyle(.secondary)
                if key.isFromApp {
                    Button("Remove key", role: .destructive) { confirmRemove = true }
                }
            }
        }
        .navigationTitle("Gemini API key")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove your Gemini key?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) { key.remove(); saved = false }
        } message: {
            Text("AI features stop working until you add a key again.")
        }
    }

    private func save() async {
        guard !working, !input.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        error = nil
        saved = false
        defer { working = false }
        do {
            try await key.save(input)
            input = ""
            saved = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
