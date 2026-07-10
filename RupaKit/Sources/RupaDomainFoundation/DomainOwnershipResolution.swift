import RupaCore
import RupaCoreTypes

public enum DomainProjectionOwnershipKind: String, Codable, Equatable, Sendable {
    case domainOwned
    case universalOwned
    case classified
    case unknownNamespace
}

public enum DomainProjectionEditRoute: String, Codable, Equatable, Sendable {
    case domainCapability
    case universalCADCommand
    case classificationUpdate
    case projectionRepair
    case preserveOnly
}

public enum DomainProjectionFreshness: String, Codable, Equatable, Sendable {
    case notApplicable
    case current
    case stale
    case unavailable
}

public struct DomainOwnershipResolution: Codable, Equatable, Sendable {
    public var extensionID: SemanticExtensionID
    public var namespace: SemanticNamespaceID
    public var semanticEntityID: SemanticEntityID
    public var ownership: SemanticOwnershipPolicy
    public var ownershipKind: DomainProjectionOwnershipKind
    public var editRoute: DomainProjectionEditRoute
    public var isNamespaceRegistered: Bool
    public var freshness: DomainProjectionFreshness
    public var dependencyIdentity: ProjectionDependencyIdentity?
    public var currentDependencyIdentity: ProjectionDependencyIdentity?

    public init(
        extensionID: SemanticExtensionID,
        namespace: SemanticNamespaceID,
        semanticEntityID: SemanticEntityID,
        ownership: SemanticOwnershipPolicy,
        ownershipKind: DomainProjectionOwnershipKind,
        editRoute: DomainProjectionEditRoute,
        isNamespaceRegistered: Bool,
        freshness: DomainProjectionFreshness,
        dependencyIdentity: ProjectionDependencyIdentity?,
        currentDependencyIdentity: ProjectionDependencyIdentity?
    ) {
        self.extensionID = extensionID
        self.namespace = namespace
        self.semanticEntityID = semanticEntityID
        self.ownership = ownership
        self.ownershipKind = ownershipKind
        self.editRoute = editRoute
        self.isNamespaceRegistered = isNamespaceRegistered
        self.freshness = freshness
        self.dependencyIdentity = dependencyIdentity
        self.currentDependencyIdentity = currentDependencyIdentity
    }
}

public struct DomainOwnershipResolver: Sendable {
    private let registeredNamespaces: Set<SemanticNamespaceID>

    public init(registeredNamespaces: Set<SemanticNamespaceID>) {
        self.registeredNamespaces = registeredNamespaces
    }

    public init(registry: DomainRegistry) {
        self.registeredNamespaces = Set(registry.namespaces.keys)
    }

    public func resolve(
        envelope: SemanticExtensionEnvelope,
        semanticEntity: ProjectionSemanticEntity,
        in document: DesignDocument,
        generation: DocumentGeneration
    ) throws -> DomainOwnershipResolution {
        let isRegistered = registeredNamespaces.contains(envelope.namespace)
        let currentDependencyIdentity = envelope.projection.hasSourceBoundReferences(
            for: semanticEntity.id
        )
            ? try ProjectionDependencyIdentityBuilder().identity(
                for: semanticEntity.id,
                in: envelope,
                document: document,
                generation: generation
            )
            : nil
        let freshness = Self.freshness(
            hasSourceBoundReferences: envelope.projection.hasSourceBoundReferences(
                for: semanticEntity.id
            ),
            dependencyIdentity: semanticEntity.dependencyIdentity,
            currentDependencyIdentity: currentDependencyIdentity
        )
        let ownershipKind = Self.ownershipKind(
            ownership: semanticEntity.ownership,
            isRegistered: isRegistered
        )
        let editRoute = Self.editRoute(
            ownership: semanticEntity.ownership,
            isRegistered: isRegistered,
            freshness: freshness
        )
        return DomainOwnershipResolution(
            extensionID: envelope.id,
            namespace: envelope.namespace,
            semanticEntityID: semanticEntity.id,
            ownership: semanticEntity.ownership,
            ownershipKind: ownershipKind,
            editRoute: editRoute,
            isNamespaceRegistered: isRegistered,
            freshness: freshness,
            dependencyIdentity: semanticEntity.dependencyIdentity,
            currentDependencyIdentity: currentDependencyIdentity
        )
    }

    public func resolve(
        envelope: SemanticExtensionEnvelope,
        semanticEntityID: SemanticEntityID,
        in document: DesignDocument,
        generation: DocumentGeneration
    ) throws -> DomainOwnershipResolution {
        guard let semanticEntity = envelope.projection.semanticEntities.first(where: {
            $0.id == semanticEntityID
        }) else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Semantic entity \(semanticEntityID.rawValue) is not declared by extension \(envelope.id.rawValue.uuidString)."
            )
        }
        return try resolve(
            envelope: envelope,
            semanticEntity: semanticEntity,
            in: document,
            generation: generation
        )
    }

    public func resolveAll(
        in document: DesignDocument,
        generation: DocumentGeneration
    ) throws -> [DomainOwnershipResolution] {
        try document.productMetadata.semanticExtensions.values
            .flatMap { envelope in
                try envelope.projection.semanticEntities.map { semanticEntity in
                    try resolve(
                        envelope: envelope,
                        semanticEntity: semanticEntity,
                        in: document,
                        generation: generation
                    )
                }
            }
            .sorted { lhs, rhs in
                let leftExtensionID = lhs.extensionID.rawValue.uuidString
                let rightExtensionID = rhs.extensionID.rawValue.uuidString
                if leftExtensionID != rightExtensionID {
                    return leftExtensionID < rightExtensionID
                }
                return lhs.semanticEntityID.rawValue < rhs.semanticEntityID.rawValue
            }
    }

    private static func freshness(
        hasSourceBoundReferences: Bool,
        dependencyIdentity: ProjectionDependencyIdentity?,
        currentDependencyIdentity: ProjectionDependencyIdentity?
    ) -> DomainProjectionFreshness {
        guard hasSourceBoundReferences else {
            return .notApplicable
        }
        guard let dependencyIdentity,
              let currentDependencyIdentity else {
            return .unavailable
        }
        return dependencyIdentity.matchesDependencies(of: currentDependencyIdentity)
            ? .current
            : .stale
    }

    private static func ownershipKind(
        ownership: SemanticOwnershipPolicy,
        isRegistered: Bool
    ) -> DomainProjectionOwnershipKind {
        guard isRegistered else {
            return .unknownNamespace
        }
        switch ownership {
        case .domainOwned:
            return .domainOwned
        case .universalOwned:
            return .universalOwned
        case .classified:
            return .classified
        }
    }

    private static func editRoute(
        ownership: SemanticOwnershipPolicy,
        isRegistered: Bool,
        freshness: DomainProjectionFreshness
    ) -> DomainProjectionEditRoute {
        guard isRegistered else {
            return .preserveOnly
        }
        guard freshness == .current || freshness == .notApplicable else {
            return .projectionRepair
        }
        switch ownership {
        case .domainOwned:
            return .domainCapability
        case .universalOwned:
            return .universalCADCommand
        case .classified:
            return .classificationUpdate
        }
    }
}
