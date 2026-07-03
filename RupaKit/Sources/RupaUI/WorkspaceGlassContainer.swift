import SwiftUI

extension View {
    func workspaceGlassContainer() -> some View {
        self
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}
