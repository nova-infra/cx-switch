import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlass(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(shape.fill(.thinMaterial))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.06)))
        }
    }

    @ViewBuilder
    func adaptiveGlassTint(_ color: Color) -> some View {
        adaptiveGlassTint(color, in: Capsule())
    }

    @ViewBuilder
    func adaptiveGlassTint<S: Shape>(_ color: Color, in shape: S) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(color), in: shape)
        } else {
            self.background(color.opacity(0.15), in: shape)
        }
    }

    @ViewBuilder
    func adaptiveGlassCircle() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: Circle())
        } else {
            self.background(Color.primary.opacity(0.06), in: Circle())
        }
    }
}

struct AdaptiveGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}
