import Foundation
import Testing
@testable import OmniContainer

@Suite("Apk Install", .serialized)
struct ApkInstallTests {
    @Test("network-enabled Alpine can install ripgrep and run rg", .enabled(if: isNetworkTestEnabled))
    func apkAddRipgrepAndRunRg() async throws {
        let rootFS = try await ImageStore.shared.resolve("alpine:minirootfs")
        let spec = ContainerSpec(
            imageRef: "alpine:minirootfs",
            capabilities: [.network]
        )
        let container = ContainerActor(config: spec, rootFS: rootFS)
        try await container.start()

        let resolvConf = (try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8))
            ?? "nameserver 8.8.8.8\nnameserver 8.8.4.4\n"
        try await container.writeFile(path: "etc/resolv.conf", content: resolvConf)

        let result = try await container.exec(
            command: "apk add ripgrep && pwd && rg 'Alpine Linux' etc/os-release && rg --version",
            timeoutMs: 180_000
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("\n/\n") || result.stdout.hasPrefix("/\n"))
        #expect(!result.stdout.contains("/SystemRoot"))
        #expect(result.stdout.contains("Alpine Linux"))
        #expect(result.stdout.contains("ripgrep"))
        #expect(result.stdout.contains("14.1.1") || result.stdout.contains("14."))
    }
}

private let isNetworkTestEnabled = ProcessInfo.processInfo.environment["OMNIKIT_NETWORK_TESTS"] == "1"
