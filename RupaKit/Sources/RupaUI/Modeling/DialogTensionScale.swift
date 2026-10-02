import Foundation

/// The Tension a surface dialog shows (XNURBS, Square, Align Surface), where 0.5 is neutral as in
/// Plasticity, against the kernel's cross-boundary scale, where 1 is: the kernel scale is
/// 4^(t − 0.5), so 0.5 is 1, 0 halves it, 1 doubles it, and every finite shown value has a
/// positive scale (a non-finite one stays non-finite and the kernel refuses it).
enum DialogTensionScale {
    static let neutral = 0.5

    /// The kernel's cross-boundary scale for the shown tension `value`.
    static func kernelScale(_ value: Double) -> Double {
        pow(4, value - neutral)
    }
}
