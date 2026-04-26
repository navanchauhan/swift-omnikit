import Foundation

public protocol MediaDescriptionProviding: Sendable {
    func describeImageAttachment(_ attachment: StagedAttachment) async throws -> String?
}
