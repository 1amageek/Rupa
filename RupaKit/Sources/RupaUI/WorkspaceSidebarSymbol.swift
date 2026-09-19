import SwiftUI

struct WorkspaceSidebarSymbol: View {
    static let pointSize: CGFloat = 13
    static let slotSize: CGFloat = 20

    let systemName: String
    var size: CGFloat = Self.pointSize

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .regular))
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
            .frame(width: Self.slotSize, height: Self.slotSize)
    }
}
