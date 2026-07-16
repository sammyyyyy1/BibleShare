import SwiftUI

struct CommentsView: View {
    let postID: UUID
    let userID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var vm = CommentsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if vm.isLoading && vm.comments.isEmpty {
                            ProgressView().tint(Theme.indigo).padding(.top, 30)
                        } else if vm.comments.isEmpty {
                            Text("No comments yet.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity).padding(.top, 30)
                        }
                        ForEach(vm.comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("@\(comment.author?.username ?? "unknown")")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text(comment.createdAt, format: .relative(presentation: .named))
                                        .font(.caption2).foregroundStyle(Theme.muted)
                                }
                                Text(comment.content)
                                    .font(.subheadline).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                }

                Divider().overlay(Theme.hairline)
                HStack(spacing: 8) {
                    SereneTextField(title: "Add a comment", text: $vm.draft,
                                     autocapitalization: .sentences)
                    Button {
                        Task { await vm.send(postID: postID, userID: userID) }
                    } label: {
                        if vm.isSending {
                            ProgressView().tint(Theme.indigo)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle(vm.canSend ? Theme.indigo : Theme.muted.opacity(0.5))
                        }
                    }
                    .disabled(!vm.canSend)
                }
                .padding(12)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await vm.load(postID: postID) }
        }
    }
}
