import RupaCore
import SwiftCAD

/// What Complete Edge and Subdivide act on in the selection.
///
/// A selected sketch curve counts itself; a selected sketch object counts each of its curves; a
/// selected B-spline surface object or face counts the surface. Anything else is left alone, so
/// the commands are offered only when the selection holds something they change.
struct WorkspaceCurveRefinementPlanner {
    /// Subdivide's commands with the control points it creates, which it then selects.
    struct Subdivision: Equatable {
        var commands: [EditorCommand]
        var createdControlPoints: [SelectionTarget]
    }

    let document: DesignDocument

    /// One Complete Edge per selected line, arc or open spline.
    func completeEdgeCommands(for targets: [SelectionTarget]) -> [EditorCommand] {
        curves(in: targets).filter { curve in
            switch curve.entity {
            case .line, .arc: true
            case .spline(let spline): !spline.isClosed
            case .circle, .point: false
            }
        }
        .map { curve in EditorCommand.completeSketchCurve(target: curve.target) }
    }

    /// One Subdivide per selected spline and B-spline surface.
    func subdivision(for targets: [SelectionTarget]) throws -> Subdivision {
        var commands: [EditorCommand] = []
        var created: [SelectionTarget] = []
        for curve in curves(in: targets) {
            guard case .spline(let spline) = curve.entity else { continue }
            commands.append(.subdivideSketchSpline(target: curve.target))
            for index in try document.sketchSplineSubdivisionControlPointIndices(spline) {
                created.append(SelectionTarget(
                    sceneNodeID: curve.target.sceneNodeID,
                    component: .sketchEntity(.sketchControlPoint(
                        featureID: curve.featureID, entityID: curve.entityID, index: index
                    ))
                ))
            }
        }

        var surfaceFeatures: Set<FeatureID> = []
        for target in targets {
            switch target.component {
            case .object, .face: break
            default: continue
            }
            guard let featureID = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID,
                  case .bSplineSurface = document.cadDocument.designGraph.nodes[featureID]?.operation,
                  surfaceFeatures.insert(featureID).inserted else { continue }
            commands.append(.subdivideSurface(target: target))
        }
        return Subdivision(commands: commands, createdControlPoints: created)
    }

    private struct Curve {
        var target: SelectionTarget
        var featureID: FeatureID
        var entityID: SketchEntityID
        var entity: SketchEntity
    }

    private func curves(in targets: [SelectionTarget]) -> [Curve] {
        var result: [Curve] = []
        var seen: Set<String> = []
        func add(_ sceneNodeID: SceneNodeID, _ featureID: FeatureID, _ entityID: SketchEntityID, _ sketch: Sketch) {
            guard let entity = sketch.entities[entityID],
                  seen.insert("\(featureID.description):\(entityID.description)").inserted else { return }
            result.append(Curve(
                target: SelectionTarget(
                    sceneNodeID: sceneNodeID,
                    component: .sketchEntity(.sketchEntity(featureID: featureID, entityID: entityID))
                ),
                featureID: featureID, entityID: entityID, entity: entity
            ))
        }
        for target in targets {
            switch target.component {
            case .sketchEntity(let componentID):
                guard let reference = componentID.sketchEntityReference,
                      case .sketch(let sketch) = document.cadDocument.designGraph.nodes[reference.featureID]?.operation else { continue }
                add(target.sceneNodeID, reference.featureID, reference.entityID, sketch)
            case .object:
                guard let featureID = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID,
                      case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else { continue }
                for entityID in sketch.entityOrder {
                    add(target.sceneNodeID, featureID, entityID, sketch)
                }
            default:
                continue
            }
        }
        return result
    }
}
