import AppKit
import Darwin

enum SingleInstanceLock {
    static func acquire(at url: URL) throws -> Int32? {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
        let code = errno
        close(descriptor)
        if code == EWOULDBLOCK { return nil }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
}
