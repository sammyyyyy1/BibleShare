import SwiftUI

/// Create-group sheet. Name + optional description + optional check-in
/// schedule (cadence/time/weekday; device timezone shown read-only).
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Check-in schedule")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)

                        Picker("Cadence", selection: $vm.cadence) {
                            Text("None").tag(CheckinCadence.none)
                            Text("Daily").tag(CheckinCadence.daily)
                            Text("Weekly").tag(CheckinCadence.weekly)
                        }
                        .pickerStyle(.segmented)

                        if vm.cadence != .none {
                            DatePicker("Time", selection: $vm.checkinTime,
                                       displayedComponents: .hourAndMinute)
                                .tint(Theme.indigo)

                            if vm.cadence == .weekly {
                                Picker("Day", selection: $vm.weekday) {
                                    Text("Sunday").tag(0)
                                    Text("Monday").tag(1)
                                    Text("Tuesday").tag(2)
                                    Text("Wednesday").tag(3)
                                    Text("Thursday").tag(4)
                                    Text("Friday").tag(5)
                                    Text("Saturday").tag(6)
                                }
                                .tint(Theme.indigo)
                            }

                            HStack {
                                Text("Timezone").foregroundStyle(Theme.muted)
                                Spacer()
                                Text(vm.timezone).foregroundStyle(Theme.ink)
                            }
                            .font(.subheadline)
                        }
                    }

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
