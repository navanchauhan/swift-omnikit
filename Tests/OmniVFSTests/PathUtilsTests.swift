import Testing
@testable import OmniVFS

@Suite("PathUtils")
struct PathUtilsTests {

    // MARK: - validPath

    @Test("validPath accepts dot")
    func validPathDot() {
        #expect(PathUtils.validPath(".") == true)
    }

    @Test("validPath rejects empty string")
    func validPathEmpty() {
        #expect(PathUtils.validPath("") == false)
    }

    @Test("validPath rejects leading slash")
    func validPathLeadingSlash() {
        #expect(PathUtils.validPath("/foo") == false)
    }

    @Test("validPath rejects trailing slash")
    func validPathTrailingSlash() {
        #expect(PathUtils.validPath("foo/") == false)
    }

    @Test("validPath rejects dotdot components")
    func validPathDotDot() {
        #expect(PathUtils.validPath("a/../b") == false)
        #expect(PathUtils.validPath("..") == false)
    }

    @Test("validPath rejects empty components (double slash)")
    func validPathDoubleSlash() {
        #expect(PathUtils.validPath("a//b") == false)
    }

    @Test("validPath accepts normal paths")
    func validPathNormal() {
        #expect(PathUtils.validPath("a") == true)
        #expect(PathUtils.validPath("a/b/c") == true)
        #expect(PathUtils.validPath("file.txt") == true)
    }

    // MARK: - cleanPath

    @Test("cleanPath normalizes various inputs")
    func cleanPathBasic() {
        #expect(PathUtils.cleanPath("") == ".")
        #expect(PathUtils.cleanPath(".") == ".")
        #expect(PathUtils.cleanPath("a/./b") == "a/b")
        #expect(PathUtils.cleanPath("a//b") == "a/b")
        #expect(PathUtils.cleanPath("/a/b") == "/a/b")
        #expect(PathUtils.cleanPath("/") == "/")
        #expect(PathUtils.cleanPath("///") == "/")
    }

    // MARK: - joinPath

    @Test("joinPath combines paths correctly")
    func joinPathBasic() {
        #expect(PathUtils.joinPath("a", "b") == "a/b")
        #expect(PathUtils.joinPath("a/", "b") == "a/b")
        #expect(PathUtils.joinPath(".", "b") == "b")
        #expect(PathUtils.joinPath("a", ".") == "a")
        #expect(PathUtils.joinPath("", "b") == "b")
        #expect(PathUtils.joinPath("a", "/b") == "/b") // absolute b overrides
    }

    // MARK: - splitPath

    @Test("splitPath splits parent and name")
    func splitPathBasic() {
        let (p1, n1) = PathUtils.splitPath("a/b/c")
        #expect(p1 == "a/b")
        #expect(n1 == "c")

        let (p2, n2) = PathUtils.splitPath("file.txt")
        #expect(p2 == ".")
        #expect(n2 == "file.txt")

        let (p3, n3) = PathUtils.splitPath(".")
        #expect(p3 == ".")
        #expect(n3 == ".")

        let (p4, n4) = PathUtils.splitPath("/a")
        #expect(p4 == "/")
        #expect(n4 == "a")
    }

    // MARK: - matchGlob

    @Test("matchGlob star wildcard")
    func matchGlobStar() {
        #expect(PathUtils.matchGlob(pattern: "*.txt", path: "hello.txt") == true)
        #expect(PathUtils.matchGlob(pattern: "*.txt", path: "hello.md") == false)
        #expect(PathUtils.matchGlob(pattern: "*", path: "anything") == true)
        #expect(PathUtils.matchGlob(pattern: "a*c", path: "abc") == true)
        #expect(PathUtils.matchGlob(pattern: "a*c", path: "aXYZc") == true)
        #expect(PathUtils.matchGlob(pattern: "a*c", path: "aXYZd") == false)
    }

    @Test("matchGlob question mark wildcard")
    func matchGlobQuestion() {
        #expect(PathUtils.matchGlob(pattern: "a?c", path: "abc") == true)
        #expect(PathUtils.matchGlob(pattern: "a?c", path: "ac") == false)
        #expect(PathUtils.matchGlob(pattern: "???", path: "abc") == true)
        #expect(PathUtils.matchGlob(pattern: "???", path: "ab") == false)
    }

    @Test("matchGlob character class")
    func matchGlobCharClass() {
        #expect(PathUtils.matchGlob(pattern: "[abc]", path: "a") == true)
        #expect(PathUtils.matchGlob(pattern: "[abc]", path: "d") == false)
        #expect(PathUtils.matchGlob(pattern: "[a-z]", path: "m") == true)
        #expect(PathUtils.matchGlob(pattern: "[!a-z]", path: "A") == true)
        #expect(PathUtils.matchGlob(pattern: "[!a-z]", path: "a") == false)
    }

    // MARK: - isAbsolute / stripLeadingSlash

    @Test("isAbsolute and stripLeadingSlash")
    func absoluteAndStrip() {
        #expect(PathUtils.isAbsolute("/foo") == true)
        #expect(PathUtils.isAbsolute("foo") == false)
        #expect(PathUtils.stripLeadingSlash("/foo") == "foo")
        #expect(PathUtils.stripLeadingSlash("foo") == "foo")
    }
}
