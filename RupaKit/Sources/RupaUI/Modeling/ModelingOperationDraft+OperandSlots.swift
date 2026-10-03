import RupaCore

/// The pick slots of Pipe's, Sweep's and XNURBS's dialogs. Operands put in a slot keep its role;
/// operands taken as one ordered selection ("Use Current Selection") take the role their place
/// gives them. Either way `targets` is kept in the order `command(in:)` reads them.
extension ModelingOperationDraft {
    /// The slots the dialog shows, in Plasticity's order; empty for an operation that reads one
    /// ordered selection.
    var operandSlots: [ModelingOperandSlot] {
        switch kind {
        case .xnurbs: [.boundaries, .guides]
        case .pipe: pipeCustomProfile ? [.profile, .paths, .targetBodies] : [.paths, .targetBodies]
        // The spine is picked before the guides, as Plasticity's dialog asks for them.
        case .sweep: [.section, .spine, .guides, .targetBodies]
        default: []
        }
    }

    /// The slots in the order `command(in:)` reads its operands.
    private var operandReadingOrder: [ModelingOperandSlot] {
        switch kind {
        case .sweep: [.section, .guides, .spine, .targetBodies]
        default: operandSlots
        }
    }

    /// The operands in `slot`.
    func operands(in slot: ModelingOperandSlot, document: DesignDocument) -> [SelectionTarget] {
        targets.indices.filter { self.slot(ofOperandAt: $0, document: document) == slot }.map { targets[$0] }
    }

    /// `targets` in the order `command(in:)` reads them: by slot once operands are put in slots,
    /// else as selected.
    func slotOrderedTargets(document: DesignDocument) -> [SelectionTarget] {
        guard operandSlotRoles.isEmpty == false else { return targets }
        return operandReadingOrder.flatMap { operands(in: $0, document: document) }
    }

    /// The selection put in `slot`, replacing what it held; an operand already in another slot
    /// moves to this one. Target bodies take only solids.
    mutating func use(_ selection: [SelectionTarget], for slot: ModelingOperandSlot, document: DesignDocument) {
        guard operandSlots.contains(slot) else { return }
        var picked: [SelectionTarget] = []
        for target in selection where picked.contains(target) == false {
            if slot == .targetBodies, Self.isSolidBody(target, document: document) == false { continue }
            picked.append(target)
        }
        var parts: [ModelingOperandSlot: [SelectionTarget]] = [:]
        for other in operandReadingOrder {
            parts[other] = operands(in: other, document: document).filter { picked.contains($0) == false }
        }
        parts[slot] = picked
        operandSlotRoles = [:]
        for other in operandReadingOrder {
            for target in parts[other] ?? [] { operandSlotRoles[target] = other }
        }
        targets = operandReadingOrder.flatMap { parts[$0] ?? [] }
        if kind == .xnurbs {
            xnurbsGuideNodeIDs = Set((parts[.guides] ?? []).map(\.sceneNodeID))
        }
    }

    /// The first slot the operation needs that is still empty, once its operands are put in
    /// slots; nil for operands taken as one ordered selection.
    func missingOperandSlot(document: DesignDocument) -> ModelingOperandSlot? {
        guard operandSlotRoles.isEmpty == false else { return nil }
        let required: [ModelingOperandSlot] = switch kind {
        case .xnurbs: [.boundaries]
        case .pipe: pipeCustomProfile ? [.profile, .paths] : [.paths]
        case .sweep: [.section, .spine]
        default: []
        }
        return required.first { operands(in: $0, document: document).isEmpty }
    }

    /// The slot of the operand at `index`: the one it was put in, else the one its place in an
    /// ordered selection gives it (Pipe: the custom profile first, the curves, then the solids;
    /// Sweep: the section first, the guides, the spine, then the solids).
    func slot(ofOperandAt index: Int, document: DesignDocument) -> ModelingOperandSlot? {
        let target = targets[index]
        if kind == .xnurbs {
            return xnurbsGuideNodeIDs.contains(target.sceneNodeID) ? .guides : .boundaries
        }
        if let role = operandSlotRoles[target] { return role }
        let lastNonBody = targets.lastIndex { Self.isSolidBody($0, document: document) == false }
        let isTrailingBody = lastNonBody.map { index > $0 } ?? (index > 0)
        switch kind {
        case .pipe:
            if pipeCustomProfile, index == 0 { return .profile }
            return isTrailingBody ? .targetBodies : .paths
        case .sweep:
            if index == 0 { return .section }
            if isTrailingBody { return .targetBodies }
            return index == lastNonBody ? .spine : .guides
        default:
            return nil
        }
    }

    private static func isSolidBody(_ target: SelectionTarget, document: DesignDocument) -> Bool {
        target.component == .object
            && document.productMetadata.sceneNodes[target.sceneNodeID]?.object?.geometryRole == .solid
    }
}
