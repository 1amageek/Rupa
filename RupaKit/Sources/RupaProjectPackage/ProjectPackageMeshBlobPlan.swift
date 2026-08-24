import RupaGeometry

struct ProjectPackageMeshBlobPlan: Sendable {
    let source: MeshSource
    let reference: ProjectSourceBlobReference
    let checksum: UInt32
    let maximumEncodedChunkByteCount: Int
}
