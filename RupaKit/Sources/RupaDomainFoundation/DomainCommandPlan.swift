import RupaAutomation
import RupaCore
import RupaCoreTypes

public enum DomainCommandPlan: Sendable {
    case automationBatch(AutomationBatch)
    case documentTransaction(DomainDocumentTransaction)
    case query(any DomainCommandQuery)
}
