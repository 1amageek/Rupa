import SwiftCAD

public enum SceneNodeTag {}
public enum ComponentDefinitionTag {}
public enum ComponentInstanceTag {}
public enum ValidationRuleTag {}
public enum ExportPresetTag {}
public enum BridgeCurveSourceTag {}
public enum ConstructionPlaneSourceTag {}
public enum MeasurementAnnotationTag {}

public typealias SceneNodeID = TaggedID<SceneNodeTag>
public typealias ComponentDefinitionID = TaggedID<ComponentDefinitionTag>
public typealias ComponentInstanceID = TaggedID<ComponentInstanceTag>
public typealias ValidationRuleID = TaggedID<ValidationRuleTag>
public typealias ExportPresetID = TaggedID<ExportPresetTag>
public typealias BridgeCurveSourceID = TaggedID<BridgeCurveSourceTag>
public typealias ConstructionPlaneSourceID = TaggedID<ConstructionPlaneSourceTag>
public typealias MeasurementAnnotationID = TaggedID<MeasurementAnnotationTag>
