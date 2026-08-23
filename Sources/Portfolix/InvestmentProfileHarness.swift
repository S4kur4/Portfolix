import Foundation

struct InvestmentProfileHarness: Sendable {
    let llm: LLMCompleting
    let search: WebSearching

    func enrich(
        positions: [Position],
        cachedExposures: [AssetExposureProfile],
        llmConfiguration: AIProviderConfiguration,
        searchConfiguration: SearchConfiguration,
        llmKey: String,
        searchKey: String?,
        now: Date = .now
    ) async -> InvestmentProfileResearchResult {
        var exposures = InvestmentProfileEngine.merge(
            positions: positions,
            cached: cachedExposures,
            now: now
        )
        _ = searchKey
        guard searchConfiguration.isEnabled else {
            return InvestmentProfileResearchResult(exposures: exposures, searchedAssetCount: 0, limitations: [])
        }
        let candidates = InvestmentProfileEngine.researchCandidates(
            positions: positions,
            exposures: exposures,
            limit: 4
        )
        guard !candidates.isEmpty else {
            return InvestmentProfileResearchResult(exposures: exposures, searchedAssetCount: 0, limitations: [])
        }

        do {
            let identities = candidates.map {
                InvestmentProfileCandidatePayload(
                    positionRef: InvestmentProfileEngine.positionRef(for: $0),
                    name: $0.name,
                    symbol: $0.symbol,
                    category: $0.category.aiCode
                )
            }
            let identitiesJSON = String(
                data: try AIAnalysisAgent.inputEncoder.encode(identities),
                encoding: .utf8
            ) ?? "[]"
            let completion = try await llm.completeJSONResult(
                systemPrompt: AIAnalysisPromptText.investmentProfileExposureSystem,
                userPrompt: AIAnalysisPromptText.investmentProfileExposureUser(
                    identitiesJSON: identitiesJSON,
                    evidenceJSON: "[]"
                ),
                configuration: llmConfiguration
                    .withRequestTimeout(LLMRequestTimeoutPolicy.followUp)
                    .withMaxOutputTokens(LLMOutputTokenPolicy.standard),
                apiKey: llmKey,
                webSearchEnabled: true,
                webSearchProgress: nil
            )
            guard let payload = Self.decodeExposurePayload(completion.content) else {
                throw AIAnalysisAgentError.invalidReport
            }
            let payloadRefs = payload.profiles.map(\.positionRef)
            guard
                payloadRefs.count <= identities.count,
                Set(payloadRefs).count == payloadRefs.count
            else {
                throw AIAnalysisAgentError.invalidReport
            }
            let citedSources = AIAnalysisAgent.nativeWebSearchToolResults(
                from: completion,
                fallbackQuery: "基金底层资产 地区 行业 业绩比较基准",
                positionRefs: identities.map(\.positionRef)
            ).flatMap(\.sources)
            let attributedSources = citedSources.isEmpty
                ? Self.modelAttributedSources(from: payload, completion: completion)
                : []
            let sources = citedSources + attributedSources
            guard !sources.isEmpty else {
                return InvestmentProfileResearchResult(
                    exposures: exposures,
                    searchedAssetCount: 0,
                    limitations: ["本次未获得可验证的公开资料，已保留本地穿透结果"]
                )
            }
            let positionsByRef = Dictionary(uniqueKeysWithValues: candidates.map {
                (InvestmentProfileEngine.positionRef(for: $0), $0)
            })
            let enriched = try payload.profiles.compactMap { candidate -> AssetExposureProfile? in
                guard let position = positionsByRef[candidate.positionRef] else { return nil }
                return try Self.validatedExposure(candidate, position: position, sources: sources, now: now)
            }
            let enrichedByRef = Dictionary(uniqueKeysWithValues: enriched.map { ($0.positionRef, $0) })
            exposures = exposures.map { enrichedByRef[$0.positionRef] ?? $0 }
            return InvestmentProfileResearchResult(
                exposures: exposures,
                searchedAssetCount: enriched.count,
                limitations: attributedSources.isEmpty
                    ? []
                    : ["DeepSeek 内建搜索未返回可独立校验的引用元数据，穿透结果已按较低置信度处理"]
            )
        } catch {
            return InvestmentProfileResearchResult(
                exposures: exposures,
                searchedAssetCount: 0,
                limitations: ["公开资料未能转换为可信的结构化底层暴露"]
            )
        }
    }

    private func makePlan(
        candidates: [Position],
        previousQueries: [String],
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> AIWebSearchToolPlan {
        let candidatePayload = candidates.map {
            InvestmentProfileCandidatePayload(
                positionRef: InvestmentProfileEngine.positionRef(for: $0),
                name: $0.name,
                symbol: $0.symbol,
                category: $0.category.aiCode
            )
        }
        let data = try AIAnalysisAgent.inputEncoder.encode(candidatePayload)
        let candidatesJSON = String(data: data, encoding: .utf8) ?? "[]"
        let previousQueriesData = try AIAnalysisAgent.inputEncoder.encode(previousQueries)
        let previousQueriesJSON = String(data: previousQueriesData, encoding: .utf8) ?? "[]"
        let raw = try await llm.completeJSON(
            systemPrompt: AIAnalysisPromptText.investmentProfilePlanningSystem,
            userPrompt: AIAnalysisPromptText.investmentProfilePlanningUser(
                candidatesJSON: candidatesJSON,
                previousQueriesJSON: previousQueriesJSON
            ),
            configuration: configuration
                .withRequestTimeout(LLMRequestTimeoutPolicy.followUp)
                .withMaxOutputTokens(LLMOutputTokenPolicy.standard),
            apiKey: apiKey
        )
        guard let decoded = AIAnalysisAgent.decodeToolPlan(raw) else {
            throw AIAnalysisAgentError.invalidReport
        }
        let allowedRefs = Set(candidatePayload.map(\.positionRef))
        let terms = Dictionary(uniqueKeysWithValues: candidatePayload.map { candidate in
            (candidate.positionRef, Set([candidate.name, candidate.symbol].filter { $0.count >= 2 }))
        })
        let validated = try AIAnalysisAgent.validatedToolPlan(
            decoded,
            allowedRefs: allowedRefs,
            allowedSearchTerms: terms
        )
        guard validated.toolCalls.allSatisfy({ $0.positionRefs.count == 1 }) else {
            throw AIAnalysisAgentError.invalidReport
        }
        let positionsByRef = Dictionary(uniqueKeysWithValues: candidates.map {
            (InvestmentProfileEngine.positionRef(for: $0), $0)
        })
        let publicCalls = try validated.toolCalls.enumerated().map { index, call in
            guard
                let ref = call.positionRefs.first,
                let position = positionsByRef[ref]
            else {
                throw AIAnalysisAgentError.invalidReport
            }
            return AIWebSearchToolCall(
                id: "web_search_\(index + 1)",
                query: Self.publicResearchQuery(for: position, proposedQuery: call.query),
                positionRefs: [ref]
            )
        }
        return AIWebSearchToolPlan(
            toolCalls: publicCalls,
            status: validated.status,
            limitations: validated.limitations
        )
    }

    private func extractExposures(
        positions: [Position],
        sourcesByRef: [String: [AssetResearchSource]],
        configuration: AIProviderConfiguration,
        apiKey: String,
        now: Date
    ) async throws -> [AssetExposureProfile] {
        let identities = positions.map {
            InvestmentProfileCandidatePayload(
                positionRef: InvestmentProfileEngine.positionRef(for: $0),
                name: $0.name,
                symbol: $0.symbol,
                category: $0.category.aiCode
            )
        }
        let evidence = sourcesByRef.mapValues { sources in
            Array(Dictionary(grouping: sources, by: \.url).compactMap { $0.value.first }.prefix(6))
        }
        let identitiesJSON = String(
            data: try AIAnalysisAgent.inputEncoder.encode(identities),
            encoding: .utf8
        ) ?? "[]"
        let evidenceJSON = String(
            data: try AIAnalysisAgent.inputEncoder.encode(evidence),
            encoding: .utf8
        ) ?? "{}"
        let raw = try await llm.completeJSON(
            systemPrompt: AIAnalysisPromptText.investmentProfileExposureSystem,
            userPrompt: AIAnalysisPromptText.investmentProfileExposureUser(
                identitiesJSON: identitiesJSON,
                evidenceJSON: evidenceJSON
            ),
            configuration: configuration
                .withRequestTimeout(LLMRequestTimeoutPolicy.followUp)
                .withMaxOutputTokens(LLMOutputTokenPolicy.standard),
            apiKey: apiKey
        )
        guard let payload = Self.decodeExposurePayload(raw) else {
            throw AIAnalysisAgentError.invalidReport
        }
        let payloadRefs = payload.profiles.map(\.positionRef)
        guard
            payloadRefs.count <= positions.count,
            Set(payloadRefs).count == payloadRefs.count
        else {
            throw AIAnalysisAgentError.invalidReport
        }
        let positionsByRef = Dictionary(uniqueKeysWithValues: positions.map {
            (InvestmentProfileEngine.positionRef(for: $0), $0)
        })
        return try payload.profiles.compactMap { candidate in
            guard
                let position = positionsByRef[candidate.positionRef],
                let sources = sourcesByRef[candidate.positionRef],
                !sources.isEmpty
            else { return nil }
            return try Self.validatedExposure(
                candidate,
                position: position,
                sources: sources,
                now: now
            )
        }
    }

    static func decodeExposurePayload(_ raw: String) -> InvestmentProfileExposurePayload? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(InvestmentProfileExposurePayload.self, from: data)
    }

    static func modelAttributedSources(
        from payload: InvestmentProfileExposurePayload,
        completion: LLMCompletionResult
    ) -> [AssetResearchSource] {
        guard completion.webSearchCallCount > 0 else { return [] }
        var seenURLs = Set<String>()
        return payload.profiles
            .flatMap(\.sourceURLs)
            .compactMap { rawURL -> AssetResearchSource? in
                let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    url.count <= 2_048,
                    seenURLs.insert(url).inserted,
                    let components = try? LLMBaseURLValidator.validatedComponents(from: url),
                    components.scheme?.lowercased() == "https",
                    let rawHost = components.host?.lowercased(),
                    !rawHost.isEmpty
                else { return nil }
                let domain = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
                return AssetResearchSource(
                    title: domain,
                    url: url,
                    domain: domain,
                    publishedDate: nil,
                    snippet: "",
                    credibility: .general
                )
            }
    }

    static func validatedExposure(
        _ candidate: InvestmentProfileExposureCandidate,
        position: Position,
        sources: [AssetResearchSource],
        now: Date = .now
    ) throws -> AssetExposureProfile {
        let allowedAssets = Set(InvestmentProfileAssetClass.allCases.map(\.rawValue))
        let allowedRegions = Set(InvestmentProfileRegion.allCases.map(\.rawValue))
        guard
            Set(candidate.assetClassWeights.keys).isSubset(of: allowedAssets),
            Set(candidate.regionWeights.keys).isSubset(of: allowedRegions),
            candidate.assetClassWeights.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
            candidate.regionWeights.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
            candidate.sectorWeights.count <= 8,
            candidate.sectorWeights.keys.allSatisfy({
                $0.range(of: #"^[a-z0-9_]{1,40}$"#, options: .regularExpression) != nil
            }),
            candidate.sectorWeights.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
            candidate.assetClassWeights.values.reduce(0, +) > 0,
            candidate.regionWeights.values.reduce(0, +) > 0,
            candidate.confidence.isFinite,
            candidate.growthStyleScore.isFinite,
            candidate.incomeScore.isFinite,
            candidate.volatilityScore.isFinite
        else {
            throw AIAnalysisAgentError.invalidReport
        }
        let sourceByURL = Dictionary(grouping: sources, by: \.url).compactMapValues(\.first)
        guard
            !candidate.sourceURLs.isEmpty,
            candidate.sourceURLs.allSatisfy({ sourceByURL[$0] != nil }),
            sources.allSatisfy({ source in
                guard let components = URLComponents(string: source.url) else { return false }
                return components.scheme?.lowercased() == "https" && components.host != nil
            })
        else {
            throw AIAnalysisAgentError.invalidReport
        }
        let referencedSources = candidate.sourceURLs.compactMap { sourceByURL[$0] }
        let acceptedSources = referencedSources.isEmpty ? Array(sources.prefix(3)) : Array(referencedSources.prefix(3))
        guard !acceptedSources.isEmpty else { throw AIAnalysisAgentError.invalidReport }
        let rationale = String(candidate.rationale.prefix(220))
        try AIInformationSecurityGuardrail.validateGeneratedText(rationale)
        let benchmark = candidate.benchmarkKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let benchmark {
            try AIInformationSecurityGuardrail.validateGeneratedText(benchmark)
        }

        let sourceConfidenceCap: Double
        if acceptedSources.contains(where: { $0.credibility == .official }) {
            sourceConfidenceCap = 0.95
        } else if acceptedSources.contains(where: { $0.credibility == .mainstream }) {
            sourceConfidenceCap = 0.82
        } else {
            sourceConfidenceCap = 0.7
        }

        return AssetExposureProfile(
            positionRef: InvestmentProfileEngine.positionRef(for: position),
            symbol: position.symbol,
            category: position.category.aiCode,
            resolverVersion: InvestmentProfileEngine.resolverVersion,
            resolvedAt: now,
            expiresAt: now.addingTimeInterval(30 * 86_400),
            assetClassWeights: normalized(candidate.assetClassWeights),
            regionWeights: normalized(candidate.regionWeights),
            sectorWeights: normalized(candidate.sectorWeights),
            growthStyleScore: clampUnit(candidate.growthStyleScore),
            incomeScore: clampUnit(candidate.incomeScore),
            volatilityScore: clampUnit(candidate.volatilityScore),
            benchmarkKey: benchmark.map { String($0.prefix(100)).lowercased() },
            confidence: min(clampUnit(candidate.confidence), sourceConfidenceCap),
            rationale: rationale,
            evidence: acceptedSources.map {
                InvestmentProfileEvidence(title: $0.title, url: $0.url, source: $0.domain, asOf: now)
            }
        )
    }

    private static func normalized(_ values: [String: Double]) -> [String: Double] {
        let total = values.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return values.mapValues { max($0, 0) / total }
    }

    private static func clampUnit(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func publicResearchQuery(for position: Position, proposedQuery: String) -> String {
        let safeSymbol = position.symbol.filter { character in
            character.isLetter || character.isNumber || ".-_".contains(character)
        }
        let focusOptions: [(String, [String])] = [
            ("最新季报", ["季报", "定期报告", "quarterly"]),
            ("投资范围", ["投资范围", "investment scope"]),
            ("资产配置", ["资产配置", "asset allocation"]),
            ("地区配置", ["地区配置", "region", "geographic"]),
            ("行业配置", ["行业配置", "sector"]),
            ("业绩比较基准", ["业绩比较基准", "benchmark"]),
        ]
        var focuses = focusOptions.compactMap { label, aliases in
            aliases.contains { proposedQuery.localizedCaseInsensitiveContains($0) } ? label : nil
        }
        if focuses.isEmpty {
            focuses = ["最新季报", "投资范围", "资产配置", "地区配置", "业绩比较基准"]
        }
        return "\(safeSymbol) 基金 \(focuses.joined(separator: " "))"
    }
}

private struct InvestmentProfileCandidatePayload: Codable {
    let positionRef: String
    let name: String
    let symbol: String
    let category: String

    enum CodingKeys: String, CodingKey {
        case positionRef = "position_ref"
        case name
        case symbol
        case category
    }
}

struct InvestmentProfileExposurePayload: Decodable {
    let profiles: [InvestmentProfileExposureCandidate]
}

struct InvestmentProfileExposureCandidate: Decodable {
    let positionRef: String
    let assetClassWeights: [String: Double]
    let regionWeights: [String: Double]
    let sectorWeights: [String: Double]
    let growthStyleScore: Double
    let incomeScore: Double
    let volatilityScore: Double
    let benchmarkKey: String?
    let confidence: Double
    let rationale: String
    let sourceURLs: [String]

    enum CodingKeys: String, CodingKey {
        case positionRef = "position_ref"
        case assetClassWeights = "asset_class_weights"
        case regionWeights = "region_weights"
        case sectorWeights = "sector_weights"
        case growthStyleScore = "growth_style_score"
        case incomeScore = "income_score"
        case volatilityScore = "volatility_score"
        case benchmarkKey = "benchmark_key"
        case confidence
        case rationale
        case sourceURLs = "source_urls"
    }
}
