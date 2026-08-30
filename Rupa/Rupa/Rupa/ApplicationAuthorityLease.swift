import Darwin
import Foundation

final class ApplicationAuthorityLease {
    static let lockFileName = "application.lock"

    let lockFileURL: URL
    private let descriptor: Int32

    private init(lockFileURL: URL, descriptor: Int32) {
        self.lockFileURL = lockFileURL
        self.descriptor = descriptor
    }

    static func acquireProductAuthority(
        fileManager: FileManager = .default
    ) throws -> ApplicationAuthorityLease {
        try acquire(
            in: ApplicationProductConfiguration.authorityDirectory(
                fileManager: fileManager
            ),
            fileManager: fileManager
        )
    }

    static func acquire(
        in directory: URL,
        fileManager: FileManager = .default
    ) throws -> ApplicationAuthorityLease {
        let normalizedDirectory = directory.standardizedFileURL
        do {
            try fileManager.createDirectory(
                at: normalizedDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: normalizedDirectory.path
            )
        } catch {
            throw ApplicationAuthorityLeaseError.directoryPreparationFailed(
                normalizedDirectory,
                message: error.localizedDescription
            )
        }

        let lockFileURL = normalizedDirectory.appendingPathComponent(
            lockFileName,
            isDirectory: false
        )
        let descriptor = lockFileURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_EXLOCK | O_NONBLOCK,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            let errorNumber = errno
            if errorNumber == EWOULDBLOCK || errorNumber == EAGAIN {
                throw ApplicationAuthorityLeaseError.alreadyRunning(lockFileURL)
            }
            throw ApplicationAuthorityLeaseError.lockFileOpenFailed(
                lockFileURL,
                errorNumber: errorNumber
            )
        }

        guard Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            let errorNumber = errno
            _ = Darwin.close(descriptor)
            throw ApplicationAuthorityLeaseError.lockFilePermissionFailed(
                lockFileURL,
                errorNumber: errorNumber
            )
        }

        return ApplicationAuthorityLease(
            lockFileURL: lockFileURL,
            descriptor: descriptor
        )
    }

    deinit {
        _ = Darwin.close(descriptor)
    }
}
