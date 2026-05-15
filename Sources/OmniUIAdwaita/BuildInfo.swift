/// Generic fallback for Xcode-style generated build metadata.
///
/// Package adapters can provide an app-local `BuildInfo` for exact values; this
/// fallback keeps source that references `BuildInfo.commitHash` buildable when
/// no generated metadata file is present.
public enum BuildInfo {
    public static let commitHash = "unknown"
}
