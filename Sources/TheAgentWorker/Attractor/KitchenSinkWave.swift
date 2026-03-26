// KitchenSinkWave.swift
// Part of TheAgentWorkerKit target

/// Manifest for a single KitchenSink attractor wave.
public struct KitchenSinkWave: Sendable, Identifiable {
    public var id: String  // e.g. "wave-00", "wave-01"
    public var title: String
    public var features: [String]
    public var ownedFiles: [String]
    public var targetedTestCases: [String]
    public var expectedArtifacts: [String]

    public init(
        id: String,
        title: String,
        features: [String],
        ownedFiles: [String],
        targetedTestCases: [String],
        expectedArtifacts: [String]
    ) {
        self.id = id
        self.title = title
        self.features = features
        self.ownedFiles = ownedFiles
        self.targetedTestCases = targetedTestCases
        self.expectedArtifacts = expectedArtifacts
    }
}

extension KitchenSinkWave {
    /// All waves for Sprint 009
    public static let allWaves: [KitchenSinkWave] = [wave00, wave01, wave02, wave03, wave04, wave05]

    public static let wave00 = KitchenSinkWave(
        id: "wave-00",
        title: "Execution Substrate",
        features: ["Wave manifest system", "Attractor workflow template", "Runner CLI", "TUI test case selection"],
        ownedFiles: [
            "Sources/TheAgentWorker/Attractor/KitchenSinkWave.swift",
            "Sources/TheAgentWorker/Attractor/KitchenSinkAttractorWorkflowTemplate.swift",
            "Sources/KitchenSinkAttractorRunner/main.swift",
            "scripts/tui-test.sh",
            "scripts/tui-test-wave.sh",
        ],
        targetedTestCases: ["wave00_home"],
        expectedArtifacts: ["workflow.dot", "pipeline-result.json"]
    )

    public static let wave01 = KitchenSinkWave(
        id: "wave-01",
        title: "Shapes, Visual Modifiers, and ProgressView",
        features: ["Unicode shape fills", "clipShape border", "scaleEffect", "ProgressView spinner/bar", "SF Symbol map"],
        ownedFiles: [
            "Sources/OmniUICore/Primitives.swift",
            "Sources/OmniUICore/Modifiers.swift",
            "Sources/OmniUICore/Shapes.swift",
            "Sources/OmniUICore/BrailleRaster.swift",
            "Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift",
            "Sources/OmniUICore/SFSymbolMap.swift",
        ],
        targetedTestCases: ["wave01_shapes", "wave01_progress"],
        expectedArtifacts: ["workflow.dot", "wave1_shapes_initial.png", "wave1_shapes_final.png"]
    )

    public static let wave02 = KitchenSinkWave(
        id: "wave-02",
        title: "Layout and Chrome",
        features: ["TabView chrome", "Form(.grouped)", "Table multi-column", "LazyVGrid/LazyHGrid", "Grid/GridRow", "NavigationSplitView"],
        ownedFiles: [
            "Sources/OmniUICore/Primitives.swift",
            "Sources/OmniUICore/Modifiers.swift",
            "Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift",
            "Sources/OmniUICore/Grid.swift",
        ],
        targetedTestCases: ["wave02_tabview", "wave02_form", "wave02_table", "wave02_grid"],
        expectedArtifacts: ["workflow.dot", "wave2_tabview.png", "wave2_form.png", "wave2_table.png"]
    )

    public static let wave03 = KitchenSinkWave(
        id: "wave-03",
        title: "Interaction and Gestures",
        features: ["Tree expand/collapse", "EditButton/.onDelete", "SecureField masking", "DragGesture", "LongPressGesture", "Multi-tap"],
        ownedFiles: [
            "Sources/OmniUICore/Primitives.swift",
            "Sources/OmniUICore/GeneratedSwiftUISignatureSink.swift",
            "Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift",
        ],
        targetedTestCases: ["wave03_tree", "wave03_editing", "wave03_secure"],
        expectedArtifacts: ["workflow.dot", "wave3_tree_expanded.png", "wave3_secure_field.png"]
    )

    public static let wave04 = KitchenSinkWave(
        id: "wave-04",
        title: "Data and Observation",
        features: ["@Observable runtime wiring", "@Bindable", "ModelContext operations", "@Query with FetchDescriptor"],
        ownedFiles: [
            "Sources/OmniUICore/ObservableObjects.swift",
            "Sources/OmniUICore/State.swift",
            "Sources/OmniUICore/SwiftDataCompat.swift",
            "Sources/SwiftUIMacros/ObservableMacro.swift",
        ],
        targetedTestCases: ["wave04_observable", "wave04_swiftdata"],
        expectedArtifacts: ["workflow.dot", "wave4_observable.png", "wave4_swiftdata.png"]
    )

    public static let wave05 = KitchenSinkWave(
        id: "wave-05",
        title: "Animation, Transitions, AsyncImage, and Polish",
        features: ["withAnimation tick scheduler", ".transition", "AsyncImage", "Polish pass"],
        ownedFiles: [
            "Sources/SwiftUI/Animation.swift",
            "Sources/OmniUICore/Modifiers.swift",
            "Sources/OmniUICore/Primitives.swift",
            "Sources/OmniUICore/View.swift",
            "Sources/OmniUINotcursesRenderer/NotcursesRenderer.swift",
        ],
        targetedTestCases: ["wave05_animation", "wave05_full_demo"],
        expectedArtifacts: ["workflow.dot", "wave5_animation.png", "wave5_full_demo.png"]
    )
}
