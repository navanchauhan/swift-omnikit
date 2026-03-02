// Minimal SwiftUI App/Scene/Commands surface.
//
// This is intentionally lightweight: enough for `@main struct …: App { … }` style
// entry points to compile when targeting non-Apple platforms.

import Foundation

// MARK: - App

public protocol App {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
    init()
}

public extension App {
    static func main() {
        // Stub runner: construct the app to ensure side effects (e.g. init) happen, then
        // build the scene graph. A real runner would drive a renderer/event loop.
        _ = Self.init().body
    }
}

// MARK: - Scene

public protocol Scene {
    associatedtype Body
    @SceneBuilder var body: Body { get }
}

public extension Scene where Body == Never {
    var body: Never { fatalError("Primitive scenes have no body") }
}

public struct EmptyScene: Scene {
    public typealias Body = Never
    public init() {}
}

public struct AnyScene: Scene {
    public typealias Body = Never
    let _box: Any

    public init<S: Scene>(_ scene: S) {
        self._box = scene
    }
}

public struct TupleScene: Scene {
    public typealias Body = Never
    let scenes: [AnyScene]

    public init(_ scenes: [AnyScene]) {
        self.scenes = scenes
    }
}

@resultBuilder
public enum SceneBuilder {
    public static func buildBlock() -> EmptyScene { EmptyScene() }
    public static func buildBlock<S0: Scene>(_ s0: S0) -> S0 { s0 }

    public static func buildBlock<S0: Scene, S1: Scene>(_ s0: S0, _ s1: S1) -> TupleScene {
        TupleScene([AnyScene(s0), AnyScene(s1)])
    }

    public static func buildBlock<S0: Scene, S1: Scene, S2: Scene>(_ s0: S0, _ s1: S1, _ s2: S2) -> TupleScene {
        TupleScene([AnyScene(s0), AnyScene(s1), AnyScene(s2)])
    }

    public static func buildOptional<S: Scene>(_ scene: S?) -> AnyScene {
        if let scene { AnyScene(scene) } else { AnyScene(EmptyScene()) }
    }

    public static func buildEither<S: Scene>(first scene: S) -> AnyScene { AnyScene(scene) }
    public static func buildEither<S: Scene>(second scene: S) -> AnyScene { AnyScene(scene) }
}

// MARK: - Scene Types + Modifiers

public struct WindowGroup<Content: View>: Scene {
    public typealias Body = Never
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

public struct Settings<Content: View>: Scene {
    public typealias Body = Never
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
}

public protocol Commands {}

public struct EmptyCommands: Commands { public init() {} }

public enum CommandGroupPlacement: Hashable, Sendable {
    case appInfo
}

public struct CommandGroup<Content: View>: Commands {
    public let placement: CommandGroupPlacement
    let content: Content

    public init(after placement: CommandGroupPlacement, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    public init(before placement: CommandGroupPlacement, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }
}

public struct AnyCommands: Commands {
    let _box: Any
    public init<C: Commands>(_ commands: C) { self._box = commands }
}

public struct TupleCommands: Commands {
    let commands: [AnyCommands]
    public init(_ commands: [AnyCommands]) { self.commands = commands }
}

@resultBuilder
public enum CommandsBuilder {
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<C0: Commands>(_ c0: C0) -> C0 { c0 }

    public static func buildBlock<C0: Commands, C1: Commands>(_ c0: C0, _ c1: C1) -> TupleCommands {
        TupleCommands([AnyCommands(c0), AnyCommands(c1)])
    }

    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleCommands {
        TupleCommands([AnyCommands(c0), AnyCommands(c1), AnyCommands(c2)])
    }

    public static func buildOptional<C: Commands>(_ commands: C?) -> AnyCommands {
        if let commands { AnyCommands(commands) } else { AnyCommands(EmptyCommands()) }
    }

    public static func buildEither<C: Commands>(first commands: C) -> AnyCommands { AnyCommands(commands) }
    public static func buildEither<C: Commands>(second commands: C) -> AnyCommands { AnyCommands(commands) }
}

public struct SidebarCommands: Commands { public init() {} }

private struct _ScenePassthrough<Content: Scene>: Scene {
    typealias Body = Never
    let content: Content
    init(_ content: Content) { self.content = content }
}

private struct _SceneModelContainerProvider<Content: Scene>: Scene {
    typealias Body = Never
    let content: Content
    let container: ModelContainer
    init(_ content: Content, container: ModelContainer) {
        self.content = content
        self.container = container
    }
}

private protocol _WindowRootScene {
    func _rootView() -> AnyView?
}

extension WindowGroup: _WindowRootScene {
    fileprivate func _rootView() -> AnyView? { AnyView(content) }
}

extension Settings: _WindowRootScene {
    fileprivate func _rootView() -> AnyView? { AnyView(content) }
}

extension AnyScene: _WindowRootScene {
    fileprivate func _rootView() -> AnyView? {
        (self._box as? _WindowRootScene)?._rootView()
    }
}

extension TupleScene: _WindowRootScene {
    fileprivate func _rootView() -> AnyView? {
        for scene in scenes {
            if let root = (scene._box as? _WindowRootScene)?._rootView() {
                return root
            }
        }
        return nil
    }
}

extension _ScenePassthrough: _WindowRootScene where Content: _WindowRootScene {
    fileprivate func _rootView() -> AnyView? {
        content._rootView()
    }
}

extension _SceneModelContainerProvider: _WindowRootScene where Content: _WindowRootScene {
    fileprivate func _rootView() -> AnyView? {
        guard let root = content._rootView() else { return nil }
        return AnyView(root.modelContainer(container))
    }
}

public extension Scene {
    func commands<C: Commands>(@CommandsBuilder _ content: () -> C) -> some Scene {
        _ = content()
        return _ScenePassthrough(self)
    }

    func modelContainer(_ any: Any) -> some Scene {
        if let container = any as? ModelContainer {
            return AnyScene(_SceneModelContainerProvider(self, container: container))
        }
        return AnyScene(_ScenePassthrough(self))
    }

    func modelContainer(_ container: ModelContainer) -> some Scene {
        _SceneModelContainerProvider(self, container: container)
    }

    func defaultSize(width: CGFloat, height: CGFloat) -> some Scene {
        _ = width
        _ = height
        return _ScenePassthrough(self)
    }
}
