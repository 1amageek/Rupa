import RupaCore

public enum DomainFoundationCapabilityLedgerProvider {
    public static func entries() -> [CapabilityLedgerEntry] {
        [
            CapabilityLedgerEntry(
                id: "domainFoundation.contracts",
                category: .domainFoundation,
                title: "Domain foundation contracts, registry, storage bridge, and generic execution",
                currentRating: .partial,
                gateAssessments: [
                    CADInteractionQualityGateAssessment(
                        gate: .referenceContract,
                        rating: .verified,
                        evidence: [
                            "DOMAIN_EXTENSION_ARCHITECTURE.md",
                            "DOMAIN_FOUNDATION_DESIGN.md",
                            "DomainRegistry validates namespaces, capabilities, lowerings, validators, repairs, and simulation adapters.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .sourceOwnership,
                        rating: .implemented,
                        evidence: [
                            "SemanticExtensionEnvelope and ProjectionManifest live in RupaCore.",
                            "DomainOwnershipResolver separates domain-owned, universal-owned, classified, unknown, and stale projections.",
                        ],
                        openWork: [
                            "Wire projection repair into user-visible domain edit flows.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .commandContract,
                        rating: .implemented,
                        evidence: [
                            "DomainCommandExecutor lowers registered domain requests into Automation batches or editor commands.",
                            "Dry-run execution restores session state for mutating domain plans.",
                            "DomainCommandParameterDescriptor validates typed payload paths, units, defaults, nullability, choices, and numeric bounds.",
                            "DomainCommandPayloadBuilder builds nested semantic JSON payloads and rejects unknown, missing, or invalid values before execution.",
                            "DomainRegistry requires namespace-qualified capability IDs and exactly one command lowering for every descriptor before discovery.",
                        ],
                        openWork: [
                            "Extend parameter contracts with selection references, collections, and file or artifact inputs required by future domains.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .selectionTopology,
                        rating: .partial,
                        evidence: [
                            "ProjectionManifest can store semantic entity IDs, source feature IDs, scene node IDs, topology names, drawing references, and boundary tags.",
                        ],
                        openWork: [
                            "Add repair and freshness diagnostics to every semantic selection readback.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .viewportAffordance,
                        rating: .partial,
                        evidence: [
                            "RupaUI can map injected domain capability descriptors into the workspace command catalog.",
                            "WorkspaceDomainCommandPanel renders scalar, choice, nullable, length, and angle inputs and executes generation-safe requests through DomainCommandExecutor.",
                            "Workspace drafts distinguish unset and null values, invalidate stale results after input or generation changes, and show returned diagnostic messages.",
                        ],
                        openWork: [
                            "Add viewport-driven selection-reference and collection parameter inputs without concrete domain imports.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .inspectorAffordance,
                        rating: .planned,
                        openWork: [
                            "Generic semantic object inspectors need property schema, projection status, and validator result surfaces.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .agentParity,
                        rating: .implemented,
                        evidence: [
                            "Agent protocol exposes domain.execute.",
                            "Agent runtime dispatches through an injected DomainRegistry.",
                            "CLIService supports file, live, and auto domain execution.",
                            "Agent capability discovery publishes the same typed domain input parameter descriptors used by RupaUI.",
                            "Read-only and mutating domain capabilities both advertise generation requirements, and dry-run support is explicit in Agent discovery.",
                        ],
                        openWork: [
                            "Publish composed domain registries from app and plugin roots.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .measurementDiagnostics,
                        rating: .partial,
                        evidence: [
                            "Domain registry and executor return typed registry and editor errors before mutation.",
                        ],
                        openWork: [
                            "Add structured domain validation summaries and projection freshness diagnostics to UI and Agent readback.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .verification,
                        rating: .implemented,
                        evidence: [
                            "RupaDomainFoundationTests",
                            "RupaAgentContractTests domain.execute coverage",
                            "RupaCLITests domain execution coverage",
                            "RupaUIPackageTests command catalog and generation-safe payload draft coverage",
                            "Rupa macOS app composition build",
                        ],
                        openWork: [
                            "Add composition-root tests once concrete domain registries are installed by app and CLI entry points.",
                        ]
                    ),
                    CADInteractionQualityGateAssessment(
                        gate: .performanceBudget,
                        rating: .planned,
                        openWork: [
                            "Measure large semantic payload decoding, projection manifest lookup, and registry dispatch budgets.",
                        ]
                    ),
                ],
                evidence: [
                    CADInteractionQualityEvidence(
                        label: "Domain foundation execution surface",
                        sourceFiles: [
                            "RupaKit/Sources/RupaCore/SemanticExtensionEnvelope.swift",
                            "RupaKit/Sources/RupaCore/ProjectionManifest.swift",
                            "RupaKit/Sources/RupaDomainFoundation/DomainRegistry.swift",
                            "RupaKit/Sources/RupaDomainFoundation/DomainCommandExecutor.swift",
                            "RupaKit/Sources/RupaDomainFoundation/DomainCommandParameterDescriptor.swift",
                            "RupaKit/Sources/RupaDomainFoundation/DomainCommandPayloadBuilder.swift",
                            "RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift",
                            "RupaKit/Sources/RupaCLIKit/CLIService.swift",
                            "RupaKit/Sources/RupaUI/WorkspaceCommandCatalog.swift",
                            "RupaKit/Sources/RupaUI/WorkspaceDomainCommandPanel.swift",
                        ],
                        tests: [
                            "RupaKit/Tests/RupaCoreTests/SemanticExtensionStorageTests.swift",
                            "RupaKit/Tests/RupaDomainFoundationTests/DomainRegistryTests.swift",
                            "RupaKit/Tests/RupaDomainFoundationTests/DomainCommandPayloadBuilderTests.swift",
                            "RupaKit/Tests/RupaAgentContractTests/AgentProtocolCodecTests.swift",
                            "RupaKit/Tests/RupaCLITests/CLIResponseTests.swift",
                            "RupaKit/Tests/RupaUIPackageTests/WorkspaceCommandCatalogTests.swift",
                        ],
                        notes: [
                            "The foundation now provides one typed scalar payload contract across registry validation, Agent discovery, Workspace forms, and execution.",
                            "The foundation remains incomplete until richer reference inputs, plugin and CLI composition, semantic Inspector surfaces, projection diagnostics, and performance budgets land.",
                        ]
                    ),
                ],
                openWork: [
                    "Compose concrete domain registries in app, CLI, and plugin roots.",
                    "Extend schema-driven payload forms with selection references, collections, files, and artifact inputs.",
                    "Expose domain validation and projection freshness diagnostics in Inspector, Agent, and CLI readback.",
                    "Add performance budgets for large semantic payloads and projection manifests.",
                ],
                nextRequiredResult: "Selection-reference payloads and semantic projection diagnostics must use the same registered contract across app, CLI, and Agent without concrete imports in UI or runtime layers."
            ),
        ]
    }
}
