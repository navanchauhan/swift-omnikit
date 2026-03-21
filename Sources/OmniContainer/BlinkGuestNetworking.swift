import Foundation

public enum BlinkGuestNetworking {
    private static let fallbackResolvers = [
        "8.8.8.8",
        "8.8.4.4",
    ]

    public static func resolvConf(hostContents: String?) -> String {
        var resultLines: [String] = []
        var keptNameserver = false

        if let hostContents {
            for rawLine in hostContents.split(
                omittingEmptySubsequences: false,
                whereSeparator: \.isNewline
            ) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else {
                    continue
                }

                if line.hasPrefix("nameserver") {
                    let fields = line.split(whereSeparator: \.isWhitespace)
                    guard fields.count >= 2 else {
                        continue
                    }

                    let address = String(fields[1])
                    guard shouldKeepNameserver(address) else {
                        continue
                    }

                    resultLines.append("nameserver \(address)")
                    keptNameserver = true
                } else {
                    resultLines.append(line)
                }
            }
        }

        if !keptNameserver {
            resultLines.append(contentsOf: fallbackResolvers.map { "nameserver \($0)" })
        }

        return resultLines.joined(separator: "\n") + "\n"
    }

    private static func shouldKeepNameserver(_ address: String) -> Bool {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return isIPv4Address(address)
#else
        return !address.isEmpty
#endif
    }

    private static func isIPv4Address(_ value: String) -> Bool {
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else {
            return false
        }

        for octet in octets {
            guard let component = Int(octet), (0...255).contains(component) else {
                return false
            }
        }

        return true
    }
}
