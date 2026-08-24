public struct QuantityDimension: Codable, Equatable, Hashable, Sendable {
    public let length: Int8
    public let mass: Int8
    public let time: Int8
    public let electricCurrent: Int8
    public let temperature: Int8
    public let amount: Int8
    public let luminousIntensity: Int8
    public let angle: Int8

    public init(
        length: Int8 = 0,
        mass: Int8 = 0,
        time: Int8 = 0,
        electricCurrent: Int8 = 0,
        temperature: Int8 = 0,
        amount: Int8 = 0,
        luminousIntensity: Int8 = 0,
        angle: Int8 = 0
    ) {
        self.length = length
        self.mass = mass
        self.time = time
        self.electricCurrent = electricCurrent
        self.temperature = temperature
        self.amount = amount
        self.luminousIntensity = luminousIntensity
        self.angle = angle
    }

    public static let dimensionless = QuantityDimension()
    public static let length = QuantityDimension(length: 1)
    public static let area = QuantityDimension(length: 2)
    public static let volume = QuantityDimension(length: 3)
    public static let mass = QuantityDimension(mass: 1)
    public static let time = QuantityDimension(time: 1)
    public static let temperature = QuantityDimension(temperature: 1)
    public static let angle = QuantityDimension(angle: 1)
}
