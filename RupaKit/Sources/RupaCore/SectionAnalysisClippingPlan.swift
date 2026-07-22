import Foundation

public enum SectionAnalysisRetainedSide: String, Codable, CaseIterable, Sendable {
    case front
    case behind
}

public struct SectionAnalysisClippingRequest: Codable, Equatable, Sendable {
    public var retainedSide: SectionAnalysisRetainedSide

    public init(retainedSide: SectionAnalysisRetainedSide) {
        self.retainedSide = retainedSide
    }
}

public struct SectionAnalysisClippingPlan: Codable, Equatable, Sendable {
    public enum BodyAction: String, Codable, Equatable, Sendable {
        case visible
        case hidden
        case clipped
    }

    public struct Body: Codable, Equatable, Sendable {
        public var bodyID: String
        public var sourceFeatureID: String?
        public var stableReference: StableSubshapeReference?
        public var name: String?
        public var classification: SectionAnalysisResult.BodyClassification
        public var action: BodyAction

        public init(
            bodyID: String,
            sourceFeatureID: String? = nil,
            stableReference: StableSubshapeReference? = nil,
            name: String?,
            classification: SectionAnalysisResult.BodyClassification,
            action: BodyAction
        ) {
            self.bodyID = bodyID
            self.sourceFeatureID = sourceFeatureID
            self.stableReference = stableReference
            self.name = name
            self.classification = classification
            self.action = action
        }
    }

    public var retainedSide: SectionAnalysisRetainedSide
    public var bodies: [Body]
    public var visibleBodyCount: Int
    public var hiddenBodyCount: Int
    public var clippedBodyCount: Int

    public init(
        retainedSide: SectionAnalysisRetainedSide,
        bodies: [Body]
    ) {
        self.retainedSide = retainedSide
        self.bodies = bodies
        self.visibleBodyCount = bodies.filter { $0.action == .visible }.count
        self.hiddenBodyCount = bodies.filter { $0.action == .hidden }.count
        self.clippedBodyCount = bodies.filter { $0.action == .clipped }.count
    }

    public init(
        result: SectionAnalysisResult,
        retaining retainedSide: SectionAnalysisRetainedSide
    ) {
        self.init(
            retainedSide: retainedSide,
            bodies: result.bodies.map { body in
                Body(
                    bodyID: body.bodyID,
                    sourceFeatureID: body.sourceFeatureID,
                    stableReference: body.stableReference,
                    name: body.name,
                    classification: body.classification,
                    action: Self.action(
                        for: body.classification,
                        retaining: retainedSide
                    )
                )
            }
        )
    }

    public func action(for bodyID: String) -> BodyAction? {
        bodies.first { $0.bodyID == bodyID }?.action
    }

    public func action(
        forStableReference stableReference: StableSubshapeReference
    ) -> BodyAction? {
        bodies.first { $0.stableReference == stableReference }?.action
    }

    public func action(forSourceFeatureID sourceFeatureID: String) -> BodyAction? {
        bodies.first { $0.sourceFeatureID == sourceFeatureID }?.action
    }

    private static func action(
        for classification: SectionAnalysisResult.BodyClassification,
        retaining retainedSide: SectionAnalysisRetainedSide
    ) -> BodyAction {
        switch classification {
        case .inFront:
            retainedSide == .front ? .visible : .hidden
        case .behind:
            retainedSide == .behind ? .visible : .hidden
        case .coplanar, .touching:
            .visible
        case .intersects, .spansPlane:
            .clipped
        }
    }
}
