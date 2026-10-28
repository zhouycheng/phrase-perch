import Foundation
import Observation

@MainActor @Observable
final class PermissionSetupViewModel {
    private let authorization: AuthorizationService
    init(authorization: AuthorizationService) { self.authorization = authorization }
    var requirements: [PermissionRequirement] { authorization.permissionRequirements }
    var isRestarting: Bool { authorization.isRestarting }
    var feedback: String { authorization.permissionSetupError }
    func refresh() { authorization.refreshPermissions() }
    func performAction(for id: String) { authorization.performPermissionAction(for: id) }
}
