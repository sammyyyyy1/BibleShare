import SwiftUI
import PhotosUI

struct ComposeEncouragementView: View {
    let userID: UUID
    /// When set, the group is pre-selected as a destination (group "Post here").
    var preselectedGroupID: UUID? = nil
    /// Called with the new post's id after a successful write.
    let onPosted: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm = ComposeViewModel()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showVersePicker = false
    @State private var showTagSheet = false
    @State private var linkURL = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.danger.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    }

                    SereneTextField(title: "Title (required)", text: $vm.title,
                                     autocapitalization: .sentences)

                    TextEditor(text: $vm.body)
                        .frame(minHeight: 110)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Theme.field)
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                        .overlay(alignment: .topLeading) {
                            if vm.body.isEmpty {
                                Text("Share an encouragement…")
                                    .font(.body).foregroundStyle(Theme.muted)
                                    .padding(.horizontal, 13).padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                    attachmentBar

                    ForEach(vm.verses) { verse in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verse.referenceLabel)
                                    .font(.system(.caption, design: .serif).weight(.semibold))
                                    .foregroundStyle(Theme.indigo)
                                Text(verse.textSnapshot)
                                    .font(.system(.caption, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(3)
                            }
                            Spacer()
                            Button { vm.removeVerse(id: verse.id) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(10)
                        .background(Theme.field)
                        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                    }

                    if !vm.pendingImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.pendingImages) { image in
                                    if let ui = UIImage(data: image.jpeg) {
                                        Image(uiImage: ui)
                                            .resizable().scaledToFill()
                                            .frame(width: 90, height: 90)
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    vm.pendingImages.removeAll { $0.id == image.id }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundStyle(.white)
                                                        .shadow(radius: 2)
                                                }
                                                .padding(4)
                                            }
                                    }
                                }
                            }
                        }
                    }

                    if !vm.taggedUsers.isEmpty {
                        HStack {
                            ForEach(vm.taggedUsers) { user in
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Theme.hairline.opacity(0.5))
                                    .clipShape(Capsule())
                                    .onTapGesture { vm.taggedUsers.removeAll { $0.id == user.id } }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        SereneTextField(title: "Add a link (optional)", text: $linkURL, keyboard: .URL)
                        Button("Add") {
                            let trimmed = linkURL.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            vm.addLink(url: trimmed, title: nil)
                            linkURL = ""
                        }
                        .foregroundStyle(Theme.indigo)
                    }

                    ForEach(Array(vm.links.enumerated()), id: \.offset) { index, link in
                        HStack {
                            Image(systemName: "link").foregroundStyle(Theme.indigo)
                            Text(link.url).font(.caption).lineLimit(1).foregroundStyle(Theme.ink)
                            Spacer()
                            Button { vm.links.remove(at: index) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    if !vm.myGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Post to groups").font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            ForEach(vm.myGroups) { item in
                                Button {
                                    if vm.selectedGroupIDs.contains(item.group.id) {
                                        vm.selectedGroupIDs.remove(item.group.id)
                                    } else {
                                        vm.selectedGroupIDs.insert(item.group.id)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: vm.selectedGroupIDs.contains(item.group.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(vm.selectedGroupIDs.contains(item.group.id)
                                                             ? Theme.indigo : Theme.muted)
                                        Text(item.group.name).foregroundStyle(Theme.ink)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Toggle("Show on my timeline", isOn: $vm.sharedToTimeline)
                        .font(.subheadline)
                        .tint(Theme.indigo)

                    PrimaryButton(title: "Post", isLoading: vm.isSubmitting) {
                        Task {
                            if let id = await vm.submit(userID: userID) {
                                onPosted(id)
                                dismiss()
                            }
                            // On failure the draft stays put and vm.errorMessage shows.
                        }
                    }
                    .disabled(!vm.canSubmit)
                    .opacity(vm.canSubmit ? 1 : 0.5)
                }
                .padding(20)
            }
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("New encouragement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showVersePicker) {
                VersePickerSheet { book, chapter, start, end in
                    await vm.addVerse(book: book, chapter: chapter, verseStart: start, verseEnd: end)
                }
            }
            .sheet(isPresented: $showTagSheet) {
                UserTagSheet { username in await vm.addTag(username: username) }
            }
            .onChange(of: photoItems) { _, items in
                Task { await loadPhotos(items) }
            }
            .task {
                await vm.loadGroups(userID: userID)
                if let preselectedGroupID { vm.preselect(groupID: preselectedGroupID) }
            }
        }
    }

    private var attachmentBar: some View {
        HStack(spacing: 12) {
            Button { showVersePicker = true } label: {
                Label("Verse", systemImage: "book.closed")
            }
            PhotosPicker(selection: $photoItems,
                         maxSelectionCount: ComposeViewModel.maxImages,
                         matching: .images) {
                Label("Photo", systemImage: "photo")
            }
            .disabled(!vm.canAddImage)
            Button { showTagSheet = true } label: {
                Label("Tag", systemImage: "person")
            }
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(Theme.indigo)
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard vm.canAddImage else { break }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data),
                  let jpeg = ImageProcessor.jpegData(from: ui) else { continue }
            vm.pendingImages.append(ComposeImage(id: UUID(), jpeg: jpeg))
        }
        photoItems = []
    }
}
