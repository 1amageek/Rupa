import SwiftCAD

public enum RupaSceneNodeTag {}
public enum RupaComponentDefinitionTag {}
public enum RupaComponentInstanceTag {}
public enum RupaValidationRuleTag {}
public enum RupaExportPresetTag {}

public typealias RupaSceneNodeID = TaggedID<RupaSceneNodeTag>
public typealias RupaComponentDefinitionID = TaggedID<RupaComponentDefinitionTag>
public typealias RupaComponentInstanceID = TaggedID<RupaComponentInstanceTag>
public typealias RupaValidationRuleID = TaggedID<RupaValidationRuleTag>
public typealias RupaExportPresetID = TaggedID<RupaExportPresetTag>
