import Foundation

// Native tool calls are retained only in memory for the paired function outputs.
struct AISearchFunctionContext: Equatable, Sendable {
    let input: [AIJSONValue]
    let calls: [LLMFunctionCall]

    func inputItems(results: [AIWebSearchToolResult], finalPrompt: String) -> [AIJSONValue] {
        var items = input
        let outputs = AISearchFunctionCalling.resultOutputs(results)
        for (index, call) in calls.enumerated() {
            let output = outputs.indices.contains(index)
                ? outputs[index]
                : #"{"status":"failed","sources":[],"limitations":["Search did not complete"]}"#
            items.append(.object(["type": .string("function_call_output"), "call_id": .string(call.callID), "output": .string(output)]))
        }
        items.append(.object(["role": .string("user"), "content": .string(finalPrompt)]))
        return items
    }
}

enum AISearchFunctionCalling {
    static let maximumCalls = 3
    static let maximumConcurrentCalls = 3

    static func resultOutputs(_ results: [AIWebSearchToolResult]) -> [String] {
        var seen = Set<String>()
        return results.map { result in
            guard let encoded = try? AIAnalysisAgent.encoder.encode(result),
                  var object = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { return "{}" }
            var duplicates: [String] = []
            object["sources"] = (object["sources"] as? [[String: Any]] ?? []).filter { source in
                guard let url = source["url"] as? String else { return false }
                if seen.insert(AISearchSourceIdentity.key(url)).inserted { return true }
                duplicates.append(url)
                return false
            }
            // Retain each call's asset associations without repeating the same source excerpt.
            object["duplicate_source_urls"] = duplicates
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func toolName(_ provider: SearchProviderOption) -> String {
        switch provider {
        case .parallel: "parallel_search"
        case .deepseek: "deepseek_search"
        case .tavily: "tavily_search"
        case .bocha: "bocha_search"
        case .exa: "exa_search"
        case .anysearch: "anysearch_search"
        }
    }

    static func definitions(providers: [SearchProviderOption]) -> [LLMFunctionTool] {
        SearchProviderOption.allCases.filter(providers.contains).map { provider in
            LLMFunctionTool(name: toolName(provider), description: "Search public web sources using \(provider.rawValue). Independent searches run concurrently. For important current facts, request 2–3 distinct enabled providers in this response, using complementary queries. Never include account values, quantities, costs or credentials. A different search engine returning the same original page is not independent corroboration.", parameters: .object([
                "type": .string("object"), "additionalProperties": .bool(false),
                "properties": .object([
                    "query": .object(["type": .string("string"), "minLength": .number(8), "maxLength": .number(128)]),
                    "position_refs": .object(["type": .string("array"), "items": .object(["type": .string("string"), "maxLength": .number(80)]), "maxItems": .number(3)])
                ]), "required": .array([.string("query"), .string("position_refs")])
            ]))
        }
    }

    static func plan(llm: LLMCompleting, systemPrompt: String, userPrompt: String,
                     configuration: AIProviderConfiguration, apiKey: String,
                     providers: [SearchProviderOption]) async throws -> AIWebSearchToolPlan {
        let completion = try await llm.completeJSONResult(
            systemPrompt: systemPrompt, userPrompt: userPrompt,
            configuration: configuration.withFunctions(definitions(providers: providers)),
            apiKey: apiKey, webSearchEnabled: false, webSearchProgress: nil)
        guard !completion.functionCalls.isEmpty else {
            guard let plan = AIAnalysisAgent.decodeToolPlan(completion.content) else { throw AIAnalysisAgentError.invalidReport }
            return plan
        }
        guard completion.functionCalls.count <= maximumCalls else { throw AIAnalysisAgentError.invalidReport }
        var seenIDs = Set<String>()
        let calls = try completion.functionCalls.enumerated().map { index, call in
            guard !call.callID.isEmpty, call.callID.count <= 200, seenIDs.insert(call.callID).inserted,
                  let provider = providers.first(where: { toolName($0) == call.name }),
                  call.arguments.utf8.count <= 4096,
                  let data = call.arguments.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["query", "position_refs"],
                  let query = object["query"] as? String,
                  let refs = object["position_refs"] as? [String] else { throw AIAnalysisAgentError.invalidReport }
            return AIWebSearchToolCall(id: "web_search_\(index + 1)", query: query, positionRefs: refs, provider: provider)
        }
        var plan = AIWebSearchToolPlan(toolCalls: calls, status: "continue", limitations: [])
        let continuation = completion.continuationItems.isEmpty ? completion.functionCalls.map {
            AIJSONValue.object(["type": .string("function_call"), "call_id": .string($0.callID), "name": .string($0.name), "arguments": .string($0.arguments)])
        } : completion.continuationItems
        plan.functionContext = AISearchFunctionContext(input: [.object(["role": .string("user"), "content": .string(userPrompt)])] + continuation, calls: completion.functionCalls)
        return plan
    }
}

struct AISearchUsageSummary: Codable, Equatable, Sendable {
    var requestCount: Int = 0
    var resultCount: Int = 0

    func displayText(language: AppLanguage) -> String {
        localizedText("搜索 \(requestCount) 次 · 获得 \(resultCount) 条来源", "\(requestCount) searches · \(resultCount) sources", language: language)
    }
}

enum AISearchSourceIdentity {
    static func key(_ url: String) -> String {
        guard var components = URLComponents(string: url) else { return url }
        components.fragment = nil
        components.host = components.host?.lowercased()
        components.queryItems = components.queryItems?.filter {
            !$0.name.lowercased().hasPrefix("utm_") && !["gclid", "fbclid"].contains($0.name.lowercased())
        }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.string ?? url
    }
}

// The ledger is task-local, so concurrent searches share one budget and source count.
enum AISearchExecution {
    static func search(_ client: WebSearching, query: String, positions: [Position],
                       configuration: SearchConfiguration, apiKey: String) async throws -> [AssetResearchSource] {
        try Task.checkCancellation()
        try await AIModelRun.ledger?.reserveSearchRequest()
        let sources = try await client.search(query: query, positions: positions, configuration: configuration, apiKey: apiKey)
        await AIModelRun.ledger?.recordSearchSources(sources)
        return sources
    }
}

extension AISearchExecution {
    static func executePlan(
        _ plan: AIWebSearchToolPlan,
        client: WebSearching,
        positions: [Position],
        configuration: SearchConfiguration,
        apiKeys: [SearchProviderOption: String],
        progress: AIAnalysisProgressHandler?,
        followUpProgress: AIFollowUpProgressHandler? = nil
    ) async -> [AIWebSearchToolResult] {
        let positionsByRef = Dictionary(uniqueKeysWithValues: positions.map { ("position_\($0.id.uuidString)", $0) })
        let calls = Array(plan.toolCalls.enumerated())
        guard !calls.isEmpty else { return [] }
        let concurrencyLimit = min(AISearchFunctionCalling.maximumConcurrentCalls, calls.count)
        let selectedProviders = Set(plan.toolCalls.compactMap(\.provider))
        return await withTaskGroup(of: (Int, AIWebSearchToolResult).self) { group in
            var nextIndex = 0
            var completed: [(Int, AIWebSearchToolResult)] = []

            func schedule(_ entry: (offset: Int, element: AIWebSearchToolCall)) {
                group.addTask {
                    await progress?(
                        .callingWebSearch(
                            query: entry.element.query,
                            ordinal: entry.offset + 1,
                            total: calls.count
                        )
                    )
                    await followUpProgress?(
                        .searching(
                            query: entry.element.query,
                            ordinal: entry.offset + 1,
                            total: calls.count
                        )
                    )
                    let result = await executeToolCall(
                        entry.element,
                        client: client,
                        positionsByRef: positionsByRef,
                        configuration: configuration,
                        apiKeys: apiKeys,
                        selectedProviders: selectedProviders
                    )
                    return (entry.offset, result)
                }
            }

            while nextIndex < concurrencyLimit {
                schedule(calls[nextIndex])
                nextIndex += 1
            }
            while let result = await group.next() {
                completed.append(result)
                if nextIndex < calls.count, !Task.isCancelled {
                    schedule(calls[nextIndex])
                    nextIndex += 1
                }
            }
            return completed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func executeToolCall(
        _ call: AIWebSearchToolCall,
        client: WebSearching,
        positionsByRef: [String: Position],
        configuration: SearchConfiguration,
        apiKeys: [SearchProviderOption: String],
        selectedProviders: Set<SearchProviderOption>
    ) async -> AIWebSearchToolResult {
        let referencedPositions = call.positionRefs.compactMap { positionsByRef[$0] }
        let providers = SearchProviderRouter.orderedProviders(
            requested: call.provider,
            query: call.query,
            positions: referencedPositions,
            configuration: configuration
        ).filter { apiKeys[$0] != nil && ($0 == call.provider || !selectedProviders.contains($0)) }
        var failures: [String] = []
        for provider in providers {
            if Task.isCancelled { break }
            guard let apiKey = apiKeys[provider] else { continue }
            do {
                let sources = try await AISearchExecution.search(client,
                    query: call.query,
                    positions: referencedPositions,
                    configuration: configuration.selecting(provider),
                    apiKey: apiKey
                )
                if !sources.isEmpty {
                    return AIWebSearchToolResult(
                        callID: call.id,
                        query: call.query,
                        positionRefs: call.positionRefs,
                        searchedAt: .now,
                        status: "ok",
                        sources: sources,
                        limitations: failures,
                        provider: provider
                    )
                }
                failures.append("\(provider.rawValue) 未返回可用来源")
            } catch {
                if error is CancellationError || Task.isCancelled { break }
                failures.append("\(provider.rawValue)：\(String(error.localizedDescription.prefix(140)))")
            }
        }
        let emptySearchLimitation = call.positionRefs.isEmpty
            ? "搜索未返回可用的公开 HTTPS 来源"
            : "搜索未返回与指定持仓直接相关的可用 HTTPS 来源"
        return AIWebSearchToolResult(
            callID: call.id,
            query: call.query,
            positionRefs: call.positionRefs,
            searchedAt: .now,
            status: failures.isEmpty ? "empty" : "failed",
            sources: [],
            limitations: failures.isEmpty ? [emptySearchLimitation] : failures,
            provider: call.provider
        )
    }

}
