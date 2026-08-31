import Foundation
import SwiftCAD
import RupaCoreTypes

public struct CommandExecutionResult: Codable, Equatable, Sendable {
    public let commandName: String
    public let generation: DocumentGeneration
    public let didMutate: Bool
    public let diagnostics: [EditorDiagnostic]
    public let primaryFeatureID: FeatureID?
    public let generatedIdentities: CommandGeneratedIdentityDelta
    public let curveRebuildReport: CurveRebuildReport?
    public let addedSelectionDimensionID: SelectionDimensionID?
    public let createdConstructionPlaneID: ConstructionPlaneSourceID?

    public var createdFeatureIDs: [FeatureID] {
        generatedIdentities.featureIDs
    }

    init(
        commandName: String,
        generation: DocumentGeneration,
        didMutate: Bool,
        diagnostics: [EditorDiagnostic],
        primaryFeatureID: FeatureID? = nil,
        generatedIdentities: CommandGeneratedIdentityDelta = .empty,
        curveRebuildReport: CurveRebuildReport? = nil,
        addedSelectionDimensionID: SelectionDimensionID? = nil,
        createdConstructionPlaneID: ConstructionPlaneSourceID? = nil
    ) throws {
        guard didMutate || generatedIdentities.isEmpty else {
            throw CommandGeneratedIdentityError.identityChangedWithoutMutation
        }
        self.commandName = commandName
        self.generation = generation
        self.didMutate = didMutate
        self.diagnostics = diagnostics
        self.primaryFeatureID = primaryFeatureID ?? generatedIdentities.featureIDs.first
        self.generatedIdentities = generatedIdentities
        self.curveRebuildReport = curveRebuildReport
        self.addedSelectionDimensionID = addedSelectionDimensionID
        self.createdConstructionPlaneID = createdConstructionPlaneID
    }

    private enum CodingKeys: String, CodingKey {
        case commandName
        case generation
        case didMutate
        case diagnostics
        case primaryFeatureID
        case generatedIdentities
        case curveRebuildReport
        case addedSelectionDimensionID
        case createdConstructionPlaneID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .commandName,
            .generation,
            .didMutate,
            .diagnostics,
            .primaryFeatureID,
            .generatedIdentities,
            .curveRebuildReport,
            .addedSelectionDimensionID,
            .createdConstructionPlaneID,
        ], in: decoder)
        try self.init(
            commandName: container.decode(String.self, forKey: .commandName),
            generation: container.decode(DocumentGeneration.self, forKey: .generation),
            didMutate: container.decode(Bool.self, forKey: .didMutate),
            diagnostics: container.decode([EditorDiagnostic].self, forKey: .diagnostics),
            primaryFeatureID: container.decodeIfPresent(FeatureID.self, forKey: .primaryFeatureID),
            generatedIdentities: container.decode(
                CommandGeneratedIdentityDelta.self,
                forKey: .generatedIdentities
            ),
            curveRebuildReport: container.decodeIfPresent(
                CurveRebuildReport.self,
                forKey: .curveRebuildReport
            ),
            addedSelectionDimensionID: container.decodeIfPresent(
                SelectionDimensionID.self,
                forKey: .addedSelectionDimensionID
            ),
            createdConstructionPlaneID: container.decodeIfPresent(
                ConstructionPlaneSourceID.self,
                forKey: .createdConstructionPlaneID
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandName, forKey: .commandName)
        try container.encode(generation, forKey: .generation)
        try container.encode(didMutate, forKey: .didMutate)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encodeIfPresent(primaryFeatureID, forKey: .primaryFeatureID)
        try container.encode(generatedIdentities, forKey: .generatedIdentities)
        try container.encodeIfPresent(curveRebuildReport, forKey: .curveRebuildReport)
        try container.encodeIfPresent(
            addedSelectionDimensionID,
            forKey: .addedSelectionDimensionID
        )
        try container.encodeIfPresent(
            createdConstructionPlaneID,
            forKey: .createdConstructionPlaneID
        )
    }
}
