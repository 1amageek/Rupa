import Foundation
import SwiftCAD
import RupaCoreTypes

/// Where a transform turns and scales about.
public enum SceneTransformPivotMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// The center of the selection's world bounding box.
    case boundingBox
    /// The mean of the selected objects' own pivots.
    case median
    /// The pivot of the object selected last.
    case active
}

/// Which axes a transform is measured along.
public enum SceneTransformOrientation: String, Codable, Hashable, Sendable, CaseIterable {
    /// The active object's own axes.
    case normal
    /// The axes of a picked pivot.
    case pivot
    case constructionPlane
    case world

    /// The next orientation in the cycle Plasticity's W key steps through.
    public var next: SceneTransformOrientation {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Resolves the frame a selection is transformed in.
public struct SceneTransformFrameResolver: Sendable {
    public struct Input: Sendable {
        /// The selected objects, in selection order; the last one is the active object.
        public var sceneNodeIDs: [SceneNodeID]
        public var pivotMode: SceneTransformPivotMode
        public var orientation: SceneTransformOrientation
        /// A pivot the user placed; it overrides the pivot mode and supplies the pivot axes.
        public var pickedPivot: SceneTransformFrame?
        public var constructionPlane: SketchPlane?
        /// The selection's world bounds, required by the bounding-box pivot.
        public var selectionBounds: MeasurementResult.Bounds?

        public init(
            sceneNodeIDs: [SceneNodeID],
            pivotMode: SceneTransformPivotMode = .boundingBox,
            orientation: SceneTransformOrientation = .world,
            pickedPivot: SceneTransformFrame? = nil,
            constructionPlane: SketchPlane? = nil,
            selectionBounds: MeasurementResult.Bounds? = nil
        ) {
            self.sceneNodeIDs = sceneNodeIDs
            self.pivotMode = pivotMode
            self.orientation = orientation
            self.pickedPivot = pickedPivot
            self.constructionPlane = constructionPlane
            self.selectionBounds = selectionBounds
        }
    }

    public init() {}

    public func frame(_ input: Input, metadata: ProductMetadata) throws -> SceneTransformFrame {
        guard let activeID = input.sceneNodeIDs.last else {
            throw EditorError(code: .commandInvalid, message: "A transform needs a selected object.")
        }
        let hierarchy = try SceneNodeHierarchy(metadata: metadata)
        func origin(of id: SceneNodeID) throws -> Point3D {
            try hierarchy.worldTransform(of: id).applied(to: .origin)
        }

        let pivot: Point3D
        if let picked = input.pickedPivot {
            pivot = picked.origin
        } else {
            switch input.pivotMode {
            case .boundingBox:
                guard let b = input.selectionBounds else {
                    throw EditorError(code: .commandInvalid, message: "The bounding-box pivot needs the selection's bounds.")
                }
                pivot = Point3D(x: (b.minX + b.maxX) / 2, y: (b.minY + b.maxY) / 2, z: (b.minZ + b.maxZ) / 2)
            case .median:
                let ids = hierarchy.outermostSceneNodeIDs(among: input.sceneNodeIDs)
                let origins = try ids.map(origin(of:))
                guard !origins.isEmpty else {
                    throw EditorError(code: .commandInvalid, message: "The median pivot needs a selected object.")
                }
                let n = Double(origins.count)
                pivot = Point3D(
                    x: origins.map(\.x).reduce(0, +) / n,
                    y: origins.map(\.y).reduce(0, +) / n,
                    z: origins.map(\.z).reduce(0, +) / n
                )
            case .active:
                pivot = try origin(of: activeID)
            }
        }

        switch input.orientation {
        case .world:
            return .world(at: pivot)
        case .constructionPlane:
            guard let plane = input.constructionPlane else {
                return .world(at: pivot)
            }
            let system = try SketchPlaneCoordinateSystem(plane: plane)
            return try SceneTransformFrame(origin: pivot, xAxis: system.u, yAxis: system.v, zAxis: system.normal)
        case .pivot:
            guard let picked = input.pickedPivot else {
                throw EditorError(code: .commandInvalid, message: "The pivot orientation needs a picked pivot.")
            }
            return picked.moved(to: pivot)
        case .normal:
            return try SceneTransformFrame(origin: pivot, axesOf: try hierarchy.worldTransform(of: activeID))
        }
    }
}
