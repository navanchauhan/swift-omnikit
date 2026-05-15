#if os(Linux)
import Glibc
import Dispatch
import Foundation

public typealias sa_family_t = Glibc.sa_family_t
public typealias in_port_t = Glibc.in_port_t
public typealias in_addr = Glibc.in_addr
public typealias sockaddr = Glibc.sockaddr
public typealias sockaddr_in = Glibc.sockaddr_in
public typealias socklen_t = Glibc.socklen_t
public typealias fd_set = Glibc.fd_set
public typealias timeval = Glibc.timeval
public typealias natural_t = UInt32
public typealias integer_t = Int32
public typealias mach_msg_type_number_t = UInt32
public typealias processor_info_array_t = UnsafeMutablePointer<integer_t>
public typealias kern_return_t = Int32
public typealias mach_port_t = UInt32
public typealias vm_address_t = UInt
public typealias vm_size_t = UInt

public extension sockaddr_in {
    var sin_len: UInt8 {
        get { 0 }
        set { _ = newValue }
    }
}

public let O_EVTONLY: Int32 = Glibc.O_RDONLY
public let MAXPATHLEN: Int32 = 1024
public let PROC_PIDVNODEPATHINFO: Int32 = 0
public let KERN_SUCCESS: kern_return_t = 0
public let PROCESSOR_CPU_LOAD_INFO: Int32 = 2
public let CPU_STATE_USER: Int32 = 0
public let CPU_STATE_SYSTEM: Int32 = 1
public let CPU_STATE_IDLE: Int32 = 2
public let CPU_STATE_NICE: Int32 = 3
public let CPU_STATE_MAX: Int32 = 4
public let mach_task_self_: mach_port_t = 0

public typealias _OmniDarwinPathBuffer = (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)

public func _omniDarwinZeroPathBuffer() -> _OmniDarwinPathBuffer {
    (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

public struct vnode_info_path {
    public var vip_path: _OmniDarwinPathBuffer
    public init() {
        vip_path = _omniDarwinZeroPathBuffer()
    }
}

public struct proc_vnodepathinfo {
    public var pvi_cdir: vnode_info_path
    public init() {
        pvi_cdir = vnode_info_path()
    }
}

public func socket(_ domain: Int32, _ type: Int32, _ protocol: Int32) -> Int32 {
    Glibc.socket(domain, type, `protocol`)
}

public func socket(_ domain: Int32, _ type: Glibc.__socket_type, _ protocol: Int32) -> Int32 {
    Glibc.socket(domain, Int32(type.rawValue), `protocol`)
}

@_disfavoredOverload
public func close(_ fd: Int32) -> Int32 {
    Glibc.close(fd)
}

public func fcntl(_ fd: Int32, _ cmd: Int32, _ value: Int32) -> Int32 {
    Glibc.fcntl(fd, cmd, value)
}

public func connect(_ fd: Int32, _ addr: UnsafePointer<sockaddr>?, _ len: socklen_t) -> Int32 {
    Glibc.connect(fd, addr, len)
}

public func select(
    _ nfds: Int32,
    _ readfds: UnsafeMutablePointer<fd_set>?,
    _ writefds: UnsafeMutablePointer<fd_set>?,
    _ exceptfds: UnsafeMutablePointer<fd_set>?,
    _ timeout: UnsafeMutablePointer<timeval>?
) -> Int32 {
    Glibc.select(nfds, readfds, writefds, exceptfds, timeout)
}

public func getsockopt(
    _ fd: Int32,
    _ level: Int32,
    _ optname: Int32,
    _ optval: UnsafeMutableRawPointer?,
    _ optlen: UnsafeMutablePointer<socklen_t>?
) -> Int32 {
    Glibc.getsockopt(fd, level, optname, optval, optlen)
}

public func __darwin_fd_set(_ fd: Int32, _ set: inout fd_set) {
    let intOffset = Int(fd) / (8 * MemoryLayout<Int>.size)
    let bitOffset = Int(fd) % (8 * MemoryLayout<Int>.size)
    withUnsafeMutablePointer(to: &set) { pointer in
        pointer.withMemoryRebound(to: Int.self, capacity: 16) { words in
            words[intOffset] |= 1 << bitOffset
        }
    }
}

public func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer!, _ buffersize: Int32) -> Int32 {
    _ = arg
    guard flavor == PROC_PIDVNODEPATHINFO,
          pid > 0,
          let buffer,
          buffersize >= Int32(MemoryLayout<proc_vnodepathinfo>.size) else {
        return 0
    }

    let linkPath = "/proc/\(pid)/cwd"
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let count = readlink(linkPath, &pathBuffer, pathBuffer.count - 1)
    guard count > 0 else { return 0 }
    pathBuffer[Int(count)] = 0

    let info = buffer.bindMemory(to: proc_vnodepathinfo.self, capacity: 1)
    info.pointee = proc_vnodepathinfo()
    withUnsafeMutableBytes(of: &info.pointee.pvi_cdir.vip_path) { rawBuffer in
        let limit = min(rawBuffer.count - 1, Int(count))
        for index in 0..<limit {
            rawBuffer[index] = UInt8(bitPattern: pathBuffer[index])
        }
        rawBuffer[limit] = 0
    }
    return Int32(MemoryLayout<proc_vnodepathinfo>.size)
}

public func mach_host_self() -> mach_port_t { 0 }

private final class _OmniDarwinProcessorInfoState: @unchecked Sendable {
    static let shared = _OmniDarwinProcessorInfoState()

    private let lock = NSLock()
    private var baselineRows: [[UInt64]] = []

    func normalizedRows(from rows: [[UInt64]]) -> [[integer_t]] {
        lock.lock()
        defer { lock.unlock() }

        if baselineRows.count != rows.count || zip(baselineRows, rows).contains(where: { $0.count != $1.count }) {
            baselineRows = rows
        }

        return rows.enumerated().map { cpuIndex, row in
            row.enumerated().map { stateIndex, value in
                let baseline = baselineRows[cpuIndex][stateIndex]
                let delta = value >= baseline ? value - baseline : 0
                return integer_t(clamping: delta)
            }
        }
    }
}

public func host_processor_info(
    _ host: mach_port_t,
    _ flavor: Int32,
    _ outProcessorCount: UnsafeMutablePointer<natural_t>,
    _ outProcessorInfo: UnsafeMutablePointer<processor_info_array_t?>,
    _ outProcessorInfoCount: UnsafeMutablePointer<mach_msg_type_number_t>
) -> kern_return_t {
    _ = host
    _ = flavor
    let procStatPath = ProcessInfo.processInfo.environment["OMNIKIT_PROC_STAT_PATH"] ?? "/proc/stat"
    let rawRows = (try? String(contentsOfFile: procStatPath, encoding: .utf8))
        .map { contents in
            contents.split(separator: "\n").compactMap { line -> [UInt64]? in
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard let name = parts.first, name.hasPrefix("cpu"), name != "cpu", parts.count >= 5 else { return nil }
                let user = UInt64(parts[1]) ?? 0
                let nice = UInt64(parts[2]) ?? 0
                let system = UInt64(parts[3]) ?? 0
                let idle = UInt64(parts[4]) ?? 0
                return [user, system, idle, nice]
            }
        } ?? []
    let rows = _OmniDarwinProcessorInfoState.shared.normalizedRows(from: rawRows)
    guard !rows.isEmpty else {
        outProcessorCount.pointee = 0
        outProcessorInfo.pointee = nil
        outProcessorInfoCount.pointee = 0
        return KERN_SUCCESS
    }
    let count = rows.count * Int(CPU_STATE_MAX)
    let pointer = processor_info_array_t.allocate(capacity: count)
    for (cpuIndex, row) in rows.enumerated() {
        for stateIndex in 0..<Int(CPU_STATE_MAX) {
            pointer[cpuIndex * Int(CPU_STATE_MAX) + stateIndex] = row[stateIndex]
        }
    }
    outProcessorCount.pointee = natural_t(rows.count)
    outProcessorInfo.pointee = pointer
    outProcessorInfoCount.pointee = mach_msg_type_number_t(count)
    return KERN_SUCCESS
}

public func vm_deallocate(_ targetTask: mach_port_t, _ address: vm_address_t, _ size: vm_size_t) -> kern_return_t {
    _ = targetTask
    _ = size
    UnsafeMutablePointer<integer_t>(bitPattern: address)?.deallocate()
    return KERN_SUCCESS
}

public final class DispatchSourceFileSystemObject: @unchecked Sendable {
    private let fileDescriptor: Int32
    private let eventMask: DispatchSourceFileSystemEvent
    private let queue: DispatchQueue
    private let path: String?
    private let lock = NSLock()
    private var eventHandler: (@Sendable () -> Void)?
    private var cancelHandler: (@Sendable () -> Void)?
    private var cancelled = false
    private var resumed = false
    private var lastSnapshot: FileSnapshot?

    init(fileDescriptor: Int32, eventMask: DispatchSourceFileSystemEvent, queue: DispatchQueue?) {
        self.fileDescriptor = fileDescriptor
        self.eventMask = eventMask
        self.queue = queue ?? .global(qos: .utility)
        self.path = Self.path(for: fileDescriptor)
        self.lastSnapshot = path.flatMap(Self.snapshot)
    }

    public func setEventHandler(handler: @escaping @Sendable () -> Void) {
        lock.lock()
        eventHandler = handler
        lock.unlock()
    }

    public func setCancelHandler(handler: @escaping @Sendable () -> Void) {
        lock.lock()
        cancelHandler = handler
        lock.unlock()
    }

    public func resume() {
        lock.lock()
        guard !resumed, !cancelled else {
            lock.unlock()
            return
        }
        resumed = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.poll()
        }
    }

    public func cancel() {
        let handler: (@Sendable () -> Void)?
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        handler = cancelHandler
        lock.unlock()
        handler?()
    }

    private func poll() {
        while true {
            usleep(250_000)
            lock.lock()
            let shouldStop = cancelled
            let watchedPath = path
            let previous = lastSnapshot
            lock.unlock()
            guard !shouldStop else { return }
            guard let watchedPath else { continue }

            let next = Self.snapshot(path: watchedPath)
            guard Self.changed(from: previous, to: next, mask: eventMask) else { continue }

            lock.lock()
            lastSnapshot = next
            let handler = eventHandler
            lock.unlock()
            queue.async {
                handler?()
            }
        }
    }

    private static func changed(
        from previous: FileSnapshot?,
        to next: FileSnapshot?,
        mask: DispatchSourceFileSystemEvent
    ) -> Bool {
        if previous == nil, next != nil {
            return mask.contains(.write) || mask.contains(.rename)
        }
        if previous != nil, next == nil {
            return mask.contains(.delete) || mask.contains(.rename)
        }
        guard let previous, let next else { return false }
        if previous.device != next.device || previous.inode != next.inode {
            return mask.contains(.rename) || mask.contains(.write)
        }
        return previous.size != next.size ||
            previous.modifiedSeconds != next.modifiedSeconds ||
            previous.modifiedNanoseconds != next.modifiedNanoseconds
    }

    private static func path(for fileDescriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let fdPath = "/proc/self/fd/\(fileDescriptor)"
        let count = fdPath.withCString { readlink($0, &buffer, buffer.count - 1) }
        guard count > 0 else { return nil }
        var path = String(decoding: buffer.prefix(Int(count)).map(UInt8.init(bitPattern:)), as: UTF8.self)
        if path.hasSuffix(" (deleted)") {
            path.removeLast(" (deleted)".count)
        }
        return path
    }

    private static func snapshot(path: String) -> FileSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        let modified = (attributes[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        let modifiedNanoseconds = Int64((modified.timeIntervalSince1970 * 1_000_000_000).rounded())
        return FileSnapshot(
            device: (attributes[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modifiedSeconds: Int64(modified.timeIntervalSince1970),
            modifiedNanoseconds: modifiedNanoseconds
        )
    }

    private struct FileSnapshot: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }
}

public struct DispatchSourceFileSystemEvent: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let write = DispatchSourceFileSystemEvent(rawValue: 1 << 0)
    public static let delete = DispatchSourceFileSystemEvent(rawValue: 1 << 1)
    public static let rename = DispatchSourceFileSystemEvent(rawValue: 1 << 2)
}

public extension DispatchSource {
    static func makeFileSystemObjectSource(
        fileDescriptor: Int32,
        eventMask: DispatchSourceFileSystemEvent,
        queue: DispatchQueue?
    ) -> DispatchSourceFileSystemObject {
        DispatchSourceFileSystemObject(fileDescriptor: fileDescriptor, eventMask: eventMask, queue: queue)
    }
}
#else
@_exported import Darwin
#endif
