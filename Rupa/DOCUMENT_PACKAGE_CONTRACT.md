# Rupa Document Package Contract

## Purpose

This document defines the `.swcad` package schema boundary, editable source
identity, optional portable records, schema versioning, integrity, and unknown
entry behavior. It is independent from Swift-CAD's internal document schema.

## Package Aggregate

`DesignDocument` is editable source. `DocumentPackage` is the file aggregate that
contains source plus package adjuncts. File services load and save the aggregate;
editor sessions edit only its source partition.

```text
Model.swcad
|-- manifest.json
|-- source/
|   |-- cad.json
|   |-- rupa.json
|   `-- blobs/
|       `-- sha256/<content-identity>
|-- records/
|   `-- validation/*.json
|-- artifacts/
|   |-- index.json
|   `-- <content-addressed entries>
`-- extensions/
    `-- <namespaced preserved entries>
```

Only `manifest.json` and the declared source entries are required. Source blobs
are required only when referenced by an authored source record. Records,
artifacts, and namespaced extension entries are optional. Removing cache artifacts
must not remove editable source. Removing audit records may invalidate a previous
handoff claim and therefore requires an explicit package operation, never normal
source save.

## Independent Schema Versions

The manifest declares independent compatibility domains.

| Field | Meaning |
|---|---|
| `packageSchemaVersion` | Archive layout and manifest semantics |
| `cadSourceSchemaVersion` | Swift-CAD source encoding |
| `rupaSourceSchemaVersion` | Rupa editable product/documentation metadata encoding |
| `sourceBlobSchemaVersions` | Media-type-specific schemas for source-owned mesh, image, volume, and other large authored payloads |
| `recordSchemaVersions` | Immutable audit record families |
| `artifactIndexSchemaVersion` | Portable artifact index and locator encoding |

One schema version must not be reused as the version of another domain. A change
to product metadata does not silently change the Swift-CAD schema version.

## Manifest Identity

The manifest contains:

- package format ID and package schema version;
- document ID;
- each source entry path, media type, schema version, byte length, and SHA-256
  content fingerprint;
- the canonical `DocumentContentIdentity` derived from sorted logical source
  entries and their content fingerprints;
- optional record/artifact indexes and their fingerprints;
- required feature declarations for safe unsupported-version diagnostics.

Archive byte layout, ZIP timestamps, compression, file order, and package save
time are not editable source identity. The canonical identity hashes logical entry
identity and canonical content.

## Source Blobs

Large authored data is stored as content-addressed source blobs. `source/rupa.json`
maps a stable source record ID to a declared blob reference; the blob path is
derived from its SHA-256 content identity and is not the editable object identity.

| Data | Source or artifact | Reason |
|---|---|---|
| Editable mesh topology and authored attributes | Source blob | Removing it would remove editable geometry. |
| Authored image pixels or packed texture tiles | Source blob | They are direct material/paint input. |
| Authored volume grid | Source blob | It is direct object input. |
| External asset reference metadata | Source JSON | The external content remains outside the package unless packed. |
| Triangulation, normals, adjacency, BVH, and GPU buffers | Artifact | They are reproducible evaluation/render products. |
| Thumbnail, render output, and simulation cache | Artifact | They are derived outputs with independent artifact identity. |

Source blob rules:

- every source blob has a declared path, media type, schema version, byte length,
  and content fingerprint;
- the fingerprint covers the canonical uncompressed blob encoding; archive
  compression and container metadata are excluded;
- a source record cannot reference an undeclared blob;
- unchanged blobs are reused byte-for-byte during atomic save;
- decoding and encoding are streaming or memory-mapped and obey explicit resource
  limits;
- changing archive compression does not change logical source identity;
- packing an external asset adds exact source blobs but preserves the referenced
  asset and version identity separately;
- garbage collection removes an unreferenced source blob only as an explicit
  source/package operation, never as normal artifact-cache cleanup.

## Source and Adjunct Mutation

| Operation | Source transaction revision | Source dirty state | Source content identity |
|---|---:|---:|---:|
| Source command save | Preserved from session provenance | Cleared after successful atomic write | May change |
| Workspace-state save | Unchanged | Unchanged | Unchanged |
| Add artifact cache | Unchanged | Unchanged | Unchanged |
| Record validation decision | Unchanged | Unchanged | Unchanged |
| Revoke audit decision | Unchanged | Unchanged | Unchanged |

Package adjunct updates use atomic file replacement but do not enter source undo
history. The project layer coordinates source and adjunct writes when one external
handoff operation needs both.

## Unknown Entries

- Unknown entries under a valid namespaced `extensions/` path are preserved
  byte-for-byte when the package is saved without a registered handler.
- Unknown required manifest features reject load with a typed unsupported-version
  result.
- Unknown arbitrary top-level entries are invalid; they are not silently ignored.
- A loader that exposes only editable source must retain an opaque adjunct set so a
  later save cannot discard records or extensions.

## Integrity and Safety

- Every declared entry is checked against its manifest length and fingerprint.
- Entry paths are normalized and cannot escape the archive root.
- Duplicate normalized paths, symlink-like entries, invalid UTF-8 names, and
  resource-limit violations are rejected.
- Large artifacts are streamed or memory-mapped. Package parsing does not require
  copying every artifact into one in-memory dictionary.
- Large source blobs are also streamed or memory-mapped. Opening metadata does not
  eagerly decode every geometry, image, or volume payload.
- Atomic save prepares a complete package next to the destination, validates it,
  then replaces the destination.

## Migration

Development schemas may break without compatibility shims. A released
conformance manifest explicitly lists accepted package, CAD source, Rupa source,
record, and artifact-index versions. Migrations are explicit transforms from one
declared schema tuple to another and preserve unknown namespaced entries.

## Required Tests

| Test family | Required cases |
|---|---|
| Versioning | Package, CAD, Rupa, source-blob, record, and artifact schema versions vary independently. |
| Identity | Re-encoding, compression, or package-entry order does not change canonical source identity; source JSON/blob changes do. |
| Adjuncts | Artifact/decision updates do not alter source identity or source dirty state. |
| Preservation | Unknown namespaced entries survive load/save byte-for-byte. |
| Source blobs | Missing/undeclared blobs reject load; unchanged blobs are reused; explicit source garbage collection retains every referenced blob. |
| Integrity | Length/hash mismatch, duplicate paths, traversal, unsupported required features, and size limits reject safely. |
| I/O | Save failure leaves the original package intact; large source and artifact entries are bounded and streamed. |
