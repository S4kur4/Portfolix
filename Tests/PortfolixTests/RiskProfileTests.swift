import Foundation
import Testing
@testable import Portfolix

@Suite("Risk Profile Guardrails & Draft Semantics")
struct RiskProfileTests {
    private func makeRepository() throws -> (URL, PositionRepository) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("portfolix-risk-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("portfolio.sqlite3")
        return (dbURL, try PositionRepository(databaseURL: dbURL))
    }

    @MainActor
    @Test
    func savingDraftBumpsVersionOnceAndPersistsAllNewProfileFields() throws {
        let (dbURL, repo) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let store = PortfolioStore(positionRepository: repo)

        let initialVersion = store.riskProfileVersion
        var draft = store.currentRiskProfileDraft
        draft.tier = .conservative
        draft.applyRecommendedGuardrails()
        draft.investmentGoal = .capitalPreservation
        draft.investmentHorizon = .oneToThreeYears
        draft.investmentExperience = .overFiveYears
        draft.reviewCadence = .quarterly
        draft.positionLimit = 22
        draft.riskAssetLimit = 38
        draft.maxDrawdownLimit = 12

        // Modifying draft in memory does not bump store version or mark configured yet.
        #expect(store.riskProfileVersion == initialVersion)
        #expect(!store.riskProfileConfigured)

        let saveDate = Date(timeIntervalSince1970: 1_800_000_000)
        store.saveRiskProfile(draft, now: saveDate)

        #expect(store.riskProfileConfigured)
        #expect(store.riskProfileVersion == initialVersion + 1)
        #expect(store.riskLevel == RiskProfileTier.conservative.rawValue)
        #expect(store.riskInvestmentGoal == RiskInvestmentGoal.capitalPreservation.rawValue)
        #expect(store.riskInvestmentHorizon == RiskInvestmentHorizon.oneToThreeYears.rawValue)
        #expect(store.riskInvestmentExperience == RiskInvestmentExperience.overFiveYears.rawValue)
        #expect(store.riskReviewCadenceMonths == 3)
        #expect(store.riskDrawdownTolerance == "12%")
        #expect(store.positionLimit == 22)
        #expect(store.riskAssetLimit == 38)

        let reloaded = PortfolioStore(
            positionRepository: try PositionRepository(databaseURL: dbURL)
        )
        #expect(reloaded.riskProfileConfigured)
        #expect(reloaded.riskProfileVersion == initialVersion + 1)
        #expect(reloaded.currentRiskProfileDraft == draft)
    }

    @MainActor
    @Test
    func singleAssetConcentrationExcludesCashHoldings() throws {
        let (dbURL, repo) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let store = PortfolioStore(positionRepository: repo)

        try store.addPosition(
            name: "现金人民币",
            symbol: "CNY",
            category: .cash,
            quantity: 800,
            averageCost: 1,
            quoteCurrency: .cny,
            latestPrice: 1
        )
        try store.addPosition(
            name: "核心指数基金",
            symbol: "COREETF",
            category: .fund,
            quantity: 200,
            averageCost: 1,
            quoteCurrency: .cny,
            latestPrice: 1
        )

        store.positionLimit = 30
        let evaluation = store.riskConstraintEvaluation
        #expect(evaluation.hasPositions)
        #expect(evaluation.largestPositionName == "核心指数基金")
        #expect(abs(evaluation.largestPositionPercent - 20) < 0.01)
        #expect(evaluation.isPositionLimitPassing)
        #expect(abs(evaluation.cashAllocationPercent - 80) < 0.01)
    }

    @Test
    func cashOnlyPortfolioRemainsHasPositionsWithZeroConcentration() {
        let cash = Position(
            name: "现金人民币",
            symbol: "CNY",
            category: .cash,
            quoteCurrency: .cny,
            quantity: 1000,
            averageCost: 1,
            latestPrice: 1,
            marketValueCNY: 1000,
            profitRate: 0,
            weeklyTrend: [],
            source: "Cash",
            quoteTime: "2026-11-28",
            freshness: .updated
        )
        let eval = RiskConstraintEvaluation.evaluate(
            positions: [cash],
            positionLimit: 20,
            cryptoLimit: 0,
            foreignCurrencyLimit: 30,
            liquidityMinimum: 10,
            riskAssetLimit: 35
        )
        #expect(eval.hasPositions)
        #expect(eval.largestPositionName == nil)
        #expect(eval.largestPositionPercent == 0)
        #expect(eval.isPositionLimitPassing)
        #expect(eval.breachCount == 0)
    }

    @Test
    func drawdownAndHighVolatilityGuardrailsDetectBreachesAndRespectBaseCurrency() {
        let usStock = Position(
            name: "NVIDIA",
            symbol: "NVDA",
            category: .usStock,
            quoteCurrency: .usd,
            quantity: 100,
            averageCost: 1,
            latestPrice: 1,
            marketValueCNY: 700,
            profitRate: 0,
            weeklyTrend: [],
            source: "Yahoo",
            quoteTime: "2026-11-28",
            freshness: .updated
        )
        let cnyCash = Position(
            name: "现金人民币",
            symbol: "CNY",
            category: .cash,
            quoteCurrency: .cny,
            quantity: 300,
            averageCost: 1,
            latestPrice: 1,
            marketValueCNY: 300,
            profitRate: 0,
            weeklyTrend: [],
            source: "Cash",
            quoteTime: "2026-11-28",
            freshness: .updated
        )

        let eval = RiskConstraintEvaluation.evaluate(
            positions: [usStock, cnyCash],
            positionLimit: 40,
            cryptoLimit: 10,
            foreignCurrencyLimit: 50,
            liquidityMinimum: 10,
            baseCurrency: .usd,
            riskAssetLimit: 50,
            currentDrawdownPercent: 24.5,
            historicalMaxDrawdownPercent: 28.0,
            maxDrawdownLimit: 20
        )

        // With USD as base currency, only CNY cash (30%) is foreign currency -> passes 50% cap.
        #expect(abs(eval.nonCNYAllocationPercent - 30) < 0.01)
        #expect(eval.isForeignCurrencyLimitPassing)
        // High-volatility stocks + crypto = 70% > 50% limit.
        #expect(abs(eval.highVolatilityAllocationPercent - 70) < 0.01)
        #expect(eval.isRiskAssetLimitPassing == false)
        // Current drawdown 24.5% > 20% limit.
        #expect(eval.isDrawdownPassing == false)
        // Single non-cash asset = 70% > 40% limit.
        #expect(!eval.isPositionLimitPassing)
        #expect(eval.constraintCount == 6)
        #expect(eval.breachCount == 3)
        #expect(!eval.breachedLabels(language: .chinese).isEmpty)
    }

    @Test
    func draftConsistencyHintsAndReviewHealthTrackCadenceExpiration() {
        var draft = RiskProfileDraft.defaultBalanced
        draft.tier = .conservative
        draft.cryptoLimit = 40
        draft.riskAssetLimit = 30
        draft.maxDrawdownLimit = 25
        let hints = draft.consistencyHints(language: .chinese)
        #expect(hints.count >= 2)

        draft.applyRecommendedGuardrails()
        #expect(draft.matchesRecommendedGuardrails)
        #expect(draft.consistencyHints(language: .chinese).isEmpty)

        let passingEval = RiskConstraintEvaluation(
            largestPositionName: "Fund",
            largestPositionPercent: 15,
            cryptoAllocationPercent: 0,
            nonCNYAllocationPercent: 10,
            cashAllocationPercent: 30,
            positionLimit: 20,
            cryptoLimit: 5,
            foreignCurrencyLimit: 30,
            liquidityMinimum: 20,
            totalValueCNY: 100_000,
            riskAssetLimit: 35
        )
        let calendar = Calendar(identifier: .gregorian)
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let twoMonthsLater = calendar.date(byAdding: .month, value: 2, to: savedAt)!
        let sevenMonthsLater = calendar.date(byAdding: .month, value: 7, to: savedAt)!

        #expect(draft.reviewHealth(isConfigured: false, updatedAt: savedAt, evaluation: passingEval, now: twoMonthsLater, calendar: calendar) == .notConfigured)
        if case .valid = draft.reviewHealth(isConfigured: true, updatedAt: savedAt, evaluation: passingEval, now: twoMonthsLater, calendar: calendar) {
            // Expected
        } else {
            Issue.record("Expected .valid within 6-month cadence")
        }
        if case .reviewDue = draft.reviewHealth(isConfigured: true, updatedAt: savedAt, evaluation: passingEval, now: sevenMonthsLater, calendar: calendar) {
            // Expected
        } else {
            Issue.record("Expected .reviewDue after 6-month cadence elapsed")
        }
    }

    @MainActor
    @Test
    func backupExportAndImportRoundTripsExtendedRiskProfileFields() throws {
        let (sourceDB, sourceRepo) = try makeRepository()
        let (targetDB, targetRepo) = try makeRepository()
        let exportURL = sourceDB.deletingLastPathComponent().appendingPathComponent("backup.portfolix.zip")
        defer {
            try? FileManager.default.removeItem(at: sourceDB.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: targetDB.deletingLastPathComponent())
        }

        let sourceStore = PortfolioStore(positionRepository: sourceRepo)
        var draft = RiskProfileDraft.defaultBalanced
        draft.tier = .growth
        draft.applyRecommendedGuardrails()
        draft.investmentGoal = .longTermCompounding
        draft.investmentHorizon = .overFiveYears
        draft.investmentExperience = .overFiveYears
        draft.reviewCadence = .annual
        draft.riskAssetLimit = 85
        draft.maxDrawdownLimit = 32
        sourceStore.saveRiskProfile(draft)

        _ = try sourceStore.exportFinancialData(to: exportURL)

        let targetStore = PortfolioStore(positionRepository: targetRepo)
        let prepared = try targetStore.prepareFinancialDataImport(from: exportURL)
        _ = try targetStore.importFinancialData(prepared)

        #expect(targetStore.riskProfileConfigured)
        #expect(targetStore.currentRiskProfileDraft == draft)
    }

    @Test
    func threeTierGuardrailSeverityUses80PercentAnd120PercentBoundaries() {
        // Maximum limits: <80% normal, 80%...100% approaching, >100% breached
        #expect(RiskGuardrailSeverity.evaluate(actual: 23.9, limit: 30, isMinimum: false) == .normal)
        #expect(RiskGuardrailSeverity.evaluate(actual: 24.0, limit: 30, isMinimum: false) == .approaching)
        #expect(RiskGuardrailSeverity.evaluate(actual: 30.0, limit: 30, isMinimum: false) == .approaching)
        #expect(RiskGuardrailSeverity.evaluate(actual: 30.1, limit: 30, isMinimum: false) == .breached)
        // Zero cap edge case: 0% is normal, >0% is breached
        #expect(RiskGuardrailSeverity.evaluate(actual: 0, limit: 0, isMinimum: false) == .normal)
        #expect(RiskGuardrailSeverity.evaluate(actual: 0.5, limit: 0, isMinimum: false) == .breached)

        // Minimum floor (cash): >120% normal, 100%...120% approaching, <100% breached
        #expect(RiskGuardrailSeverity.evaluate(actual: 12.1, limit: 10, isMinimum: true) == .normal)
        #expect(RiskGuardrailSeverity.evaluate(actual: 12.0, limit: 10, isMinimum: true) == .approaching)
        #expect(RiskGuardrailSeverity.evaluate(actual: 10.0, limit: 10, isMinimum: true) == .approaching)
        #expect(RiskGuardrailSeverity.evaluate(actual: 9.9, limit: 10, isMinimum: true) == .breached)
        #expect(RiskGuardrailSeverity.evaluate(actual: 0, limit: 0, isMinimum: true) == .normal)
        #expect(RiskGuardrailSeverity.evaluate(actual: nil, limit: 20, isMinimum: false) == .noData)
    }

    @MainActor
    @Test
    func unsavedNavigationGuardInterceptsSavesDiscardsAndCancelsCleanly() throws {
        let (dbURL, repo) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let store = PortfolioStore(positionRepository: repo)
        store.selection = .riskProfile

        var draft = store.currentRiskProfileDraft
        draft.positionLimit = 22
        store.unsavedRiskProfileDraft = draft

        // Attempting to navigate away intercepts rather than switching immediately
        store.requestSidebarNavigation(to: .overview)
        #expect(store.selection == .riskProfile)
        #expect(store.pendingSidebarSelection == .overview)

        // Cancel keeps editing
        store.cancelPendingSidebarNavigation()
        #expect(store.selection == .riskProfile)
        #expect(store.pendingSidebarSelection == nil)
        #expect(store.unsavedRiskProfileDraft != nil)

        // Save & leave commits draft and switches
        store.requestSidebarNavigation(to: .positions)
        store.saveUnsavedRiskProfileAndContinueNavigation()
        #expect(store.selection == .positions)
        #expect(store.positionLimit == 22)
        #expect(store.riskProfileConfigured)
        #expect(store.unsavedRiskProfileDraft == nil)
        #expect(store.pendingSidebarSelection == nil)

        // Discard & leave drops draft and switches
        store.selection = .riskProfile
        var discardedDraft = store.currentRiskProfileDraft
        discardedDraft.positionLimit = 45
        store.unsavedRiskProfileDraft = discardedDraft
        store.requestSidebarNavigation(to: .settings)
        store.discardUnsavedRiskProfileAndContinueNavigation()
        #expect(store.selection == .settings)
        #expect(store.positionLimit == 22)
        #expect(store.unsavedRiskProfileDraft == nil)
    }

    @Test
    func presetChangesAndChangedFieldCountReportExactDiffs() {
        var draft = RiskProfileDraft.defaultBalanced
        let conservativeDiffs = draft.presetChanges(for: .conservative, language: .chinese)
        #expect(conservativeDiffs.count == 6)
        #expect(conservativeDiffs.first(where: { $0.id == "position" })?.targetValue == "20%")

        let original = draft
        draft.tier = .growth
        draft.positionLimit = 35
        draft.investmentGoal = .longTermCompounding
        #expect(draft.changedFieldCount(comparedTo: original) == 3)
    }

    @Test
    func followUpParserAndGuardrailRejectLeakedDeepSeekDSMLToolCallMarkup() {
        let leakedSpacedDSML = """
        < | | DSML | | calls>
        < | | DSML | | invoke name="simulate_rebalance">
        < | | DSML | | parameter name="target_weights" string="true">[{"position_ref":"position_1","target_weight_pct":20}]</ | | DSML | | parameter>
        </ | | DSML | | invoke>
        </ | | DSML | | calls>
        """
        let leakedFullwidthDSML = "<｜DSML｜function_calls><｜DSML｜invoke name=\"get_portfolio_constraints\"></｜DSML｜invoke></｜DSML｜function_calls>"
        let leakedXMLToolCall = "<tool_call>{\"name\":\"simulate_rebalance\"}</tool_call>"

        #expect(AIFollowUpResponseParser.containsLeakedToolCallMarkup(leakedSpacedDSML))
        #expect(AIFollowUpResponseParser.containsLeakedToolCallMarkup(leakedFullwidthDSML))
        #expect(AIFollowUpResponseParser.containsLeakedToolCallMarkup(leakedXMLToolCall))
        #expect(AIFollowUpResponseParser.decode(leakedSpacedDSML) == nil)
        #expect(AIFollowUpResponseParser.decode(leakedFullwidthDSML) == nil)
        #expect(throws: Error.self) {
            _ = try AIFollowUpGuardrail.validatedAnswer(leakedSpacedDSML)
        }
        // Normal portfolio analysis prose passes cleanly.
        let normalReply = "当前组合全部 6 项风险护栏均在范围内，建议继续跟踪 BTC 波动。"
        #expect(!AIFollowUpResponseParser.containsLeakedToolCallMarkup(normalReply))
        #expect(AIFollowUpResponseParser.decode(normalReply)?.answer == normalReply)
    }

    @MainActor
    @Test
    func importingLegacyBackupClearsStaleExtendedRiskProfileFields() throws {
        let (targetDB, targetRepo) = try makeRepository()
        let legacyBackupURL = targetDB.deletingLastPathComponent().appendingPathComponent("legacy.portfolix.zip")
        defer { try? FileManager.default.removeItem(at: targetDB.deletingLastPathComponent()) }

        // Seed target store with customized extended fields first.
        let store = PortfolioStore(positionRepository: targetRepo)
        var extendedDraft = RiskProfileDraft.defaultBalanced
        extendedDraft.tier = .growth
        extendedDraft.investmentGoal = .longTermCompounding
        extendedDraft.reviewCadence = .annual
        extendedDraft.riskAssetLimit = 88
        store.saveRiskProfile(extendedDraft)

        // Export a legacy payload where optional extended fields are nil.
        let legacyPayload = PortfolixDataPackage.Payload(
            holdings: [],
            portfolioSnapshots: [],
            assetPriceSnapshots: [],
            riskProfile: PortfolixDataPackage.RiskProfile(
                configured: true,
                level: "保守稳健",
                version: 2,
                positionLimit: "25",
                cryptoLimit: "5",
                foreignCurrencyLimit: "30",
                liquidityMinimum: "20",
                updatedAt: "2026-11-20T08:00:00Z"
            )
        )
        _ = try PortfolixDataPackageService.write(payload: legacyPayload, to: legacyBackupURL)

        let prepared = try store.prepareFinancialDataImport(from: legacyBackupURL)
        _ = try store.importFinancialData(prepared)

        #expect(store.riskLevel == "保守稳健")
        #expect(store.positionLimit == 25)
        #expect(store.riskAssetLimit == 65)
        #expect(store.riskInvestmentGoal.isEmpty)
        #expect(store.riskReviewCadenceMonths == 6)
    }

    @MainActor
    @Test
    func changingDisplayCurrencyToHKDDoesNotTriggerFalseForeignCurrencyBreach() throws {
        let (dbURL, repo) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }
        let store = PortfolioStore(positionRepository: repo)

        try store.addPosition(
            name: "人民币基金",
            symbol: "CNYFUND",
            category: .fund,
            quantity: 800,
            averageCost: 1,
            quoteCurrency: .cny,
            latestPrice: 1
        )
        try store.addPosition(
            name: "BTC",
            symbol: "BTC/USDT",
            category: .crypto,
            quantity: 200 * DisplayCurrency.usdt.rateFromCNY,
            averageCost: 1,
            quoteCurrency: .usdt,
            latestPrice: 1
        )
        store.foreignCurrencyLimit = 50

        store.displayCurrency = .cny
        let cnyEval = store.riskConstraintEvaluation
        #expect(cnyEval.baseCurrency == .cny)
        #expect(abs(cnyEval.nonCNYAllocationPercent - 20) < 0.1)
        #expect(cnyEval.isForeignCurrencyLimitPassing)

        // Switching display currency to HKD must NOT turn CNY holdings into 100% foreign currency!
        store.displayCurrency = .hkd
        let hkdEval = store.riskConstraintEvaluation
        #expect(hkdEval.baseCurrency == .cny)
        #expect(abs(hkdEval.nonCNYAllocationPercent - 20) < 0.1)
        #expect(hkdEval.isForeignCurrencyLimitPassing)
        #expect(hkdEval.breachCount == cnyEval.breachCount)

        let draftEval = store.evaluateRiskConstraints(for: store.currentRiskProfileDraft)
        #expect(draftEval.baseCurrency == .cny)
        #expect(abs(draftEval.nonCNYAllocationPercent - 20) < 0.1)
    }
}
