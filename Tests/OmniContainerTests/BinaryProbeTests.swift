import Testing
@testable import OmniContainer

@Suite("BinaryProbe")
struct BinaryProbeTests {
    @Test("detects ELF binary")
    func detectsELF() {
        let elfMagic: [UInt8] = [0x7f, 0x45, 0x4c, 0x46, 0x02, 0x01]
        #expect(BinaryProbe.detect(elfMagic) == .elf)
    }

    @Test("detects WASM binary")
    func detectsWASM() {
        let wasmMagic: [UInt8] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00]
        #expect(BinaryProbe.detect(wasmMagic) == .wasm)
    }

    @Test("detects script")
    func detectsScript() {
        let script: [UInt8] = Array("#!/bin/sh\necho hello".utf8)
        #expect(BinaryProbe.detect(script) == .script)
    }

    @Test("returns unknown for too-short data")
    func tooShort() {
        #expect(BinaryProbe.detect([0x7f]) == .unknown)
        #expect(BinaryProbe.detect([]) == .unknown)
    }

    @Test("returns unknown for random data")
    func randomData() {
        let random: [UInt8] = [0xCA, 0xFE, 0xBA, 0xBE]
        #expect(BinaryProbe.detect(random) == .unknown)
    }
}
