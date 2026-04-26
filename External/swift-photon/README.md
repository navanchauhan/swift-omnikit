# swift-photon

Unofficial swift sdk to use imessages stuff with [spectrum](https://photon.codes)

## Newer API surface

The package now exposes `PhotonImessage.Session`, which keeps the gRPC channel and exposes:

- Message ops: `send`, `sendReaction`, `unreact`, `editMessage`, `unsendMessage`, `getMessage`, `listMessages`, `fetchMissedMessages`, `getEmbeddedMedia`, `getMessageStats`, `subscribeMessageEvents`
- `listMessages` now supports `before`/`after` `Date` windows and `fetchMissedMessages(cursor:)` for replay flows.
- Chat ops: `createChat`, `getChat`, `getChatCount`, `leaveChat`, `markRead`, `shareContactInfo`, `startTyping`, `stopTyping`, `getParticipants`, `subscribeChatEvents`
- Address ops: `getAddress`, `getFocusStatus`, `checkAvailability`
- Attachment ops: `getAttachment`, `getAttachmentCount`, `uploadAttachment`, `downloadAttachment`, `getLivePhoto`
- Poll ops: `createPoll`, `vote`, `unvote`, `addPollOption`, `getPoll`, `subscribePollEvents`

`send` and `createChat` both support `effectId` / screen effect IDs for expressive send styling.

To connect:

```swift
let session = try await PhotonImessage.Session.connect()
// ... call session methods ...
try await session.close()
```

`runHelloWorld()` is still available as a simple event-stream responder demo.
