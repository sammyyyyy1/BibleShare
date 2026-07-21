import SwiftUI

struct GroupsView: View {
    let myID: UUID
    var body: some View {
        NavigationStack {
            Text("Groups")
                .foregroundStyle(Theme.muted)
                .navigationTitle("Groups")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cream.ignoresSafeArea())
        }
    }
}
