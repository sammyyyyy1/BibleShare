import SwiftUI

/// Create-group sheet. Name + optional description only; check-in schedule is
/// deferred to Plan 5 (the RPC stores it dormant when set).
struct CreateGroupView: View {
    /// Called after a successful create so the caller can refresh its list.
    let onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm = CreateGroupViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = vm.errorMessage {
                        Text(error).font(.caption).foregroundStyle(Theme.danger)
                    }
                    SereneTextField(title: "Group name", text: $vm.name, autocapitalization: .sentences)
                    SereneTextField(title: "Description (optional)", text: $vm.groupDescription,
                                    autocapitalization: .sentences)
                    PrimaryButton(title: "Create group", isLoading: vm.isSubmitting) {
                        Task {
                            if await vm.submit() != nil {
                                await onCreated()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .opacity(vm.canSubmit ? 1 : 0.5)
                }
                .padding(20)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
