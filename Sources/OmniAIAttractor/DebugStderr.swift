import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

func writeToAttractorStderr(_ message: String) {
    let bytes = Array(message.utf8)
    bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        #if os(Linux)
        _ = Glibc.write(STDERR_FILENO, base, raw.count)
        #else
        _ = Darwin.write(STDERR_FILENO, base, raw.count)
        #endif
    }
}
