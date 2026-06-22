import Foundation

public struct SketchInputState: Codable, Equatable, Sendable {
    public static let maximumReferenceLineAnchorCount = 8
    public static let standard = SketchInputState()

    public var axisConstraint: SketchAxisConstraint?
    public var dimensionInputFocus: SketchDimensionInputFocus?
    public var dimensionInputLengthMeters: Double?
    public var dimensionInputAngleRadians: Double?
    public var dimensionInputWidthMeters: Double?
    public var dimensionInputHeightMeters: Double?
    public var referenceLineAnchors: [SketchReferenceLineAnchor]

    public init(
        axisConstraint: SketchAxisConstraint? = nil,
        dimensionInputFocus: SketchDimensionInputFocus? = nil,
        dimensionInputLengthMeters: Double? = nil,
        dimensionInputAngleRadians: Double? = nil,
        dimensionInputWidthMeters: Double? = nil,
        dimensionInputHeightMeters: Double? = nil,
        referenceLineAnchors: [SketchReferenceLineAnchor] = []
    ) {
        self.axisConstraint = axisConstraint
        self.dimensionInputFocus = dimensionInputFocus
        self.dimensionInputLengthMeters = dimensionInputLengthMeters
        self.dimensionInputAngleRadians = dimensionInputAngleRadians
        self.dimensionInputWidthMeters = dimensionInputWidthMeters
        self.dimensionInputHeightMeters = dimensionInputHeightMeters
        self.referenceLineAnchors = Array(referenceLineAnchors.prefix(Self.maximumReferenceLineAnchorCount))
    }

    public mutating func setAxisConstraint(_ axisConstraint: SketchAxisConstraint?) {
        self.axisConstraint = axisConstraint
    }

    public mutating func toggleAxisConstraint(_ axisConstraint: SketchAxisConstraint) {
        if self.axisConstraint == axisConstraint {
            self.axisConstraint = nil
        } else {
            self.axisConstraint = axisConstraint
        }
    }

    public mutating func clearAxisConstraint() {
        axisConstraint = nil
    }

    @discardableResult
    public mutating func focusNextDimensionInput(
        availableFocuses: [SketchDimensionInputFocus] = SketchDimensionInputFocus.allCases
    ) -> SketchDimensionInputFocus? {
        guard availableFocuses.isEmpty == false else {
            dimensionInputFocus = nil
            return nil
        }
        guard let dimensionInputFocus,
              let currentIndex = availableFocuses.firstIndex(of: dimensionInputFocus) else {
            self.dimensionInputFocus = availableFocuses[0]
            return self.dimensionInputFocus
        }
        let nextIndex = availableFocuses.index(after: currentIndex)
        self.dimensionInputFocus = nextIndex == availableFocuses.endIndex
            ? availableFocuses[0]
            : availableFocuses[nextIndex]
        return self.dimensionInputFocus
    }

    public mutating func clearDimensionInputFocus() {
        dimensionInputFocus = nil
    }

    public mutating func setDimensionInputLengthMeters(_ lengthMeters: Double?) throws {
        guard let lengthMeters else {
            dimensionInputLengthMeters = nil
            return
        }
        guard lengthMeters.isFinite else {
            throw SketchDimensionInputValueError.nonFiniteLength
        }
        guard lengthMeters > 0.0 else {
            throw SketchDimensionInputValueError.nonPositiveLength
        }
        dimensionInputLengthMeters = lengthMeters
        dimensionInputFocus = .length
    }

    public mutating func setDimensionInputAngleRadians(_ angleRadians: Double?) throws {
        guard let angleRadians else {
            dimensionInputAngleRadians = nil
            return
        }
        guard angleRadians.isFinite else {
            throw SketchDimensionInputValueError.nonFiniteAngle
        }
        dimensionInputAngleRadians = angleRadians
        dimensionInputFocus = .angle
    }

    public mutating func setDimensionInputWidthMeters(_ widthMeters: Double?) throws {
        guard let widthMeters else {
            dimensionInputWidthMeters = nil
            return
        }
        guard widthMeters.isFinite else {
            throw SketchDimensionInputValueError.nonFiniteWidth
        }
        guard widthMeters > 0.0 else {
            throw SketchDimensionInputValueError.nonPositiveWidth
        }
        dimensionInputWidthMeters = widthMeters
        dimensionInputFocus = .width
    }

    public mutating func setDimensionInputHeightMeters(_ heightMeters: Double?) throws {
        guard let heightMeters else {
            dimensionInputHeightMeters = nil
            return
        }
        guard heightMeters.isFinite else {
            throw SketchDimensionInputValueError.nonFiniteHeight
        }
        guard heightMeters > 0.0 else {
            throw SketchDimensionInputValueError.nonPositiveHeight
        }
        dimensionInputHeightMeters = heightMeters
        dimensionInputFocus = .height
    }

    public mutating func addReferenceLineAnchor(_ anchor: SketchReferenceLineAnchor) {
        referenceLineAnchors.removeAll { existing in
            let deltaX = existing.point.x - anchor.point.x
            let deltaY = existing.point.y - anchor.point.y
            return (deltaX * deltaX + deltaY * deltaY).squareRoot() <= 1.0e-10
        }
        referenceLineAnchors.append(anchor)
        if referenceLineAnchors.count > Self.maximumReferenceLineAnchorCount {
            referenceLineAnchors.removeFirst(referenceLineAnchors.count - Self.maximumReferenceLineAnchorCount)
        }
    }

    public mutating func clearReferenceLineAnchors() {
        referenceLineAnchors.removeAll()
    }

    public mutating func clearTransientInput() {
        axisConstraint = nil
        dimensionInputFocus = nil
        dimensionInputLengthMeters = nil
        dimensionInputAngleRadians = nil
        dimensionInputWidthMeters = nil
        dimensionInputHeightMeters = nil
        referenceLineAnchors.removeAll()
    }
}
