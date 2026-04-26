import PhotonImessage
import Foundation

@main
@MainActor
struct PlaceholderMain {
  private static func runStep(
    _ label: String,
    _ body: @MainActor @Sendable () async throws -> Void
  ) async {
    do {
      try await body()
    } catch {
      print("[Demo][\(label)] \(error)")
    }
  }

  static func main() async {
    do {
      let session = try await PhotonImessage.Session.connect()
      defer {
        Task { await session.close() }
      }

      let address = "+1 720 882 8227"
      let normalizedAddress = address.replacingOccurrences(of: " ", with: "")
      print("[Demo] connected to \(session.serverHost):\(session.serverPort)")

      // Message send + fetch demo
      print("[Demo] creating chat and sending message...")
      let createResp = try await session.createChat(
        addresses: [normalizedAddress],
        message: "hello from swift-photon demo",
        service: "iMessage",
        effectId: "com.apple.MobileSMS.effect.impact"
      )
      let chatGuid = createResp.chat.guid
      print("[Demo] chat guid: \(chatGuid)")
      print("[Demo] chat type: \(createResp.chat.isGroup ? "group" : "dm"), archive?: \(createResp.chat.isArchived)")

      let messageGuid: String
      do {
        let listed = try await session.listMessages(
          chatGuid: chatGuid,
          sort: .descending,
          limit: 1,
          withChats: false,
          withAttachments: false
        )
        guard let latest = listed.messages.first else {
          throw PhotonImessageError.badCloudResponse(statusCode: 0, body: "No message returned after createChat")
        }
        messageGuid = latest.guid
      } catch {
        print("[Demo] could not resolve recent message guid from listMessages: \(error)")
        messageGuid = ""
      }

      if !messageGuid.isEmpty {
        print("[Demo] latest message guid: \(messageGuid)")

        await runStep("getMessage") {
          let message = try await session.getMessage(guid: messageGuid)
          print("[Demo] fetched message: \(message.text.isEmpty ? "(empty)" : message.text)")
        }

        await runStep("sendFullScreenEffect") {
          _ = try await session.send(
            chatGuid: chatGuid,
            message: "full screen effect 🚀",
            effectId: "com.apple.messages.effect.CKSpotlightEffect"
          )
          print("[Demo] full-screen effect message sent")
        }

        await runStep("sendReaction") {
          _ = try await session.sendReaction(
            chatGuid: chatGuid,
            messageGuid: messageGuid,
            reaction: "love",
            partIndex: 0
          )
          print("[Demo] reaction sent")
        }
        await runStep("unreact") {
          _ = try await session.unreact(
            chatGuid: chatGuid,
            messageGuid: messageGuid,
            reaction: "love",
            partIndex: 0
          )
          print("[Demo] reaction removed")
        }
      }

      // Poll creation + optional vote flow
      print("[Demo] creating poll...")
      let pollMessageGuid: String
      do {
        let pollReceipt = try await session.createPoll(
          chatGuid: chatGuid,
          title: "Lunch idea?",
          options: ["Pizza", "Sushi", "Tacos"]
        )
        pollMessageGuid = pollReceipt.guid
        print("[Demo] poll receipt guid: \(pollMessageGuid)")
      } catch {
        print("[Demo] createPoll failed: \(error)")
        pollMessageGuid = ""
      }

      if !pollMessageGuid.isEmpty {
        do {
          let poll = try await session.getPoll(messageGuid: pollMessageGuid)
        if let option = poll.options.first(where: { !$0.optionIdentifier.isEmpty }) {
          print("[Demo] voting on option id=\(option.optionIdentifier)")
          await runStep("votePoll") {
            _ = try await session.vote(
              chatGuid: chatGuid,
              pollMessageGuid: pollMessageGuid,
              optionIdentifier: option.optionIdentifier
            )
            print("[Demo] poll vote sent")
          }
          await runStep("unvotePoll") {
            _ = try await session.unvote(
              chatGuid: chatGuid,
              pollMessageGuid: pollMessageGuid
            )
            print("[Demo] poll unvote sent")
          }
          } else {
            print("[Demo] poll returned no option identifiers; skipping vote")
          }
        } catch {
          print("[Demo] getPoll failed: \(error)")
        }
      }

      // Address + chat operations
      await runStep("getAddressInfo") {
        let addressInfo = try await session.getAddress(address: normalizedAddress)
        print("[Demo] address: \(addressInfo.address), service: \(addressInfo.service), country: \(addressInfo.country)")
      }
      await runStep("checkAvailability") {
        let availability = try await session.checkAvailability(address: normalizedAddress)
        let focus = try await session.getFocusStatus(address: normalizedAddress)
        print("[Demo] availability(iMessage): \(availability), focused: \(focus)")
      }
      await runStep("getChat") {
        let chat = try await session.getChat(guid: chatGuid)
        print("[Demo] chat fetched back, service: \(chat.service), participants: \(chat.participants.count)")
      }
      await runStep("getChatCount") {
        let chatCount = try await session.getChatCount(includeArchived: false)
        print("[Demo] chat count: \(chatCount)")
      }

      await runStep("getParticipants") {
        let participants = try await session.getParticipants(chatGuid: chatGuid)
        print("[Demo] participants: \(participants.map { $0.address }.joined(separator: ", "))")
      }
      await runStep("listMessages") {
        let messages = try await session.listMessages(
          chatGuid: chatGuid,
          sort: .descending,
          limit: 20,
          withChats: true,
          withAttachments: false
        )
        print("[Demo] listed messages: \(messages.messages.count), total meta: \(messages.meta.total)")
      }
      await runStep("getMessageStats") {
        let stats = try await session.getMessageStats()
        print("[Demo] message stats total/sent/received = \(stats.total)/\(stats.sent)/\(stats.received)")
      }
      await runStep("getAttachmentCount") {
        let attachmentCount = try await session.getAttachmentCount()
        print("[Demo] attachment count: \(attachmentCount)")
      }
      await runStep("getEmbeddedMedia") {
        if !messageGuid.isEmpty {
          let media = try await session.getEmbeddedMedia(chatGuid: chatGuid, messageGuid: messageGuid)
          print("[Demo] embedded media for latest message: \(media.count)")
        }
      }

      try await session.startTyping(chatGuid: chatGuid)
      try await Task.sleep(nanoseconds: 500_000_000)
      try await session.stopTyping(chatGuid: chatGuid)

      print("[Demo] completed advanced feature flow.")
      try await session.markRead(chatGuid: chatGuid)
    } catch {
      print("Error: \(error)")
    }
  }
}
