import Foundation
import Testing
@testable import OmniContainer

@Suite("Blink Guest Node Runtime")
struct BlinkGuestNodeRuntimeTests {
    @Test("Environment strings are passed through unchanged")
    func mergesNodeOptionsIntoEnvironmentStrings() {
        let original = [
            "PATH=/usr/bin:/bin",
            "LANG=C.UTF-8",
        ]

        #expect(BlinkGuestNodeRuntime.mergedEnvironmentStrings(original) == original)
    }

    @Test("Existing NODE_OPTIONS remain untouched")
    func preservesExistingNodeOptions() {
        let original = [
            "NODE_OPTIONS=--max-old-space-size=2048 --dns-result-order=verbatim",
            "PATH=/usr/bin:/bin",
        ]

        #expect(BlinkGuestNodeRuntime.mergedEnvironmentStrings(original) == original)
    }

    @Test("Dictionary merge is a passthrough")
    func mergesDictionaryEnvironment() {
        let original = [
            "PATH": "/usr/bin:/bin",
            "NODE_OPTIONS": "--max-old-space-size=2048",
        ]

        #expect(BlinkGuestNodeRuntime.mergedEnvironment(original) == original)
    }
}
