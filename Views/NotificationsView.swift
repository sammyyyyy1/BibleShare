import SwiftUI

struct NotificationsView: View {
    @Bindable var vm: NotificationsViewModel
    @Environment(AppRouter.self) private var router
    @State private var unavailableMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if vm.items.isEmpty && !vm.isLoading {
                    ContentUnavailableView("Nothing yet",
                                           systemImage: "bell",
                                           description: Text("Likes, comments and check-ins will show up here."))
                } else {
                    List {
                        ForEach(vm.items) { item in
                            Button { Task { await open(item) } } label: { NotificationRow(item: item) }
                                .buttonStyle(.plain)
                        }
                        if !vm.items.isEmpty {
                            Color.clear.frame(height: 1)
                                .onAppear { Task { await vm.loadMore() } }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                if vm.unreadCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark all read") { Task { await vm.markAllRead() } }
                    }
                }
            }
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .alert("That's no longer available",
                   isPresented: .constant(unavailableMessage != nil),
                   presenting: unavailableMessage) { _ in
                Button("OK") { unavailableMessage = nil }
            } message: { Text($0) }
            .alert("Something went wrong",
                   isPresented: .constant(vm.errorMessage != nil),
                   presenting: vm.errorMessage) { _ in
                Button("OK") { vm.errorMessage = nil }
            } message: { Text($0) }
        }
    }

    private func open(_ item: NotificationItem) async {
        await vm.markRead(item)
        guard let destination = NotificationDestination.from(item) else {
            // Unresolvable: a check-in whose post was deleted and which carries
            // no group. Say so rather than selecting a tab that shows nothing.
            unavailableMessage = "That post or group isn't around anymore."
            return
        }
        router.select(destination)
    }
}
