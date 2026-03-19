import Foundation

public enum PathUtils {
    /// Validates a VFS path. Rejects paths with ".." components, empty components,
    /// or leading/trailing slashes. The path "." is valid and represents the root.
    public static func validPath(_ path: String) -> Bool {
        if path == "." { return true }
        if path.isEmpty { return false }
        if path.hasPrefix("/") || path.hasSuffix("/") { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            if component.isEmpty { return false }
            if component == ".." { return false }
        }
        return true
    }

    /// Normalize a path: remove double slashes, resolve single dots, but NOT "..".
    public static func cleanPath(_ path: String) -> String {
        if path.isEmpty { return "." }
        let isAbs = path.hasPrefix("/")
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        var result: [Substring] = []
        for component in components {
            if component == "." { continue }
            result.append(component)
        }
        if result.isEmpty {
            return isAbs ? "/" : "."
        }
        let joined = result.joined(separator: "/")
        return isAbs ? "/" + joined : joined
    }

    /// Join two path components.
    public static func joinPath(_ a: String, _ b: String) -> String {
        if a.isEmpty || a == "." { return b }
        if b.isEmpty || b == "." { return a }
        if b.hasPrefix("/") { return b }
        let trimmedA = a.hasSuffix("/") ? String(a.dropLast()) : a
        return trimmedA + "/" + b
    }

    /// Split into parent directory and filename.
    public static func splitPath(_ path: String) -> (parent: String, name: String) {
        let clean = cleanPath(path)
        if clean == "." || clean == "/" {
            return (".", clean)
        }
        guard let lastSlash = clean.lastIndex(of: "/") else {
            return (".", clean)
        }
        let parent = String(clean[clean.startIndex..<lastSlash])
        let name = String(clean[clean.index(after: lastSlash)...])
        return (parent.isEmpty ? (clean.hasPrefix("/") ? "/" : ".") : parent, name)
    }

    /// fnmatch-style glob matching supporting *, ?, and [abc] character classes.
    public static func matchGlob(pattern: String, path: String) -> Bool {
        return fnmatchImpl(
            pattern: Array(pattern.unicodeScalars),
            pi: 0,
            string: Array(path.unicodeScalars),
            si: 0
        )
    }

    /// Whether a path is absolute (starts with /).
    public static func isAbsolute(_ path: String) -> Bool {
        return path.hasPrefix("/")
    }

    /// Remove leading / if present.
    public static func stripLeadingSlash(_ path: String) -> String {
        if path.hasPrefix("/") {
            return String(path.dropFirst())
        }
        return path
    }

    // MARK: - Private

    private static func fnmatchImpl(
        pattern: [Unicode.Scalar],
        pi: Int,
        string: [Unicode.Scalar],
        si: Int
    ) -> Bool {
        var pi = pi
        var si = si
        while pi < pattern.count {
            let pc = pattern[pi]
            switch pc {
            case "*":
                // Skip consecutive stars.
                var nextPi = pi + 1
                while nextPi < pattern.count && pattern[nextPi] == "*" {
                    nextPi += 1
                }
                // If star is at end of pattern, match rest.
                if nextPi == pattern.count { return true }
                // Try matching rest of pattern at each position.
                for pos in si...string.count {
                    if fnmatchImpl(pattern: pattern, pi: nextPi, string: string, si: pos) {
                        return true
                    }
                }
                return false
            case "?":
                guard si < string.count else { return false }
                pi += 1
                si += 1
            case "[":
                guard si < string.count else { return false }
                let ch = string[si]
                pi += 1
                var negate = false
                if pi < pattern.count && pattern[pi] == "!" {
                    negate = true
                    pi += 1
                }
                var matched = false
                var first = true
                while pi < pattern.count && (first || pattern[pi] != "]") {
                    first = false
                    let lo = pattern[pi]
                    pi += 1
                    if pi + 1 < pattern.count && pattern[pi] == "-" {
                        pi += 1
                        let hi = pattern[pi]
                        pi += 1
                        if ch >= lo && ch <= hi { matched = true }
                    } else {
                        if ch == lo { matched = true }
                    }
                }
                // Skip closing ].
                if pi < pattern.count && pattern[pi] == "]" { pi += 1 }
                if matched == negate { return false }
                si += 1
            default:
                guard si < string.count && string[si] == pc else { return false }
                pi += 1
                si += 1
            }
        }
        return si == string.count
    }
}
