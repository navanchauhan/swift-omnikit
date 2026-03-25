import Foundation
import OmniSkills

public extension ShellToolLocalSkill {
    init(projection: OmniSkillShellProjection) {
        self.init(
            description: projection.description,
            name: projection.name,
            path: projection.path
        )
    }
}

public extension Array where Element == ShellToolLocalSkill {
    init(projections: [OmniSkillShellProjection]) {
        self = projections.map(ShellToolLocalSkill.init(projection:))
    }
}
