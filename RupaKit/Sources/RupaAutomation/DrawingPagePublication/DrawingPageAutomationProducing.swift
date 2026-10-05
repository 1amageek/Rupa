import Foundation
import RupaCore

public protocol DrawingPageAutomationProducing: Sendable {
    func generate(_ request: DrawingPageAutomationRequest, in session: EditorSession) throws -> DrawingPageAutomationResult
    func export(_ request: DrawingPageAutomationRequest, to url: URL,
        in session: EditorSession) throws -> DrawingPageAutomationResult
}
