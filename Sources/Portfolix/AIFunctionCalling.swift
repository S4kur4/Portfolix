import Foundation

struct LLMFunctionTool: Encodable, Equatable, Sendable {
  let type = "function"
  let name: String
  let description: String
  let parameters: AIJSONValue
}

struct LLMFunctionCall: Equatable, Sendable {
  let callID: String
  let name: String
  let arguments: String
}

enum AIFunctionCallPolicy {
  static let maximumRounds = 2
  static let maximumCalls = 4
  static let maximumResultBytes = 24_000
}
