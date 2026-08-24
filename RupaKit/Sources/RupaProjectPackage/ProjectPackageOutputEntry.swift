import Foundation

enum ProjectPackageOutputEntry: Sendable {
    case data(path: String, value: Data)
    case mesh(ProjectPackageMeshBlobPlan)
    case retained(ProjectPackageArchiveEntryDescriptor)

    var path: String {
        switch self {
        case .data(let path, _):
            path
        case .mesh(let plan):
            plan.reference.path
        case .retained(let descriptor):
            descriptor.path
        }
    }
}
