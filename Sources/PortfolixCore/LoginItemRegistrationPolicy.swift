public enum LoginItemRegistrationStatus: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum LoginItemRegistrationAction: Equatable, Sendable {
    case none
    case register
    case reregister
    case unregister
    case requiresApproval
}

public enum LoginItemRegistrationPolicy {
    public static func action(
        isEnabled: Bool,
        currentBuild: String,
        registeredBuild: String?,
        status: LoginItemRegistrationStatus
    ) -> LoginItemRegistrationAction {
        guard isEnabled else {
            switch status {
            case .enabled, .requiresApproval:
                return .unregister
            case .notRegistered, .notFound:
                return .none
            }
        }

        switch status {
        case .enabled:
            return registeredBuild == currentBuild ? .none : .reregister
        case .notRegistered, .notFound:
            return .register
        case .requiresApproval:
            return .requiresApproval
        }
    }
}
