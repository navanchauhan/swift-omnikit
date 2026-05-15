import Glibc
import Foundation
import OmniDarwin
import Testing

@Test
func sockaddrInAcceptsDarwinSinLenCompatibility() {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

    #expect(address.sin_len == 0)
}

@Test
func unqualifiedPOSIXCloseRemainsAvailableAlongsideOmniDarwinClose() {
    let glibcResult = close(-1)
    let omniDarwinResult = OmniDarwin.close(-1)

    #expect(glibcResult == -1)
    #expect(omniDarwinResult == -1)
}

@Test
func darwinSocketAcceptsUnqualifiedLinuxPOSIXConstants() {
    let sock = OmniDarwin.socket(AF_INET, SOCK_STREAM, 0)
    #expect(sock >= 0)
    if sock >= 0 {
        #expect(OmniDarwin.fcntl(sock, F_SETFL, O_NONBLOCK) >= 0)
        #expect(OmniDarwin.close(sock) == 0)
    }

    #expect(inet_addr("127.0.0.1") != in_addr_t.max)
    #expect(EINPROGRESS > 0)
    #expect(SOL_SOCKET > 0)
    #expect(SO_ERROR > 0)
}

@Test
func hostProcessorInfoNormalizesLargeLinuxProcStatCounters() throws {
    let procStatURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("omnidarwin-proc-stat-\(UUID().uuidString)")
    let previous = getenv("OMNIKIT_PROC_STAT_PATH").map { String(cString: $0) }
    defer {
        try? FileManager.default.removeItem(at: procStatURL)
        if let previous {
            setenv("OMNIKIT_PROC_STAT_PATH", previous, 1)
        } else {
            unsetenv("OMNIKIT_PROC_STAT_PATH")
        }
    }
    setenv("OMNIKIT_PROC_STAT_PATH", procStatURL.path, 1)

    func writeStat(user: UInt64, nice: UInt64, system: UInt64, idle: UInt64) throws {
        var lines = ["cpu  \(user) \(nice) \(system) \(idle) 0 0 0 0 0 0"]
        for cpu in 0..<7 {
            lines.append("cpu\(cpu) \(user + UInt64(cpu)) \(nice + UInt64(cpu)) \(system + UInt64(cpu)) \(idle + UInt64(cpu)) 0 0 0 0 0 0")
        }
        try (lines.joined(separator: "\n") + "\n").write(to: procStatURL, atomically: true, encoding: .utf8)
    }

    func readRows() -> [[integer_t]] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        #expect(result == KERN_SUCCESS)
        guard let info else { return [] }
        defer {
            _ = vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        return (0..<Int(cpuCount)).map { cpu in
            (0..<Int(CPU_STATE_MAX)).map { state in
                info[cpu * Int(CPU_STATE_MAX) + state]
            }
        }
    }

    try writeStat(
        user: UInt64(Int32.max) + 10_000,
        nice: UInt64(Int32.max) + 20_000,
        system: UInt64(Int32.max) + 30_000,
        idle: UInt64(Int32.max) + 40_000
    )
    #expect(readRows() == Array(repeating: [0, 0, 0, 0], count: 7))

    try writeStat(
        user: UInt64(Int32.max) + 10_125,
        nice: UInt64(Int32.max) + 20_050,
        system: UInt64(Int32.max) + 30_075,
        idle: UInt64(Int32.max) + 40_200
    )
    let rows = readRows()
    #expect(rows.count == 7)
    #expect(rows.first == [125, 75, 200, 50])
}

@Test
func procPidInfoVnodePathInfoReportsCurrentWorkingDirectoryOnLinux() {
    var info = proc_vnodepathinfo()
    let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)

    let result = proc_pidinfo(
        ProcessInfo.processInfo.processIdentifier,
        PROC_PIDVNODEPATHINFO,
        0,
        &info,
        size
    )

    #expect(result == size)
    let cwd = withUnsafePointer(to: info.pvi_cdir.vip_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cString in
            String(cString: cString)
        }
    }
    #expect(cwd == FileManager.default.currentDirectoryPath)
}

@Test
func fileSystemObjectSourceReportsLinuxFileWrites() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("omnidarwin-file-watch-\(UUID().uuidString).txt")
    try "before".write(to: url, atomically: true, encoding: .utf8)
    let fd = open(url.path, O_EVTONLY)
    #expect(fd >= 0)
    guard fd >= 0 else { return }

    let semaphore = DispatchSemaphore(value: 0)
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .delete, .rename],
        queue: .global(qos: .utility)
    )
    source.setEventHandler {
        semaphore.signal()
    }
    source.setCancelHandler {
        close(fd)
    }
    source.resume()
    defer {
        source.cancel()
        try? FileManager.default.removeItem(at: url)
    }

    try "after".write(to: url, atomically: true, encoding: .utf8)
    #expect(semaphore.wait(timeout: .now() + 2) == .success)
}

@Test
func fileSystemObjectSourceReportsLinuxDirectoryMutations() throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("omnidarwin-directory-watch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let fd = open(directoryURL.path, O_EVTONLY)
    #expect(fd >= 0)
    guard fd >= 0 else { return }

    let semaphore = DispatchSemaphore(value: 0)
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .delete, .rename],
        queue: .global(qos: .utility)
    )
    source.setEventHandler {
        semaphore.signal()
    }
    source.setCancelHandler {
        close(fd)
    }
    source.resume()
    defer {
        source.cancel()
        try? FileManager.default.removeItem(at: directoryURL)
    }

    let childURL = directoryURL.appendingPathComponent("created.md")
    try "created".write(to: childURL, atomically: true, encoding: .utf8)
    #expect(semaphore.wait(timeout: .now() + 2) == .success)
}
