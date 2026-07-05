import Foundation

public struct DrawingProjectionColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hexRed: Int, green: Int, blue: Int) {
        self.red = Double(hexRed) / 255.0
        self.green = Double(green) / 255.0
        self.blue = Double(blue) / 255.0
    }

    public var hexString: String {
        let r = Self.channelByte(red)
        let g = Self.channelByte(green)
        let b = Self.channelByte(blue)
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    public func normalized(fallback: DrawingProjectionColor) -> DrawingProjectionColor {
        DrawingProjectionColor(
            red: Self.normalizedChannel(red, fallback: fallback.red),
            green: Self.normalizedChannel(green, fallback: fallback.green),
            blue: Self.normalizedChannel(blue, fallback: fallback.blue)
        )
    }

    private static func normalizedChannel(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else {
            return fallback
        }
        return min(max(value, 0.0), 1.0)
    }

    private static func channelByte(_ value: Double) -> Int {
        guard value.isFinite else {
            return 0
        }
        return Int((min(max(value, 0.0), 1.0) * 255.0).rounded())
    }
}
