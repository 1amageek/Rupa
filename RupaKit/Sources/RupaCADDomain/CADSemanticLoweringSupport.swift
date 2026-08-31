import Foundation
import RupaAutomation
import RupaCore
import RupaDomainFoundation

extension SemanticOperationInputDescriptor {
  init(id: String, type: SemanticValueType, isRequired: Bool = true) {
    self.init(
      id: SemanticArgumentID(id),
      type: type,
      isRequired: isRequired
    )
  }
}

extension SemanticOperationOutputDescriptor {
  init(
    id: String,
    type: SemanticValueType,
    selector: SemanticOutputSelector
  ) {
    self.init(id: SemanticOutputID(id), type: type, selector: selector)
  }
}

enum CADSemanticLoweringSupport {
  static let resultEstimate = SemanticOperationResultEstimate(
    diagnosticRecordCount: 0,
    diagnosticScalarCount: 0,
    diagnosticStringUTF8ByteCount: 0,
    telemetryRecordCount: 1,
    telemetryScalarCount: 6,
    telemetryStringUTF8ByteCount: 0
  )

  static func input(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> SemanticResolvedArgument {
    guard let argument = request.arguments[SemanticArgumentID(id)] else {
      throw invalidArgument("Required argument '\(id)' is missing.")
    }
    return argument
  }

  static func text(_ id: String, in request: SemanticLoweringRequest) throws -> String {
    guard case .value(.text(let value)) = try input(id, in: request) else {
      throw invalidArgument("Argument '\(id)' must be text.")
    }
    return try validatedName(value, argument: id)
  }

  static func validatedName(_ value: String, argument: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw invalidArgument("Argument '\(argument)' must not be empty.")
    }
    return trimmed
  }

  static func number(
    _ id: String,
    unit: SemanticUnit,
    in request: SemanticLoweringRequest
  ) throws -> Double {
    guard case .value(.number(let value, unit: let actualUnit)) = try input(id, in: request),
      actualUnit == unit,
      value.isFinite
    else {
      throw invalidArgument("Argument '\(id)' must be a finite \(unit.rawValue) number.")
    }
    return value
  }

  static func positiveLength(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> Double {
    let value = try number(id, unit: .meter, in: request)
    guard value > 0 else {
      throw degenerateGeometry("Argument '\(id)' must be greater than zero.")
    }
    return value
  }

  static func nonzeroLength(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> Double {
    let value = try number(id, unit: .meter, in: request)
    guard value != 0 else {
      throw degenerateGeometry("Argument '\(id)' must not be zero.")
    }
    return value
  }

  static func integer(_ id: String, in request: SemanticLoweringRequest) throws -> Int {
    guard case .value(.integer(let value)) = try input(id, in: request),
      let result = Int(exactly: value)
    else {
      throw invalidArgument("Argument '\(id)' must be an exactly representable integer.")
    }
    return result
  }

  static func point(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> SemanticPoint3D {
    guard case .value(.point(let point)) = try input(id, in: request),
      point.isFinite,
      point.isValidUnit
    else {
      throw invalidArgument("Argument '\(id)' must be a finite point in meters.")
    }
    return point
  }

  static func direction(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> SemanticDirection3D {
    guard case .value(.direction(let direction)) = try input(id, in: request),
      direction.isFinite
    else {
      throw invalidArgument("Argument '\(id)' must be a finite direction.")
    }
    guard direction.isNonZero else {
      throw degenerateGeometry("Argument '\(id)' must be non-zero.")
    }
    return direction
  }

  static func plane(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> SemanticPlane {
    guard case .value(.plane(let plane)) = try input(id, in: request),
      plane.isFinite
    else {
      throw invalidArgument("Argument '\(id)' must be a finite plane in meters.")
    }
    guard plane.normal.isNonZero else {
      throw degenerateGeometry("Argument '\(id)' must have a non-zero normal.")
    }
    return plane
  }

  static func transform(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> SemanticTransform {
    guard case .value(.transform(let transform)) = try input(id, in: request),
      transform.isFinite
    else {
      throw invalidArgument("Argument '\(id)' must be a finite transform.")
    }
    guard transform.rotationAxis.isNonZero else {
      throw degenerateGeometry("Argument '\(id)' must have a non-zero rotation axis.")
    }
    return transform
  }

  static func angle(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> SemanticAngle {
    guard case .value(.number(let value, unit: .degree)) = try input(id, in: request),
      value.isFinite
    else {
      throw invalidArgument("Argument '\(id)' must be a finite angle in degrees.")
    }
    return SemanticAngle(value: value, unit: .degree)
  }

  static func array(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> [SemanticResolvedArgument] {
    let argument = try input(id, in: request)
    switch argument {
    case .array(let values):
      return values
    case .value(.array(let values)):
      return values.map(SemanticResolvedArgument.value)
    default:
      throw invalidArgument("Argument '\(id)' must be an array.")
    }
  }

  static func object(
    _ argument: SemanticResolvedArgument,
    owner: String
  ) throws -> [String: SemanticResolvedArgument] {
    let entries: [SemanticResolvedObjectEntry]
    switch argument {
    case .object(let resolvedEntries):
      entries = resolvedEntries
    case .value(.object(let values)):
      entries = values.map {
        SemanticResolvedObjectEntry(key: $0.key, value: .value($0.value))
      }
    default:
      throw invalidArgument("\(owner) must be an object.")
    }
    return Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
  }

  static func exactKeys(
    _ values: [String: SemanticResolvedArgument],
    expected: Set<String>,
    owner: String
  ) throws {
    guard Set(values.keys) == expected else {
      throw invalidArgument("\(owner) has missing or unsupported fields.")
    }
  }

  static func literalText(
    _ key: String,
    in values: [String: SemanticResolvedArgument],
    owner: String
  ) throws -> String {
    guard case .value(.text(let value))? = values[key] else {
      throw invalidArgument("\(owner).\(key) must be text.")
    }
    return value
  }

  static func literalInteger(
    _ key: String,
    in values: [String: SemanticResolvedArgument],
    owner: String
  ) throws -> Int {
    guard case .value(.integer(let value))? = values[key],
      let result = Int(exactly: value)
    else {
      throw invalidArgument("\(owner).\(key) must be an exactly representable integer.")
    }
    return result
  }

  static func literalPoint(
    _ key: String,
    in values: [String: SemanticResolvedArgument],
    owner: String
  ) throws -> SemanticPoint3D {
    guard case .value(.point(let point))? = values[key],
      point.isFinite,
      point.isValidUnit
    else {
      throw invalidArgument("\(owner).\(key) must be a finite point in meters.")
    }
    return point
  }

  static func literalLength(
    _ key: String,
    in values: [String: SemanticResolvedArgument],
    owner: String
  ) throws -> Double {
    guard case .value(.number(let value, unit: .meter))? = values[key],
      value.isFinite
    else {
      throw invalidArgument("\(owner).\(key) must be a finite length in meters.")
    }
    return value
  }

  static func preparedSlot(
    _ id: String,
    in request: SemanticLoweringRequest
  ) throws -> PreparedAutomationSlotID {
    try preparedSlot(try input(id, in: request), owner: "Argument '\(id)'")
  }

  static func preparedSlot(
    _ argument: SemanticResolvedArgument,
    owner: String
  ) throws -> PreparedAutomationSlotID {
    switch argument {
    case .source(_, let slot), .local(_, let slot):
      return slot
    default:
      throw RupaCADDomainError(
        code: RupaCADDomainError.referenceKindMismatchCode,
        message: "\(owner) must be a typed source reference."
      )
    }
  }

  static func corePoint(_ point: SemanticPoint3D) -> Point3D {
    Point3D(x: point.x, y: point.y, z: point.z)
  }

  static func normalizedVector(_ direction: SemanticDirection3D) throws -> Vector3D {
    let length = sqrt(
      direction.x * direction.x
        + direction.y * direction.y
        + direction.z * direction.z
    )
    guard length.isFinite, length > 0 else {
      throw degenerateGeometry("Direction must be finite and non-zero.")
    }
    return Vector3D(
      x: direction.x / length,
      y: direction.y / length,
      z: direction.z / length
    )
  }

  static func corePlane(_ plane: SemanticPlane) throws -> SketchPlane {
    .plane(
      Plane3D(
        origin: corePoint(plane.origin),
        normal: try normalizedVector(plane.normal)
      ))
  }

  static func canonicalAxisPlane(_ plane: SemanticPlane) throws -> SketchPlane {
    let normal = try normalizedVector(plane.normal)
    if plane.origin.x == 0, plane.origin.y == 0, plane.origin.z == 0 {
      if normal == .unitZ {
        return .xy
      }
      if normal == .unitY {
        return .zx
      }
      if normal == .unitX {
        return .yz
      }
    }
    return .plane(
      Plane3D(
        origin: corePoint(plane.origin),
        normal: normal
      ))
  }

  static func sketchPoint(
    _ point: SemanticPoint3D,
    on plane: SketchPlane,
    owner: String
  ) throws -> SketchPoint {
    let projection = try sketchCoordinates(point, on: plane, owner: owner)
    return SketchPoint(
      x: .length(projection.x, .meter),
      y: .length(projection.y, .meter)
    )
  }

  static func sketchCoordinates(
    _ point: SemanticPoint3D,
    on plane: SketchPlane,
    owner: String
  ) throws -> (x: Double, y: Double) {
    let coordinates: SketchPlaneCoordinateSystem
    do {
      coordinates = try SketchPlaneCoordinateSystem(plane: plane)
    } catch {
      throw degenerateGeometry("\(owner) uses an invalid sketch plane.")
    }
    let projection = coordinates.project(corePoint(point))
    guard abs(projection.depth) <= ModelingTolerance.standard.distance else {
      throw invalidArgument("\(owner) must lie on the supplied sketch plane.")
    }
    return (projection.point.x, projection.point.y)
  }

  static func coreTransform(_ transform: SemanticTransform) throws -> Transform3D {
    try coreTransform(
      translation: transform.translation,
      axisPoint: transform.axisPoint,
      rotationAxis: transform.rotationAxis,
      rotation: transform.rotation
    )
  }

  static func coreTransform(
    translation: SemanticPoint3D,
    axisPoint: SemanticPoint3D,
    rotationAxis: SemanticDirection3D,
    rotation: SemanticAngle
  ) throws -> Transform3D {
    guard translation.isFinite,
      translation.isValidUnit,
      axisPoint.isFinite,
      axisPoint.isValidUnit,
      rotationAxis.isFinite,
      rotationAxis.isNonZero,
      rotation.isFinite,
      rotation.isValidUnit
    else {
      throw invalidArgument("Transform fields must be finite and use meters/degrees.")
    }
    let axis = try normalizedVector(rotationAxis)
    let angle = rotation.value * Double.pi / 180.0
    let cosine = cos(angle)
    let sine = sin(angle)
    let oneMinusCosine = 1.0 - cosine
    let r00 = cosine + axis.x * axis.x * oneMinusCosine
    let r01 = axis.x * axis.y * oneMinusCosine - axis.z * sine
    let r02 = axis.x * axis.z * oneMinusCosine + axis.y * sine
    let r10 = axis.y * axis.x * oneMinusCosine + axis.z * sine
    let r11 = cosine + axis.y * axis.y * oneMinusCosine
    let r12 = axis.y * axis.z * oneMinusCosine - axis.x * sine
    let r20 = axis.z * axis.x * oneMinusCosine - axis.y * sine
    let r21 = axis.z * axis.y * oneMinusCosine + axis.x * sine
    let r22 = cosine + axis.z * axis.z * oneMinusCosine
    let point = corePoint(axisPoint)
    let tx = translation.x + point.x - (r00 * point.x + r01 * point.y + r02 * point.z)
    let ty = translation.y + point.y - (r10 * point.x + r11 * point.y + r12 * point.z)
    let tz = translation.z + point.z - (r20 * point.x + r21 * point.y + r22 * point.z)
    do {
      return Transform3D(
        matrix: try Matrix4x4(values: [
          r00, r01, r02, tx,
          r10, r11, r12, ty,
          r20, r21, r22, tz,
          0, 0, 0, 1,
        ]))
    } catch {
      throw invalidArgument("Transform matrix could not be constructed.")
    }
  }

  static func invalidArgument(_ message: String) -> RupaCADDomainError {
    RupaCADDomainError(code: RupaCADDomainError.invalidArgumentCode, message: message)
  }

  static func degenerateGeometry(_ message: String) -> RupaCADDomainError {
    RupaCADDomainError(code: RupaCADDomainError.degenerateGeometryCode, message: message)
  }
}
