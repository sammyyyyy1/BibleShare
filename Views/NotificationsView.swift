import SwiftUI

/// Unifies the view's two alert sources — an unresolvable tap destination and
/// any `vm.errorMessage` failure (from `load()`/`loadMore()`/mark-read calls)
/// — into a single presentable item. Two simultaneously-true `.alert`
/// modifiers on one view have undefined SwiftUI behavior, so only one alert
/// modifier may exist; this struct is what it presents.
private struct NotificationAlertInfo: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct NotificationsView: View {
    @Bindable var vm: NotificationsViewModel
    @Environment(AppRouter.self) private var router
    @State private var unavailableMessage: String?

    /// Unresolvable-destination takes priority since it's the more specific
    /// message; either way dismissal (below) clears both sources so neither
    /// can linger and re-present.
    private var activeAlert: NotificationAlertInfo? {
        if let unavailableMessage {
            return NotificationAlertInfo(title: "That's no longer available", message: unavailableMessage)
        }
        if let error = vm.errorMessage {
            return NotificationAlertInfo(title: "Something went wrong", message: error)
        }
        return nil
    }

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
            .alert(activeAlert?.title ?? "",
                   isPresented: Binding(
                       get: { activeAlert != nil },
                       set: { isPresented in
                           guard !isPresented else { return }
                           // Clear both sources on dismiss: whichever wasn't
                           // the one showing is already nil, so this is a
                           // no-op for it. Leaving the true source set would
                           // make it immediately re-present.
                           unavailableMessage = nil
                           vm.errorMessage = nil
                       }
                   ),
                   presenting: activeAlert) { _ in
                Button("OK") { }
            } message: { Text($0.message) }
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
