import Foundation
import Testing
@testable import Portfolix

@Suite("Display preference persistence")
@MainActor
struct PortfolioDisplayPreferencesTests {
    @Test
    func freshInstallKeepsExistingDefaultsWithoutWritingOnRead() throws {
        let repository = try makeRepository()
        let store = PortfolioStore(positionRepository: repository)
        expectDefaults(store)
        for key in PortfolioDisplayPreferenceKey.allCases {
            #expect(try repository.appSetting(for: key.rawValue) == nil)
        }
    }

    @Test
    func selectionsSurviveNavigationMarketReloadAndRelaunch() throws {
        let repository = try makeRepository()
        let store = PortfolioStore(positionRepository: repository)
        store.investmentCloudMode = .distribution
        store.dailyProfitDisplayMode = .chart
        store.primaryPositionSortField = .profitRate
        store.primaryPositionSortDirection = .ascending
        store.trendMetric = .profitRate
        store.trendRange = .year
        store.displayCurrency = .usd
        store.appearanceMode = .dark
        store.performanceColorScheme = .redUpGreenDown
        for page in [SidebarSection.positions, .report, .settings, .overview] {
            store.selection = page
            #expect(store.investmentCloudMode == .distribution)
            #expect(store.dailyProfitDisplayMode == .chart)
            #expect(store.performanceColorScheme == .redUpGreenDown)
        }
        store.synchronizePersistedMarketDataIfNeeded()
        #expect(store.investmentCloudMode == .distribution)
        #expect(store.performanceColorScheme == .redUpGreenDown)
        let reopenedRepository = try PositionRepository(databaseURL: repository.storageURL)
        let restored = PortfolioStore(positionRepository: reopenedRepository)
        #expect(restored.investmentCloudMode == .distribution)
        #expect(restored.dailyProfitDisplayMode == .chart)
        #expect(restored.primaryPositionSortField == .profitRate)
        #expect(restored.primaryPositionSortDirection == .ascending)
        #expect(restored.trendMetric == .profitRate)
        #expect(restored.trendRange == .year)
        #expect(restored.displayCurrency == .usd)
        #expect(restored.appearanceMode == .dark)
        #expect(restored.performanceColorScheme == .redUpGreenDown)
        #expect(restored.persistenceErrorMessage == nil)
    }

    @Test
    func switchingBackToDefaultIsAlsoPersisted() throws {
        let repository = try makeRepository()
        let store = PortfolioStore(positionRepository: repository)
        for mode in [InvestmentCloudMode.distribution, .dailyProfit] {
            store.investmentCloudMode = mode
            #expect(PortfolioStore(positionRepository: repository).investmentCloudMode == mode)
        }
        for mode in [DailyProfitDisplayMode.chart, .calendar] {
            store.dailyProfitDisplayMode = mode
            #expect(PortfolioStore(positionRepository: repository).dailyProfitDisplayMode == mode)
        }
        for currency in DisplayCurrency.allCases {
            store.displayCurrency = currency
            #expect(PortfolioStore(positionRepository: repository).displayCurrency == currency)
        }
        for appearance in AppearanceMode.allCases {
            store.appearanceMode = appearance
            #expect(PortfolioStore(positionRepository: repository).appearanceMode == appearance)
        }
        for scheme in PerformanceColorScheme.allCases {
            store.performanceColorScheme = scheme
            #expect(PortfolioStore(positionRepository: repository).performanceColorScheme == scheme)
        }
        for metric in TrendMetric.allCases {
            store.trendMetric = metric
            #expect(PortfolioStore(positionRepository: repository).trendMetric == metric)
        }
        for range in TrendRange.allCases {
            store.trendRange = range
            #expect(PortfolioStore(positionRepository: repository).trendRange == range)
        }
    }

    @Test
    func unknownSavedValuesFallBackWithoutOverwritingStoredData() throws {
        let repository = try makeRepository()
        for key in PortfolioDisplayPreferenceKey.allCases {
            try repository.setAppSetting(key: key.rawValue, value: "unsupported-future-value")
        }
        let store = PortfolioStore(positionRepository: repository)
        expectDefaults(store)
        #expect(store.persistenceErrorMessage == nil)
        for key in PortfolioDisplayPreferenceKey.allCases {
            #expect(try repository.appSetting(for: key.rawValue) == "unsupported-future-value")
        }
    }

    @Test
    func preferencesRemainLocalToTheirRepository() throws {
        let first = PortfolioStore(positionRepository: try makeRepository())
        first.investmentCloudMode = .distribution
        first.dailyProfitDisplayMode = .chart
        first.displayCurrency = .hkd
        first.performanceColorScheme = .redUpGreenDown
        let separate = PortfolioStore(positionRepository: try makeRepository())
        expectDefaults(separate)
    }

    private func expectDefaults(_ store: PortfolioStore) {
        #expect(store.investmentCloudMode == .dailyProfit)
        #expect(store.dailyProfitDisplayMode == .calendar)
        #expect(store.primaryPositionSortField == .marketValue)
        #expect(store.primaryPositionSortDirection == .descending)
        #expect(store.trendMetric == .profitValue)
        #expect(store.trendRange == .month)
        #expect(store.displayCurrency == .cny)
        #expect(store.appearanceMode == .system)
        #expect(store.performanceColorScheme == .greenUpRedDown)
    }

    private func makeRepository() throws -> PositionRepository {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DisplayPreferenceTests-\(UUID())/portfolio.sqlite3")
        return try PositionRepository(databaseURL: url)
    }
}
