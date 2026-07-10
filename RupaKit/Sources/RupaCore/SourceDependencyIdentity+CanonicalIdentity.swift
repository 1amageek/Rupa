extension SourceDependencyIdentity {
    func appendCanonicalIdentity(to hasher: inout CanonicalIdentityHasher) {
        hasher.appendField("subject")
        subject.appendCanonicalIdentity(to: &hasher)
        hasher.appendField("contentFingerprint")
        hasher.appendString(contentFingerprint.algorithm)
        hasher.appendString(contentFingerprint.value)
    }
}

private extension SourceDependencySubject {
    func appendCanonicalIdentity(to hasher: inout CanonicalIdentityHasher) {
        switch self {
        case .cadDocument(let documentID):
            hasher.appendString("cadDocument")
            hasher.appendString(documentID.description)
        case .rupaDocument(let documentID):
            hasher.appendString("rupaDocument")
            hasher.appendString(documentID.description)
        case .linkedDocument(let documentID):
            hasher.appendString("linkedDocument")
            hasher.appendString(documentID.description)
        case .semanticEntity(let documentID, let namespace, let extensionID, let entityID):
            hasher.appendString("semanticEntity")
            hasher.appendString(documentID.description)
            hasher.appendString(namespace.rawValue)
            hasher.appendString(extensionID.rawValue.uuidString)
            hasher.appendString(entityID.rawValue)
        case .external(let namespace, let logicalID):
            hasher.appendString("external")
            hasher.appendString(namespace)
            hasher.appendString(logicalID)
        }
    }
}
