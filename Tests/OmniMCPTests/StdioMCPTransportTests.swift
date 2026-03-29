import Foundation
import Testing
@testable import OmniMCP

@Suite
struct StdioMCPTransportTests {
    @Test
    func stdioTransportEchoesSingleLineAndDisconnectsCleanly() async throws {
        let transport = StdioMCPTransport(
            command: "/bin/sh",
            args: ["-c", "while IFS= read -r line; do printf '%s\\n' \"$line\"; break; done"]
        )

        try await transport.connect()
        defer {
            Task {
                await transport.disconnect()
            }
        }

        try await transport.send(Data(#"{"jsonrpc":"2.0","id":1}"#.utf8))

        let stream = try await transport.messageStream()
        var iterator = stream.makeAsyncIterator()
        let message = try #require(try await iterator.next())
        #expect(String(decoding: message, as: UTF8.self) == #"{"jsonrpc":"2.0","id":1}"#)
    }
}
