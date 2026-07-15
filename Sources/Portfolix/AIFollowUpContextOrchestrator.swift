import Foundation

struct AIFollowUpConversationEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: String
    let createdAt: Date
    let content: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt = "created_at"
        case content
    }
}

struct AIFollowUpConversationSummary: Codable, Equatable {
    let omittedItemCount: Int
    let periodStart: Date?
    let periodEnd: Date?
    let earlierUserTopics: [String]
    let earlierAssistantConclusions: [String]
    let earlierReportSummaries: [String]

    enum CodingKeys: String, CodingKey {
        case omittedItemCount = "omitted_item_count"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case earlierUserTopics = "earlier_user_topics"
        case earlierAssistantConclusions = "earlier_assistant_conclusions"
        case earlierReportSummaries = "earlier_report_summaries"
    }
}

struct AIFollowUpConversationContext: Codable, Equatable {
    let schemaVersion: String
    let sourceItemCount: Int
    let includedItemCount: Int
    let recentHistory: [AIFollowUpConversationEntry]
    let relevantEarlierHistory: [AIFollowUpConversationEntry]
    let earlierHistorySummary: AIFollowUpConversationSummary?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sourceItemCount = "source_item_count"
        case includedItemCount = "included_item_count"
        case recentHistory = "recent_history"
        case relevantEarlierHistory = "relevant_earlier_history"
        case earlierHistorySummary = "earlier_history_summary"
    }
}

enum AIFollowUpContextOrchestrator {
    static let recentItemLimit = 10
    static let relevantEarlierItemLimit = 6
    static let maximumEncodedCharacterCount = 18_000

    static func make(
        question: String,
        items: [AIReportChatItem],
        excludingItemIDs: Set<UUID> = [],
        recentLimit: Int = recentItemLimit,
        relevantLimit: Int = relevantEarlierItemLimit,
        characterBudget: Int = maximumEncodedCharacterCount
    ) -> AIFollowUpConversationContext {
        var candidates = items
            .filter { !excludingItemIDs.contains($0.id) && shouldInclude($0) }
            .sorted { $0.createdAt < $1.createdAt }
        removeDuplicatedCurrentQuestion(question, from: &candidates)

        let sourceItemCount = candidates.count
        let recentStart = max(0, candidates.count - max(1, recentLimit))
        let recentItems = recentStart < candidates.count ? Array(candidates[recentStart...]) : []
        let earlierItems = Array(candidates[..<recentStart])
        let questionTokens = relevanceTokens(question)
        let rankedEarlierItems = earlierItems
            .map { item in
                (item: item, score: relevanceScore(for: item, question: question, questionTokens: questionTokens))
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score {
                    return $0.item.createdAt > $1.item.createdAt
                }
                return $0.score > $1.score
            }
        let relevantIDs = Set(rankedEarlierItems.prefix(max(0, relevantLimit)).map(\.item.id))
        let relevantItems = earlierItems.filter { relevantIDs.contains($0.id) }
        let omittedItems = earlierItems.filter { !relevantIDs.contains($0.id) }

        var recentEntries = recentItems.map { entry(for: $0, contentLimit: 1_200) }
        var relevantEntries = relevantItems.map { entry(for: $0, contentLimit: 900) }
        var summary = summary(for: omittedItems)
        var context = buildContext(
            sourceItemCount: sourceItemCount,
            recentEntries: recentEntries,
            relevantEntries: relevantEntries,
            summary: summary
        )

        while encodedCharacterCount(context) > characterBudget, !relevantEntries.isEmpty {
            relevantEntries.removeFirst()
            context = buildContext(
                sourceItemCount: sourceItemCount,
                recentEntries: recentEntries,
                relevantEntries: relevantEntries,
                summary: summary
            )
        }
        while encodedCharacterCount(context) > characterBudget, recentEntries.count > 4 {
            recentEntries.removeFirst()
            context = buildContext(
                sourceItemCount: sourceItemCount,
                recentEntries: recentEntries,
                relevantEntries: relevantEntries,
                summary: summary
            )
        }
        if encodedCharacterCount(context) > characterBudget {
            recentEntries = recentEntries.map { shortened($0, limit: 480) }
            relevantEntries = relevantEntries.map { shortened($0, limit: 360) }
            summary = shortened(summary, limit: 320)
            context = buildContext(
                sourceItemCount: sourceItemCount,
                recentEntries: recentEntries,
                relevantEntries: relevantEntries,
                summary: summary
            )
        }
        if encodedCharacterCount(context) > characterBudget {
            summary = nil
            context = buildContext(
                sourceItemCount: sourceItemCount,
                recentEntries: recentEntries,
                relevantEntries: relevantEntries,
                summary: nil
            )
        }
        while encodedCharacterCount(context) > characterBudget, recentEntries.count > 1 {
            recentEntries.removeFirst()
            context = buildContext(
                sourceItemCount: sourceItemCount,
                recentEntries: recentEntries,
                relevantEntries: relevantEntries,
                summary: nil
            )
        }
        if encodedCharacterCount(context) > characterBudget {
            recentEntries = recentEntries.map { shortened($0, limit: 160) }
            relevantEntries = []
            context = buildContext(
                sourceItemCount: sourceItemCount,
                recentEntries: recentEntries,
                relevantEntries: [],
                summary: nil
            )
        }
        return context
    }

    static func encodedJSON(_ context: AIFollowUpConversationContext) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(context) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func shouldInclude(_ item: AIReportChatItem) -> Bool {
        guard item.kind != .assistant || AIChatDisclosurePolicy.shouldShowDisclosure(for: item.text ?? "") else {
            return false
        }
        return item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || item.report != nil
    }

    private static func removeDuplicatedCurrentQuestion(
        _ question: String,
        from items: inout [AIReportChatItem]
    ) {
        let normalizedQuestion = normalizedText(question)
        guard !normalizedQuestion.isEmpty,
              let index = items.lastIndex(where: {
                  $0.kind == .user && normalizedText($0.text ?? "") == normalizedQuestion
              })
        else { return }
        items.remove(at: index)
    }

    private static func entry(
        for item: AIReportChatItem,
        contentLimit: Int
    ) -> AIFollowUpConversationEntry {
        AIFollowUpConversationEntry(
            id: item.id,
            kind: item.kind.rawValue,
            createdAt: item.createdAt,
            content: truncate(content(for: item), limit: contentLimit)
        )
    }

    private static func content(for item: AIReportChatItem) -> String {
        if let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        guard let report = item.report else { return "" }
        let actions = (report.rebalanceActions ?? []).prefix(3).map { action in
            [action.assetName, action.symbol, action.title, action.rationale]
                .compactMap(\.self)
                .joined(separator: " ")
        }
        let alerts = report.assetAlerts.prefix(3).map { alert in
            [alert.assetName, alert.symbol, alert.title, alert.reason]
                .compactMap(\.self)
                .joined(separator: " ")
        }
        return ([report.summary] + actions + alerts).joined(separator: "\n")
    }

    private static func relevanceScore(
        for item: AIReportChatItem,
        question: String,
        questionTokens: Set<String>
    ) -> Int {
        let content = content(for: item)
        let contentTokens = relevanceTokens(content)
        var score = questionTokens.intersection(contentTokens).count
        let normalizedQuestion = normalizedText(question)
        let normalizedContent = normalizedText(content)
        if normalizedContent.contains(normalizedQuestion) || normalizedQuestion.contains(normalizedContent) {
            score += 4
        }
        if item.kind == .user {
            score += min(1, score)
        }
        return score
    }

    private static func relevanceTokens(_ text: String) -> Set<String> {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let components = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
        var tokens = Set<String>()
        for component in components where component.count >= 2 {
            tokens.insert(component)
            let characters = Array(component)
            guard characters.count > 2 else { continue }
            for index in 0..<(characters.count - 1) {
                tokens.insert(String(characters[index...index + 1]))
            }
        }
        return tokens
    }

    private static func summary(for items: [AIReportChatItem]) -> AIFollowUpConversationSummary? {
        guard !items.isEmpty else { return nil }
        let userTopics = items
            .filter { $0.kind == .user }
            .suffix(4)
            .map { truncate(content(for: $0), limit: 240) }
        let assistantConclusions = items
            .filter { $0.kind == .assistant }
            .suffix(4)
            .map { truncate(content(for: $0), limit: 280) }
        let reportSummaries = items
            .filter { $0.kind == .report }
            .suffix(3)
            .map { truncate(content(for: $0), limit: 320) }
        return AIFollowUpConversationSummary(
            omittedItemCount: items.count,
            periodStart: items.first?.createdAt,
            periodEnd: items.last?.createdAt,
            earlierUserTopics: userTopics,
            earlierAssistantConclusions: assistantConclusions,
            earlierReportSummaries: reportSummaries
        )
    }

    private static func buildContext(
        sourceItemCount: Int,
        recentEntries: [AIFollowUpConversationEntry],
        relevantEntries: [AIFollowUpConversationEntry],
        summary: AIFollowUpConversationSummary?
    ) -> AIFollowUpConversationContext {
        AIFollowUpConversationContext(
            schemaVersion: "follow-up-context.v1",
            sourceItemCount: sourceItemCount,
            includedItemCount: recentEntries.count + relevantEntries.count,
            recentHistory: recentEntries,
            relevantEarlierHistory: relevantEntries,
            earlierHistorySummary: summary
        )
    }

    private static func shortened(
        _ entry: AIFollowUpConversationEntry,
        limit: Int
    ) -> AIFollowUpConversationEntry {
        AIFollowUpConversationEntry(
            id: entry.id,
            kind: entry.kind,
            createdAt: entry.createdAt,
            content: truncate(entry.content, limit: limit)
        )
    }

    private static func shortened(
        _ summary: AIFollowUpConversationSummary?,
        limit: Int
    ) -> AIFollowUpConversationSummary? {
        guard let summary else { return nil }
        return AIFollowUpConversationSummary(
            omittedItemCount: summary.omittedItemCount,
            periodStart: summary.periodStart,
            periodEnd: summary.periodEnd,
            earlierUserTopics: summary.earlierUserTopics.map { truncate($0, limit: limit) },
            earlierAssistantConclusions: summary.earlierAssistantConclusions.map { truncate($0, limit: limit) },
            earlierReportSummaries: summary.earlierReportSummaries.map { truncate($0, limit: limit) }
        )
    }

    private static func encodedCharacterCount(_ context: AIFollowUpConversationContext) -> Int {
        encodedJSON(context).utf8.count
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(1, limit - 1))) + "…"
    }
}
