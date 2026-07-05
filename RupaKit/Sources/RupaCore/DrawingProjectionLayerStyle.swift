public struct DrawingProjectionLayerStyle: Codable, Equatable, Sendable {
    public var color: DrawingProjectionColor
    public var strokeWidth: Double
    public var dashPattern: [Double]

    public init(
        color: DrawingProjectionColor,
        strokeWidth: Double,
        dashPattern: [Double] = []
    ) {
        self.color = color
        self.strokeWidth = strokeWidth
        self.dashPattern = dashPattern
    }

    public func normalized(fallback: DrawingProjectionLayerStyle) -> DrawingProjectionLayerStyle {
        DrawingProjectionLayerStyle(
            color: color.normalized(fallback: fallback.color),
            strokeWidth: strokeWidth.isFinite && strokeWidth > 0.0 ? strokeWidth : fallback.strokeWidth,
            dashPattern: normalizedDashPattern(fallback: fallback.dashPattern)
        )
    }

    private func normalizedDashPattern(fallback: [Double]) -> [Double] {
        let normalized = dashPattern.filter { value in
            value.isFinite && value > 0.0
        }
        if dashPattern.isEmpty || !normalized.isEmpty {
            return normalized
        }
        return fallback
    }
}
