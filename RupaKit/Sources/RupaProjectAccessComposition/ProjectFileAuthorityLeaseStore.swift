import CryptoKit
import Darwin
import Foundation
import RupaProjectAccess

// Darwin exposes flock(2) and stat(2) with names that collide with imported
// Swift declarations. These narrow symbol bindings keep the POSIX boundary
// private while preserving the open-description and device/inode contracts.
@_silgen_name("flock")
private func rupaFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

@_silgen_name("stat")
private func rupaStat(
    _ path: UnsafePointer<CChar>,
    _ info: UnsafeMutablePointer<stat>
) -> Int32

/// Owns cross-session and cross-process project file authority leases.
///
/// A durable coordinator lock serializes creation and removal of per-path lock
/// files. Each active path is then protected by an open-description `flock`
/// lock, so releasing a lock cannot race a contender into a replacement inode.
public actor ProjectFileAuthorityLeaseStore {
    public let rootDirectory: URL

    private struct FileIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    private struct HeldPath: Sendable {
        let path: URL
        let lockURL: URL
        let lockDescriptor: Int32
        var sourceDescriptor: Int32?
        let expectedIdentity: FileIdentity?
    }

    private struct Record: Sendable {
        var paths: [URL: HeldPath]
    }

    private var records: [UUID: Record] = [:]

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    /// Acquires all canonical paths in lexical order.
    ///
    /// Paths in `requiredPaths` must exist as regular files. Other paths may be
    /// absent so an explicit output can be created by a later save.
    public func acquire(
        paths: [URL],
        requiredPaths: Set<URL> = [],
        deadline: ContinuousClock.Instant
    ) async throws -> ProjectFileAuthorityLease {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else {
            throw ProjectAccessError.deadlineExceeded
        }
        let normalizedPaths = try canonicalPaths(paths)
        let required = Set(try canonicalPaths(Array(requiredPaths)))
        guard !normalizedPaths.isEmpty else {
            throw ProjectAccessError.authorityUnavailable
        }
        guard required.isSubset(of: Set(normalizedPaths)) else {
            throw ProjectAccessError.invalidTarget(required.first ?? rootDirectory)
        }

        try ensureRootDirectory()
        let coordinator = try await acquireCoordinator(deadline: deadline)
        var held: [URL: HeldPath] = [:]
        do {
            for path in normalizedPaths {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw ProjectAccessError.deadlineExceeded
                }
                let lockURL = lockURL(for: path)
                let lockDescriptor = try openLockFile(at: lockURL)
                var acquiredPath: HeldPath?
                do {
                    guard rupaFlock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                        let errorNumber = errno
                        closeDescriptor(lockDescriptor)
                        if errorNumber == EWOULDBLOCK || errorNumber == EAGAIN {
                            throw ProjectAccessError.fileAuthorityConflict(path)
                        }
                        throw ProjectAccessError.authorityUnavailable
                    }
                    var heldPath = HeldPath(
                        path: path,
                        lockURL: lockURL,
                        lockDescriptor: lockDescriptor,
                        sourceDescriptor: nil,
                        expectedIdentity: nil
                    )
                    acquiredPath = heldPath
                    let source = try openSourceIfPresent(
                        at: path,
                        required: required.contains(path)
                    )
                    heldPath.sourceDescriptor = source.descriptor
                    heldPath = HeldPath(
                        path: heldPath.path,
                        lockURL: heldPath.lockURL,
                        lockDescriptor: heldPath.lockDescriptor,
                        sourceDescriptor: heldPath.sourceDescriptor,
                        expectedIdentity: source.identity
                    )
                    acquiredPath = heldPath
                    held[path] = heldPath
                } catch {
                    if let acquiredPath, held[path] == nil {
                        unlockAndClose(heldPath: acquiredPath, unlink: true)
                    }
                    throw error
                }
            }
            let id = UUID()
            records[id] = Record(paths: held)
            unlockAndCloseCoordinator(coordinator)
            return ProjectFileAuthorityLease(id: id, store: self, paths: normalizedPaths)
        } catch {
            for path in held.values {
                unlockAndClose(heldPath: path, unlink: true)
            }
            unlockAndCloseCoordinator(coordinator)
            throw error
        }
    }

    func validate(id: UUID) throws {
        guard let record = records[id] else {
            throw ProjectAccessError.fileAuthorityLost(rootDirectory)
        }
        for heldPath in record.paths.values {
            guard let lockIdentity = fileIdentity(ofDescriptor: heldPath.lockDescriptor),
                  let pathIdentity = fileIdentity(at: heldPath.lockURL),
              lockIdentity == pathIdentity else {
                throw ProjectAccessError.fileAuthorityLost(heldPath.path)
            }
            let currentIdentity = try currentIdentityForValidation(at: heldPath.path)
            guard currentIdentity == heldPath.expectedIdentity else {
                throw ProjectAccessError.fileAuthorityLost(heldPath.path)
            }
            if let sourceDescriptor = heldPath.sourceDescriptor,
               let sourceIdentity = fileIdentity(ofDescriptor: sourceDescriptor),
               sourceIdentity == currentIdentity {
                continue
            }
            if heldPath.sourceDescriptor != nil {
                throw ProjectAccessError.fileAuthorityLost(heldPath.path)
            }
        }
    }

    func adoptPublished(_ path: URL, leaseID: UUID) throws {
        guard var record = records[leaseID] else {
            throw ProjectAccessError.fileAuthorityLost(path.standardizedFileURL)
        }
        let canonicalPath = self.canonicalPath(path)
        guard var heldPath = record.paths[canonicalPath] else {
            throw ProjectAccessError.fileAuthorityLost(canonicalPath)
        }
        guard let lockIdentity = fileIdentity(ofDescriptor: heldPath.lockDescriptor),
              let currentLockIdentity = fileIdentity(at: heldPath.lockURL),
              lockIdentity == currentLockIdentity else {
            throw ProjectAccessError.fileAuthorityLost(canonicalPath)
        }
        guard let identity = fileIdentity(at: canonicalPath) else {
            throw ProjectAccessError.fileAuthorityLost(canonicalPath)
        }
        let descriptor = try openExistingSource(at: canonicalPath)
        guard let descriptorIdentity = fileIdentity(ofDescriptor: descriptor),
              descriptorIdentity == identity else {
            closeDescriptor(descriptor)
            throw ProjectAccessError.fileAuthorityLost(canonicalPath)
        }
        guard let publishedIdentity = fileIdentity(at: canonicalPath),
              publishedIdentity == descriptorIdentity else {
            closeDescriptor(descriptor)
            throw ProjectAccessError.fileAuthorityLost(canonicalPath)
        }
        if let oldDescriptor = heldPath.sourceDescriptor {
            closeDescriptor(oldDescriptor)
        }
        heldPath = HeldPath(
            path: heldPath.path,
            lockURL: heldPath.lockURL,
            lockDescriptor: heldPath.lockDescriptor,
            sourceDescriptor: descriptor,
            expectedIdentity: publishedIdentity
        )
        record.paths[canonicalPath] = heldPath
        records[leaseID] = record
    }

    func release(id: UUID) {
        guard let record = records.removeValue(forKey: id) else {
            return
        }
        let coordinator = tryAcquireCoordinatorImmediately()
        for heldPath in record.paths.values {
            unlockAndClose(heldPath: heldPath, unlink: coordinator != nil)
        }
        if let coordinator {
            unlockAndCloseCoordinator(coordinator)
        }
    }

    private func canonicalPaths(_ paths: [URL]) throws -> [URL] {
        var byPath: [String: URL] = [:]
        for path in paths {
            guard path.isFileURL, !path.path.isEmpty else {
                throw ProjectAccessError.invalidTarget(path)
            }
            let canonical = canonicalPath(path)
            byPath[canonical.path] = canonical
        }
        return byPath.values.sorted { $0.path < $1.path }
    }

    private func canonicalPath(_ path: URL) -> URL {
        path.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private func ensureRootDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ProjectAccessError.authorityUnavailable
        }
        guard Darwin.chmod(rootDirectory.path, mode_t(0o700)) == 0 else {
            throw ProjectAccessError.authorityUnavailable
        }
    }

    private func openCoordinator() throws -> Int32 {
        let url = rootDirectory.appendingPathComponent(".coordinator.lock")
        let descriptor = openDescriptor(
            at: url,
            flags: O_CREAT | O_RDWR | O_CLOEXEC,
            mode: mode_t(0o600)
        )
        guard descriptor >= 0 else {
            throw ProjectAccessError.authorityUnavailable
        }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            closeDescriptor(descriptor)
            throw ProjectAccessError.authorityUnavailable
        }
        return descriptor
    }

    private func acquireCoordinator(
        deadline: ContinuousClock.Instant
    ) async throws -> Int32 {
        let descriptor = try openCoordinator()
        do {
            while true {
                try Task.checkCancellation()
                guard ContinuousClock.now < deadline else {
                    throw ProjectAccessError.deadlineExceeded
                }
                if rupaFlock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                    return descriptor
                }
                let errorNumber = errno
                guard errorNumber == EWOULDBLOCK || errorNumber == EAGAIN else {
                    throw ProjectAccessError.authorityUnavailable
                }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        } catch {
            closeDescriptor(descriptor)
            throw error
        }
    }

    private func tryAcquireCoordinatorImmediately() -> Int32? {
        let descriptor: Int32
        do {
            descriptor = try openCoordinator()
        } catch {
            return nil
        }
        guard rupaFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            closeDescriptor(descriptor)
            return nil
        }
        return descriptor
    }

    private func openLockFile(at url: URL) throws -> Int32 {
        let descriptor = openDescriptor(
            at: url,
            flags: O_CREAT | O_RDWR | O_CLOEXEC,
            mode: mode_t(0o600)
        )
        guard descriptor >= 0,
              Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            if descriptor >= 0 {
                closeDescriptor(descriptor)
            }
            throw ProjectAccessError.authorityUnavailable
        }
        return descriptor
    }

    private func openSourceIfPresent(
        at path: URL,
        required: Bool
    ) throws -> (descriptor: Int32?, identity: FileIdentity?) {
        guard let pathIdentity = fileIdentity(at: path) else {
            let errorNumber = errno
            if errorNumber == ENOENT, !required {
                return (nil, nil)
            }
            if errorNumber == ENOENT {
                throw ProjectAccessError.invalidTarget(path)
            }
            throw ProjectAccessError.authorityUnavailable
        }
        guard isRegularFile(at: path) else {
            throw ProjectAccessError.invalidTarget(path)
        }
        let descriptor = openDescriptor(
            at: path,
            // O_NONBLOCK prevents a raced FIFO/device from making lease
            // acquisition unbounded before the descriptor type is checked.
            flags: O_RDONLY | O_NONBLOCK | O_CLOEXEC,
            mode: mode_t(0)
        )
        guard descriptor >= 0 else {
            let errorNumber = errno
            if errorNumber == ENOENT {
                throw ProjectAccessError.fileAuthorityLost(path)
            }
            throw ProjectAccessError.authorityUnavailable
        }
        guard let descriptorIdentity = fileIdentity(ofDescriptor: descriptor),
              isRegularFile(descriptor: descriptor),
              descriptorIdentity == pathIdentity,
              let currentIdentity = fileIdentity(at: path),
              currentIdentity == descriptorIdentity else {
            closeDescriptor(descriptor)
            throw ProjectAccessError.fileAuthorityLost(path)
        }
        return (descriptor, descriptorIdentity)
    }

    private func openExistingSource(at path: URL) throws -> Int32 {
        let descriptor = openDescriptor(
            at: path,
            flags: O_RDONLY | O_NONBLOCK | O_CLOEXEC,
            mode: mode_t(0)
        )
        guard descriptor >= 0,
              isRegularFile(descriptor: descriptor) else {
            if descriptor >= 0 {
                closeDescriptor(descriptor)
            }
            throw ProjectAccessError.fileAuthorityLost(path)
        }
        return descriptor
    }

    private func currentIdentityForValidation(at path: URL) throws -> FileIdentity? {
        if let identity = fileIdentity(at: path) {
            return identity
        }
        let errorNumber = errno
        if errorNumber == ENOENT {
            return nil
        }
        throw ProjectAccessError.fileAuthorityLost(path)
    }

    private func lockURL(for path: URL) -> URL {
        rootDirectory.appendingPathComponent("\(Self.pathHash(path)).lock")
    }

    private static func pathHash(_ path: URL) -> String {
        let digest = SHA256.hash(data: Data(path.path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileIdentity(at path: URL) -> FileIdentity? {
        var info = stat()
        let result = path.path.withCString { rupaStat($0, &info) }
        guard result == 0 else {
            return nil
        }
        return FileIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino)
        )
    }

    private func fileIdentity(ofDescriptor descriptor: Int32) -> FileIdentity? {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else {
            return nil
        }
        return FileIdentity(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino)
        )
    }

    private func isRegularFile(descriptor: Int32) -> Bool {
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else {
            return false
        }
        return (info.st_mode & S_IFMT) == S_IFREG
    }

    private func isRegularFile(at path: URL) -> Bool {
        var info = stat()
        guard path.path.withCString({ rupaStat($0, &info) }) == 0 else {
            return false
        }
        return (info.st_mode & S_IFMT) == S_IFREG
    }

    private func openDescriptor(
        at url: URL,
        flags: Int32,
        mode: mode_t
    ) -> Int32 {
        url.path.withCString { Darwin.open($0, flags, mode) }
    }

    private func closeDescriptor(_ descriptor: Int32) {
        _ = Darwin.close(descriptor)
    }

    private func unlockAndClose(heldPath: HeldPath, unlink: Bool) {
        _ = rupaFlock(heldPath.lockDescriptor, LOCK_UN)
        closeDescriptor(heldPath.lockDescriptor)
        if let sourceDescriptor = heldPath.sourceDescriptor {
            closeDescriptor(sourceDescriptor)
        }
        if unlink {
            _ = heldPath.lockURL.path.withCString { Darwin.unlink($0) }
        }
    }

    private func unlockAndCloseCoordinator(_ descriptor: Int32) {
        _ = rupaFlock(descriptor, LOCK_UN)
        closeDescriptor(descriptor)
    }
}
