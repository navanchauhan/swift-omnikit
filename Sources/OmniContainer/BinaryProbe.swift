/// Detected binary format from magic bytes.
public enum BinaryFormat: Sendable {
    case elf
    case wasm
    case script
    case unknown
}

/// Detects the binary format of data by inspecting magic bytes.
public struct BinaryProbe: Sendable {
    public static func detect(_ data: [UInt8]) -> BinaryFormat {
        guard data.count >= 4 else { return .unknown }
        // ELF: 7f 45 4c 46
        if data[0] == 0x7f && data[1] == 0x45 && data[2] == 0x4c && data[3] == 0x46 {
            return .elf
        }
        // WASM: 00 61 73 6d
        if data[0] == 0x00 && data[1] == 0x61 && data[2] == 0x73 && data[3] == 0x6d {
            return .wasm
        }
        // Script: #!
        if data[0] == 0x23 && data[1] == 0x21 {
            return .script
        }
        return .unknown
    }
}
