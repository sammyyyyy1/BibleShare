import SwiftUI

/// Structured reference entry (spec §10: no fuzzy search in v1).
struct VersePickerSheet: View {
    let onAdd: (String, Int, Int, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var book = ""
    @State private var chapter = ""
    @State private var verseStart = ""
    @State private var verseEnd = ""
    @State private var isAdding = false

    private var parsed: (String, Int, Int, Int)? {
        let b = book.trimmingCharacters(in: .whitespaces)
        guard !b.isEmpty,
              let c = Int(chapter), c > 0,
              let s = Int(verseStart), s > 0 else { return nil }
        let e = Int(verseEnd) ?? s
        return (b, c, s, max(e, s))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                SereneTextField(title: "Book (e.g. John)", text: $book)
                    .textInputAutocapitalization(.words)
                HStack(spacing: 10) {
                    SereneTextField(title: "Chapter", text: $chapter, keyboard: .numberPad)
                    SereneTextField(title: "Verse", text: $verseStart, keyboard: .numberPad)
                    SereneTextField(title: "To (optional)", text: $verseEnd, keyboard: .numberPad)
                }
                Text("Passages come from the World English Bible.")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                PrimaryButton(title: "Add verse", isLoading: isAdding) {
                    guard let (b, c, s, e) = parsed else { return }
                    Task {
                        isAdding = true
                        await onAdd(b, c, s, e)
                        isAdding = false
                        dismiss()
                    }
                }
                .disabled(parsed == nil || isAdding)
                .opacity(parsed == nil ? 0.5 : 1)
            }
            .padding(20)
            .background(Theme.cream.ignoresSafeArea())
            .navigationTitle("Add a verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
