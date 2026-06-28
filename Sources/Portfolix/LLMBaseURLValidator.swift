import Darwin
import Foundation

enum LLMBaseURLValidationError: LocalizedError, Equatable {
    case empty
    case unsupportedScheme
    case missingHost
    case containsUserInfo
    case invalidPort
    case invalidHost
    case localEndpointBlocked

    var errorDescription: String? {
        switch self {
        case .empty:
            "请填写 API Base URL"
        case .unsupportedScheme:
            "LLM API Base URL 必须使用 HTTPS"
        case .missingHost:
            "LLM API Base URL 缺少主机名"
        case .containsUserInfo:
            "LLM API Base URL 不允许包含用户名或密码"
        case .invalidPort:
            "LLM API Base URL 端口无效"
        case .invalidHost:
            "LLM API Base URL 主机名无效"
        case .localEndpointBlocked:
            "LLM API Base URL 不允许指向本机、内网、链路本地或多播地址"
        }
    }
}

enum LLMBaseURLValidator {
    static var allowsLocalDevelopmentEndpoints: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["PORTFOLIX_ALLOW_INSECURE_LLM_BASE_URLS"] == "1"
#else
        false
#endif
    }

    static func validatedComponents(from baseURL: String) throws -> URLComponents {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMBaseURLValidationError.empty }
        guard var components = URLComponents(string: trimmed) else {
            throw LLMBaseURLValidationError.invalidHost
        }
        guard let scheme = components.scheme?.lowercased() else {
            throw LLMBaseURLValidationError.unsupportedScheme
        }
        if scheme != "https" {
            guard allowsLocalDevelopmentEndpoints, scheme == "http" else {
                throw LLMBaseURLValidationError.unsupportedScheme
            }
        }
        guard components.user == nil, components.password == nil else {
            throw LLMBaseURLValidationError.containsUserInfo
        }
        if components.port == nil, authorityContainsPort(in: trimmed) {
            throw LLMBaseURLValidationError.invalidPort
        }
        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw LLMBaseURLValidationError.missingHost
        }
        if let port = components.port, !(1...65535).contains(port) {
            throw LLMBaseURLValidationError.invalidPort
        }
        let normalizedHost = normalize(host: host)
        guard isValidHostSyntax(normalizedHost) else {
            throw LLMBaseURLValidationError.invalidHost
        }
        if isLocalOrPrivateHost(normalizedHost) {
            guard allowsLocalDevelopmentEndpoints else {
                throw LLMBaseURLValidationError.localEndpointBlocked
            }
        }
        components.scheme = scheme
        return components
    }

    static func endpointURL(baseURL: String, appendingPath pathComponent: String) -> URL? {
        guard var components = try? validatedComponents(from: baseURL) else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.hasSuffix(pathComponent) {
            return components.url
        }
        components.path = "/" + [basePath, pathComponent].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url
    }

    static func endpointURL(baseURL: String, appendingPath pathComponent: String, queryItems: [URLQueryItem]) -> URL? {
        guard var components = try? validatedComponents(from: baseURL) else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, pathComponent].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems
        return components.url
    }

    private static func normalize(host: String) -> String {
        host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
    }

    private static func authorityContainsPort(in rawURL: String) -> Bool {
        guard let schemeRange = rawURL.range(of: "://") else { return false }
        let afterScheme = rawURL[schemeRange.upperBound...]
        let authority = afterScheme.split(whereSeparator: { character in
            character == "/" || character == "?" || character == "#"
        }).first.map(String.init) ?? ""
        let hostPort = authority.split(separator: "@", maxSplits: 1).last.map(String.init) ?? authority
        if hostPort.hasPrefix("[") {
            guard let closingBracket = hostPort.firstIndex(of: "]") else { return false }
            return hostPort[hostPort.index(after: closingBracket)...].hasPrefix(":")
        }
        return hostPort.contains(":")
    }

    private static func isValidHostSyntax(_ host: String) -> Bool {
        if ipv4Bytes(host) != nil || ipv6Bytes(host) != nil {
            return true
        }
        guard host.count <= 253, host.contains(".") else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 }) else { return false }
        return labels.allSatisfy { label in
            guard label.first != "-", label.last != "-" else { return false }
            return label.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-"
            }
        }
    }

    private static func isLocalOrPrivateHost(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") {
            return true
        }
        if host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".internal") || host.hasSuffix(".home") {
            return true
        }
        if let bytes = ipv4Bytes(host) {
            return isBlockedIPv4(bytes)
        }
        if let bytes = ipv6Bytes(host) {
            return isBlockedIPv6(bytes)
        }
        if isLegacyNumericIPAddress(host) {
            return true
        }
        return false
    }

    private static func isLegacyNumericIPAddress(_ host: String) -> Bool {
        if host.allSatisfy(\.isNumber) {
            return true
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.count <= 4 else { return false }
        return labels.allSatisfy { label in
            guard !label.isEmpty else { return false }
            let text = label.lowercased()
            if text.hasPrefix("0x") {
                return text.dropFirst(2).allSatisfy(\.isHexDigit)
            }
            return text.allSatisfy { character in
                character.isNumber && character.wholeNumberValue.map { (0...9).contains($0) } == true
            }
        }
    }

    private static func ipv4Bytes(_ host: String) -> [UInt8]? {
        var address = in_addr()
        let parsed = host.withCString { inet_pton(AF_INET, $0, &address) }
        guard parsed == 1 else { return nil }
        let value = UInt32(bigEndian: address.s_addr)
        return [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
    }

    private static func ipv6Bytes(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        let parsed = host.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func isBlockedIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        let first = bytes[0]
        let second = bytes[1]
        switch first {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(second)
        case 169:
            return second == 254
        case 172:
            return (16...31).contains(second)
        case 192:
            return second == 168
        case 198:
            return second == 18 || second == 19
        case 224...255:
            return true
        default:
            return false
        }
    }

    private static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }
        let isUnspecified = bytes.allSatisfy { $0 == 0 }
        let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        let isUniqueLocal = (bytes[0] & 0xfe) == 0xfc
        let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
        let isMulticast = bytes[0] == 0xff
        let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        if isIPv4Mapped {
            return isBlockedIPv4(Array(bytes[12...15]))
        }
        return isUnspecified || isLoopback || isUniqueLocal || isLinkLocal || isMulticast
    }
}
