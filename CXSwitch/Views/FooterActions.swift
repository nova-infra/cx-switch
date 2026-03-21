import SwiftUI

struct FooterActions: View {
    let onOpenSettings: () -> Void
    let onOpenStatus: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)

            Button(action: onOpenStatus) {
                Image(systemName: "waveform.path.ecg")
            }
            .buttonStyle(.plain)

            Spacer()

            Button(Strings.quit, action: onQuit)
        }
    }
}
