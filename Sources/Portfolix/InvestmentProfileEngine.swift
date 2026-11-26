import Foundation

enum InvestmentProfileEngine {
    static let resolverVersion = "native-lookthrough.v1"

    static func positionRef(for position: Position) -> String {
        "position_\(position.id.uuidString)"
    }
}
