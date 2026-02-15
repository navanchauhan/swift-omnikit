import XCTest

@testable import OmniAICore

final class ModelCatalogTests: XCTestCase {
    func testModelCatalogLookupByIdAndAlias() {
        let catalog = ModelCatalog.default
        XCTAssertNotNil(catalog.getModelInfo("gpt-5.2"))
        XCTAssertNotNil(catalog.getModelInfo("opus"))
        XCTAssertNotNil(catalog.getModelInfo("latest-groq"))
    }

    func testModelCatalogListAndLatest() {
        let catalog = ModelCatalog.default
        let anthropic = catalog.listModels(provider: "anthropic")
        XCTAssertFalse(anthropic.isEmpty)

        let latest = catalog.getLatestModel(provider: "anthropic")
        XCTAssertEqual(latest?.provider, "anthropic")
    }
}
