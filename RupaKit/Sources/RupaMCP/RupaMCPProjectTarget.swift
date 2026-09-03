import Foundation

public enum RupaMCPProjectTarget: Equatable, Sendable {
    case project(URL)
    case session(UUID)
}
