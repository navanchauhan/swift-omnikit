import Foundation
import Testing
@testable import OmniContainer

@Suite("Blink Guest Node Runtime", .serialized)
struct BlinkGuestNodeRuntimeTests {
    private let allowEnvVar = "OMNIKIT_BLINK_ALLOW_NODE_GUEST_JIT"
    private let forceEnvVar = "OMNIKIT_BLINK_FORCE_NODE_GUEST_JITLESS"

    private func withForcedGuestJitless(_ body: () -> Void) {
        let original = ProcessInfo.processInfo.environment[forceEnvVar]
        setenv(forceEnvVar, "1", 1)
        defer {
            if let original {
                setenv(forceEnvVar, original, 1)
            } else {
                unsetenv(forceEnvVar)
            }
        }
        body()
    }

    private func withAllowedGuestJit(_ body: () -> Void) {
        let original = ProcessInfo.processInfo.environment[allowEnvVar]
        setenv(allowEnvVar, "1", 1)
        defer {
            if let original {
                setenv(allowEnvVar, original, 1)
            } else {
                unsetenv(allowEnvVar)
            }
        }
        body()
    }

    private var expectsInjectedNodeOptionsByDefault: Bool {
        #if arch(arm64) && canImport(Darwin)
        true
        #else
        false
        #endif
    }

    @Test("Environment strings follow the platform default")
    func mergesNodeOptionsIntoEnvironmentStrings() {
        let original = [
            "PATH=/usr/bin:/bin",
            "LANG=C.UTF-8",
        ]

        let merged = BlinkGuestNodeRuntime.mergedEnvironmentStrings(original)
        if expectsInjectedNodeOptionsByDefault {
            #expect(merged == original + ["NODE_OPTIONS=--jitless"])
        } else {
            #expect(merged == original)
        }
    }

    @Test("Allow env disables the default guest jitless policy")
    func allowsGuestJitWhenRequested() {
        withAllowedGuestJit {
            let original = [
                "PATH=/usr/bin:/bin",
                "LANG=C.UTF-8",
            ]

            #expect(BlinkGuestNodeRuntime.mergedEnvironmentStrings(original) == original)
        }
    }

    @Test("Forced guest jitless is injected into environment strings")
    func injectsNodeOptionsWhenForced() {
        withForcedGuestJitless {
            let original = [
                "PATH=/usr/bin:/bin",
                "LANG=C.UTF-8",
            ]

            #expect(BlinkGuestNodeRuntime.mergedEnvironmentStrings(original) == original + ["NODE_OPTIONS=--jitless"])
        }
    }

    @Test("Existing NODE_OPTIONS follow the platform default")
    func preservesExistingNodeOptions() {
        let original = [
            "NODE_OPTIONS=--max-old-space-size=2048 --dns-result-order=verbatim",
            "PATH=/usr/bin:/bin",
        ]

        let merged = BlinkGuestNodeRuntime.mergedEnvironmentStrings(original)
        if expectsInjectedNodeOptionsByDefault {
            #expect(merged == [
                "NODE_OPTIONS=--max-old-space-size=2048 --dns-result-order=verbatim --jitless",
                "PATH=/usr/bin:/bin",
            ])
        } else {
            #expect(merged == original)
        }
    }

    @Test("Existing NODE_OPTIONS get jitless appended when forced")
    func appendsForcedJitlessToExistingNodeOptions() {
        withForcedGuestJitless {
            let original = [
                "NODE_OPTIONS=--max-old-space-size=2048 --dns-result-order=verbatim",
                "PATH=/usr/bin:/bin",
            ]

            let merged = BlinkGuestNodeRuntime.mergedEnvironmentStrings(original)
            #expect(merged == [
                "NODE_OPTIONS=--max-old-space-size=2048 --dns-result-order=verbatim --jitless",
                "PATH=/usr/bin:/bin",
            ])
        }
    }

    @Test("Dictionary merge follows the platform default")
    func mergesDictionaryEnvironment() {
        let original = [
            "PATH": "/usr/bin:/bin",
            "NODE_OPTIONS": "--max-old-space-size=2048",
        ]

        let merged = BlinkGuestNodeRuntime.mergedEnvironment(original)
        if expectsInjectedNodeOptionsByDefault {
            #expect(merged == [
                "PATH": "/usr/bin:/bin",
                "NODE_OPTIONS": "--max-old-space-size=2048 --jitless",
            ])
        } else {
            #expect(merged == original)
        }
    }

    @Test("Dictionary merge injects jitless when forced")
    func mergesDictionaryEnvironmentWhenForced() {
        withForcedGuestJitless {
            let original = [
                "PATH": "/usr/bin:/bin",
                "NODE_OPTIONS": "--max-old-space-size=2048",
            ]

            let merged = BlinkGuestNodeRuntime.mergedEnvironment(original)
            #expect(merged == [
                "PATH": "/usr/bin:/bin",
                "NODE_OPTIONS": "--max-old-space-size=2048 --jitless",
            ])
        }
    }

    @Test("Allow env overrides a forced platform default")
    func allowsGuestJitAgainstPlatformDefault() {
        withAllowedGuestJit {
            let original = [
                "NODE_OPTIONS=--trace-warnings",
                "PATH=/usr/bin:/bin",
            ]

            #expect(BlinkGuestNodeRuntime.mergedEnvironmentStrings(original) == original)
        }
    }

    @Test("Existing jitless is not duplicated when forcing")
    func preservesExistingJitlessOption() {
        withForcedGuestJitless {
            let original = [
                "NODE_OPTIONS=--trace-warnings --jitless",
                "PATH=/usr/bin:/bin",
            ]

            #expect(BlinkGuestNodeRuntime.mergedEnvironmentStrings(original) == original)
        }
    }
}
