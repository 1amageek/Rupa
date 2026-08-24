import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#endif

enum ProjectPackageAtomicFileReplacer {
    static func replace(temporaryURL: URL, destinationURL: URL) throws {
        let result = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
            destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                // Both nul-terminated paths are owned by their URLs for these nested
                // synchronous borrows and cannot escape the atomic rename call.
                guard let temporaryPath, let destinationPath else {
                    return Int32(-1)
                }
                #if canImport(Darwin)
                return Darwin.rename(temporaryPath, destinationPath)
                #elseif canImport(Glibc)
                return Glibc.rename(temporaryPath, destinationPath)
                #elseif canImport(WASILibc)
                return WASILibc.rename(temporaryPath, destinationPath)
                #else
                return Int32(-1)
                #endif
            }
        }
        guard result == 0 else {
            throw ProjectPackageError(
                code: .atomicSaveFailure,
                message: "Project package atomic replacement failed."
            )
        }
    }
}
