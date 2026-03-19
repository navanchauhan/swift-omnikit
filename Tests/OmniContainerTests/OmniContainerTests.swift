import Testing
@testable import OmniContainer

@Test func containerIDDescription() {
    let id = ContainerID()
    #expect(!id.description.isEmpty)
}
