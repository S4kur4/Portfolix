import os.signpost

enum PortfolixPerformance {
    private static let log = OSLog(
        subsystem: "app.portfolix.mac",
        category: .pointsOfInterest
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let identifier = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: identifier)
        return identifier
    }

    static func end(_ name: StaticString, identifier: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: identifier)
    }

    static func event(_ name: StaticString) {
        os_signpost(.event, log: log, name: name)
    }
}
