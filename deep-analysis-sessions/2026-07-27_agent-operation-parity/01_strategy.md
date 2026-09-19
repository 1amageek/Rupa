# Analysis Strategy

1. Map the live app-to-Agent connection.
2. Trace Agent mutations into AutomationRunner and EditorSession.
3. Compare Agent public operations with Core/UI-only operations.
4. Inspect success/failure tests and run the narrowest available build.
5. Decide whether a viewer-first architecture is currently safe.

Critical path: `ApplicationRoot -> AgentHost -> socket -> AgentCommandController -> AutomationRunner -> EditorSession -> save/export`.

The RupaAgent product build was selected before package-wide tests because it is the narrowest executable gate for the question.
