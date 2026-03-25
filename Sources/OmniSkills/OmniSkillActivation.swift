import Foundation
import OmniAgentMesh

public enum OmniSkillActivationResolver {
    public static func activeInstallations(
        installations: [SkillInstallationRecord],
        activations: [SkillActivationRecord],
        scope: SessionScope,
        missionID: String?
    ) -> [SkillInstallationRecord] {
        let activeKeys = Set(
            activations
                .filter { $0.status == .active }
                .filter { activation in
                    switch activation.scope {
                    case .system:
                        return true
                    case .workspace:
                        return activation.workspaceID == scope.workspaceID
                    case .mission:
                        return activation.missionID == missionID
                    }
                }
                .map { "\($0.skillID)@\($0.version ?? "")" }
        )

        return installations.filter { installation in
            let key = "\(installation.skillID)@\(installation.version)"
            guard activeKeys.contains(key) else {
                return false
            }
            switch installation.scope {
            case .system:
                return true
            case .workspace:
                return installation.workspaceID == scope.workspaceID
            case .mission:
                return missionID != nil && installation.workspaceID == scope.workspaceID
            }
        }
    }
}
