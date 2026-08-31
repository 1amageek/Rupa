# RupaAgentUI

## Purpose and Scope

`RupaAgentUI` owns the application-facing Agent host. It is a child of the
[RupaKit package design](../../DESIGN.md) and has no child designs.

The host keeps an HTTP listener alive for the App process and injects one
semantic request handler. It is not a project or package authority.

## Responsibilities and Boundaries

The module owns `AgentHost` state and listener start/stop lifecycle. It accepts
an application-composed `AgentRequestHandling` value and a listener factory.
It does not own Keychain storage, CLI parsing, project persistence, CAD/Mesh
semantics, session resolution, or a second workspace/controller.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaKit package](../../DESIGN.md) | parent | module graph and single authority | Places the host above runtime and below App composition. | Host lifecycle is process-scoped. |
| [Rupa App](../../../Rupa/Rupa/Rupa/DESIGN.md) | used by | handler, listener, and discovery composition | Builds one host over the App workspace. | Start before window restoration and publish only after readiness. |
| [RupaAgentRuntime](../RupaAgentRuntime/DESIGN.md) | depends on | registered-workspace request handling | Supplies the semantic handler. | Runtime never binds or discovers an endpoint. |
| [RupaAgentTransport](../RupaAgentTransport/DESIGN.md) | depends on | loopback HTTP listener | Enforces framing and mutual authentication. | The host does not inspect HTTP fields. |
| [RupaProjectAccessPlatform](../RupaProjectAccessPlatform/DESIGN.md) | coordinates with | discovery record writer | App composition publishes the ready listener record. | Host cannot publish or remove records itself. |

## Architecture

```mermaid
flowchart LR
    App["ApplicationRoot"] --> Host["AgentHost\nprocess lifetime"]
    Host --> Listener["Loopback HTTP listener"]
    Listener --> Router["ApplicationAgentRequestRouter"]
    Router --> Runtime["ProjectAgentCommandController"]
    Runtime --> Workspace["ProjectWorkspace → ProjectController"]
    App --> Writer["Keychain discovery writer"]
    Listener -->|ready port| Writer
```

## Contracts and Invariants

1. The host starts independently of window and scene restoration and remains
   available through active, inactive, and background phases.
2. Listener readiness returns a dynamic loopback port. App composition writes
   the port, per-launch HMAC key, and generation only after readiness; the key
   is never sent over the API connection.
3. The host delegates decoded requests unchanged to one handler. It never
   creates a workspace, registry, controller, or package writer.
4. The listener enforces 16-MiB bodies, 32 connections, bounded headers,
   required Content-Length, one same-connection challenge/RPC exchange, and
   one deadline. It rejects a second challenge or RPC on that connection.
5. HTTP mutual authentication uses a request nonce and directional HMAC
   proofs derived from the Keychain secret. The raw secret is never sent.
6. Stop drains accepted requests, then App composition conditionally removes
   only its own discovery generation. A response-loss result is not retried.

## Runtime Flows

```mermaid
sequenceDiagram
    participant A as App
    participant H as AgentHost
    participant L as HTTP listener
    participant K as Keychain writer
    A->>H: start()
    H->>L: bind loopback dynamic port
    L-->>H: ready(port)
    A->>K: publish(port, secret, generation)
    L->>L: verify client proof before JSON decode
    L->>A: route decoded request
    A->>H: stop()
    H->>L: drain and close
    A->>K: remove(ifGeneration: own)
```

## State, Ownership, and Lifecycle

`AgentHost` owns only listener lifecycle state. The App owns the listener
secret/generation and discovery record lifecycle; Runtime owns registered
workspace state; the project layer owns source and package state.

## Failure, Concurrency, and Constraints

Startup, authentication, framing, deadline, cancellation, capacity, handler,
and shutdown failures are typed and observable. No failure selects another
transport or local project authority.

## Verification and Change Impact

Host tests prove listener readiness, handler injection, authenticated routing,
bounded drain, terminal listener lifetime, and no workspace duplication. App
tests own process-lifetime startup, discovery publication and conditional
generation removal, and the complete same-workspace evidence.
