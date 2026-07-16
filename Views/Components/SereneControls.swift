import SwiftUI

struct SereneTextField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .never

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboard)
            .textContentType(content)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .padding(12)
            .background(Theme.field)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

struct SereneSecureField: View {
    let title: String
    @Binding var text: String
    var content: UITextContentType? = .password

    var body: some View {
        SecureField(title, text: $text)
            .textContentType(content)
            .padding(12)
            .background(Theme.field)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading { ProgressView().tint(.white) }
                Text(title).opacity(isLoading ? 0 : 1)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.indigo)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        }
        .disabled(isLoading)
    }
}

struct SocialButton: View {
    let label: String
    let systemMark: String
    var markColor: Color = Theme.ink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemMark).foregroundStyle(markColor)
                Text(label).foregroundStyle(Theme.ink)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Theme.field)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.hairline))
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        }
    }
}

struct OrDivider: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text(text).font(.caption2).foregroundStyle(Theme.muted).fixedSize()
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}
