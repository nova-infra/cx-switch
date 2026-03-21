import SwiftUI

struct LoginFlowSheet: View {
    let loginFlow: LoginFlowState
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            if let message = loginFlow.message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
            } else if let status = localizedStatus(loginFlow.status), !status.isEmpty {
                Text(status)
                    .font(.subheadline)
            }

            if let error = loginFlow.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func localizedStatus(_ status: String?) -> String? {
        switch status?.lowercased() {
        case Strings.loginWaiting.lowercased():
            return Strings.loginWaiting
        case Strings.loginCompleted.lowercased():
            return Strings.loginCompleted
        case Strings.loginPreparing.lowercased():
            return Strings.loginPreparing
        default:
            return status
        }
    }
}
