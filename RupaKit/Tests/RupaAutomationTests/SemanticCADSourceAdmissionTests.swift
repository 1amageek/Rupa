import RupaCore
import SwiftCAD
import Testing

@testable import RupaAutomation

@Test(.timeLimit(.minutes(1)))
func preparedAutomationAdmitsIdentityFreeSemanticCreationAndRejectsRawSourceGraphs() {
  let semanticSketch = EditorCommand.createSemanticSketch(
    name: "Semantic Sketch",
    plan: SketchCreationPlan(
      plane: .xy,
      entities: [
        .line(
          start: SketchPoint(
            x: .length(0, .meter),
            y: .length(0, .meter)
          ),
          end: SketchPoint(
            x: .length(1, .meter),
            y: .length(0, .meter)
          )
        )
      ]
    ),
    geometryRole: .curve
  )
  let semanticSphere = EditorCommand.createAnalyticSphere(
    name: "Semantic Sphere",
    center: .origin,
    radius: 1
  )
  var rawBuilder = SketchBuilder(on: .xy)
  _ = rawBuilder.line(
    from: SketchPoint(
      x: .length(0, .meter),
      y: .length(0, .meter)
    ),
    to: SketchPoint(
      x: .length(1, .meter),
      y: .length(0, .meter)
    )
  )

  #expect(PreparedAutomationSourceCommandValidation.isAcceptedSourceCommand(semanticSketch))
  #expect(PreparedAutomationSourceCommandValidation.isAcceptedSourceCommand(semanticSphere))
  #expect(
    PreparedAutomationSourceCommandValidation.isAcceptedSourceCommand(
      .createSketch(
        name: "Caller-built Sketch",
        sketch: rawBuilder.build(),
        geometryRole: .curve
      )
    ) == false)
  #expect(
    PreparedAutomationSourceCommandValidation.isAcceptedSourceCommand(
      .appendFeatureGraph(FeatureGraphTransaction(features: []))
    ) == false)
}
