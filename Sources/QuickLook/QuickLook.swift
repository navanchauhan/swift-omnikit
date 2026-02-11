// Minimal QuickLook shim.
//
// iGopherBrowser imports QuickLook to drive previews on Apple platforms. OmniKit's
// SwiftUI shim implements `quickLookPreview(_:)` as a no-op, so the module only
// needs to exist for `import QuickLook` to compile on non-Apple platforms.

