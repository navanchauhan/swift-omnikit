/// Capabilities that can be granted to a container.
public enum ContainerCapability: Sendable, Hashable, Codable {
    case network
    case workspace(hostPath: String)
    case persistentVolume(name: String, hostPath: String)
    case tmpfs
    case debugMount
}
