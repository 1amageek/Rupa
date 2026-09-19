import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct OutlinerDropDelegate: DropDelegate {
    let acceptedType: UTType
    let isLocalDragActive: () -> Bool
    let resolveDestination: (CGPoint) -> OutlinerDropDestination?
    let updateHighlight: (OutlinerDropDestination?) -> Void
    let perform: ([NSItemProvider], OutlinerDropDestination) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        isLocalDragActive()
            && info.hasItemsConforming(to: [acceptedType])
            && resolveDestination(info.location) != nil
    }

    func dropEntered(info: DropInfo) {
        update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isLocalDragActive(),
              info.hasItemsConforming(to: [acceptedType]),
              let destination = resolveDestination(info.location) else {
            updateHighlight(nil)
            return DropProposal(operation: .forbidden)
        }
        updateHighlight(destination)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        updateHighlight(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [acceptedType])
        let destination = resolveDestination(info.location)
        updateHighlight(nil)
        guard isLocalDragActive(),
              !providers.isEmpty,
              let destination else {
            return false
        }
        return perform(providers, destination)
    }

    private func update(_ info: DropInfo) {
        guard isLocalDragActive(),
              info.hasItemsConforming(to: [acceptedType]) else {
            updateHighlight(nil)
            return
        }
        updateHighlight(resolveDestination(info.location))
    }
}
