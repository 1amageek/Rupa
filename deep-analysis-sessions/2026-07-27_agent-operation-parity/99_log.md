# Investigation Log

- Read the complete `skeleton` and `deep-analysis` skill instructions.
- Used `skltn` to map Agent, AgentRuntime, AgentProtocol, Automation, and Core structures.
- Inspected the original implementations for ApplicationRoot, AgentHost, session publication, AgentRequest, capability invocation, AutomationRunner, EditorSession, WorkspaceRegistry, save/export, and representative tests.
- Counted 158 static capability declarations: 126 automation routes and 32 typed Agent-request routes. Domain capabilities are injected dynamically.
- Confirmed no public Agent/Automation routes for undo, redo, session lifecycle, resetDocument, replaceProductMetadata, or arbitrary feature removal.
- Confirmed the default ApplicationRoot does not provide MainView a document URL, while Agent save requires one.
- Runtime inspection found no running Rupa process/default socket.
- `xcodebuild test -scheme RupaAgent` could not run because that scheme has no test action.
- `xcodebuild build -scheme RupaAgent` failed with current Swift-CAD contract errors, including missing re-exported types and required tolerance arguments.
- Restored the incidental Package.resolved change created by Xcode package resolution.
- No product source was modified.
