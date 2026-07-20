import SwiftUI

/// Exact `@username` entry. Adding a tag stays exact-match only; the Plan 3
/// friends list is where you can filter people you've already connected with.
struct UserTagSheet: View {
    let onAdd: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                SereneTextField(title: "username", text: $username)
                Text("Enter the exact username of the person you want to tag.")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                PrimaryButton(title: "Tag", isLoading: isAdding) {
                    Task {
                        isAdding = true
                        await onAdd(username)
                        isAdding = false
                        dismiss()
                    }
                }
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
            }
            .padding(20)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Tag someone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
