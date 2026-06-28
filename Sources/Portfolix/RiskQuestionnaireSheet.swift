import SwiftUI

struct RiskQuestionnaireSheet: View {
    @EnvironmentObject private var store: PortfolioStore
    @Environment(\.dismiss) private var dismiss

    @State private var investmentHorizon = "3-5 年"
    @State private var drawdown = "20%"
    @State private var singlePosition = "30%"
    @State private var crypto = "15%"
    @State private var foreignCurrency = "50%"
    @State private var liquidAssets = "10%"
    @State private var investmentExperience = "3-5 年"
    @State private var volatilityResponse = "观察并复核"
    @State private var customSinglePosition = "30"
    @State private var customCrypto = "15"
    @State private var customForeignCurrency = "50"
    @State private var customLiquidAssets = "10"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: localizedText("风险评估", "Risk Assessment", language: store.appLanguage),
                symbol: "checklist"
            )

            Divider().overlay(PortfolixTheme.border)

            Form {
                Section(localizedText("投资背景", "Investment Background", language: store.appLanguage)) {
                    Picker(localizedText("预计持有周期", "Expected holding period", language: store.appLanguage), selection: $investmentHorizon) {
                        Text(localizedText("< 1 年", "< 1 year", language: store.appLanguage)).tag("< 1 年")
                        Text(localizedText("1-3 年", "1-3 years", language: store.appLanguage)).tag("1-3 年")
                        Text(localizedText("3-5 年", "3-5 years", language: store.appLanguage)).tag("3-5 年")
                        Text(localizedText("> 5 年", "> 5 years", language: store.appLanguage)).tag("> 5 年")
                    }

                    Picker(localizedText("投资经验", "Investment experience", language: store.appLanguage), selection: $investmentExperience) {
                        Text(localizedText("初次接触", "New investor", language: store.appLanguage)).tag("初次接触")
                        Text(localizedText("1-3 年", "1-3 years", language: store.appLanguage)).tag("1-3 年")
                        Text(localizedText("3-5 年", "3-5 years", language: store.appLanguage)).tag("3-5 年")
                        Text(localizedText("> 5 年", "> 5 years", language: store.appLanguage)).tag("> 5 年")
                    }

                    Picker(localizedText("遇到明显波动时的反应", "Response to volatility", language: store.appLanguage), selection: $volatilityResponse) {
                        Text(localizedText("优先降低波动", "Reduce volatility first", language: store.appLanguage)).tag("优先降低波动")
                        Text(localizedText("观察并复核", "Observe and review", language: store.appLanguage)).tag("观察并复核")
                        Text(localizedText("可接受较大波动", "Accept higher volatility", language: store.appLanguage)).tag("可接受较大波动")
                    }
                }

                Section(localizedText("风险承受边界", "Risk Limits", language: store.appLanguage)) {
                    Picker(localizedText("可接受的阶段性最大回撤", "Maximum drawdown", language: store.appLanguage), selection: $drawdown) {
                        Text("5%").tag("5%")
                        Text("10%").tag("10%")
                        Text("20%").tag("20%")
                        Text("30%").tag("30%")
                        Text("> 30%").tag("> 30%")
                    }

                    ThresholdPicker(
                        title: localizedText("单一资产最大占比", "Max single asset", language: store.appLanguage),
                        selection: $singlePosition,
                        customValue: $customSinglePosition,
                        options: ["10%", "20%", "30%", "40%", "自定义"],
                        language: store.appLanguage
                    )

                    ThresholdPicker(
                        title: localizedText("数字货币最大占比", "Max crypto", language: store.appLanguage),
                        selection: $crypto,
                        customValue: $customCrypto,
                        options: ["0%", "5%", "10%", "15%", "20%", "自定义"],
                        language: store.appLanguage
                    )

                    ThresholdPicker(
                        title: localizedText("非基准币种资产最大占比", "Max non-base currency", language: store.appLanguage),
                        selection: $foreignCurrency,
                        customValue: $customForeignCurrency,
                        options: ["10%", "30%", "50%", "70%", "自定义"],
                        language: store.appLanguage
                    )

                    ThresholdPicker(
                        title: localizedText("最低流动资产占比", "Minimum liquidity", language: store.appLanguage),
                        selection: $liquidAssets,
                        customValue: $customLiquidAssets,
                        options: ["0%", "5%", "10%", "20%", "自定义"],
                        language: store.appLanguage
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider().overlay(PortfolixTheme.border)

            HStack {
                Spacer()

                Button(localizedText("取消", "Cancel", language: store.appLanguage)) {
                    dismiss()
                }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)

                Button(localizedText("保存为新版本", "Save Version", language: store.appLanguage)) {
                    saveQuestionnaire()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(PortfolixSpacing.xl)
        }
        .frame(width: 640, height: 680)
        .background {
            PortfolixSheetBackground()
        }
        .onAppear(perform: syncCurrentThresholds)
    }

    private func saveQuestionnaire() {
        store.applyRiskQuestionnaire(
            riskLevel: riskLevel,
            positionLimit: thresholdValue(selection: singlePosition, customValue: customSinglePosition, fallback: 30),
            cryptoLimit: thresholdValue(selection: crypto, customValue: customCrypto, fallback: 15),
            foreignCurrencyLimit: thresholdValue(selection: foreignCurrency, customValue: customForeignCurrency, fallback: 50),
            liquidityMinimum: thresholdValue(selection: liquidAssets, customValue: customLiquidAssets, fallback: 10)
        )
    }

    private var riskLevel: String {
        switch volatilityResponse {
        case "优先降低波动":
            "保守稳健"
        case "可接受较大波动":
            "积极成长"
        default:
            "稳健平衡"
        }
    }

    private func thresholdValue(selection: String, customValue: String, fallback: Double) -> Double {
        guard selection == "自定义" else {
            return Double(selection.replacingOccurrences(of: "%", with: "")) ?? fallback
        }
        return Double(customValue) ?? fallback
    }

    private func syncCurrentThresholds() {
        let singleOptions = ["10%", "20%", "30%", "40%"]
        let cryptoOptions = ["0%", "5%", "10%", "15%", "20%"]
        let foreignOptions = ["10%", "30%", "50%", "70%"]
        let liquidityOptions = ["0%", "5%", "10%", "20%"]

        (singlePosition, customSinglePosition) = thresholdSelection(for: store.positionLimit, options: singleOptions)
        (crypto, customCrypto) = thresholdSelection(for: store.cryptoLimit, options: cryptoOptions)
        (foreignCurrency, customForeignCurrency) = thresholdSelection(for: store.foreignCurrencyLimit, options: foreignOptions)
        (liquidAssets, customLiquidAssets) = thresholdSelection(for: store.liquidityMinimum, options: liquidityOptions)
    }

    private func thresholdSelection(for value: Double, options: [String]) -> (selection: String, customValue: String) {
        let formattedValue = formattedThreshold(value)
        let option = "\(formattedValue)%"
        if options.contains(option) {
            return (option, formattedValue)
        }
        return ("自定义", formattedValue)
    }

    private func formattedThreshold(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

private struct ThresholdPicker: View {
    let title: String
    @Binding var selection: String
    @Binding var customValue: String
    let options: [String]
    let language: AppLanguage

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(option == "自定义" ? localizedText("自定义", "Custom", language: language) : option).tag(option)
            }
        }

        if selection == "自定义" {
            TextField(language == .english ? "\(title) (%)" : "\(title)（%）", text: $customValue)
        }
    }
}
