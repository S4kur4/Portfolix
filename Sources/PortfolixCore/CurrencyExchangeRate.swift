import Foundation

/// Fixed currency conversion factors from CNY shared across the app and background updater.
public enum CurrencyExchangeRate {
    public static func rateFromCNY(for currencyCode: String) -> Decimal {
        switch currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "HKD": Decimal(string: "1.153431425")!
        case "USD": Decimal(string: "0.147215543")!
        case "USDT": Decimal(string: "0.147289188")!
        default: 1
        }
    }
}

/// Normalizes US equity symbols while preserving share-class suffixes such as BRK.B.
public enum USSymbolNormalizer {
    public static func normalize(_ value: String) -> String {
        var symbol = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let prefixRange = symbol.range(of: #"^\d+\."#, options: .regularExpression) {
            symbol.removeSubrange(prefixRange)
        }
        if symbol.hasPrefix("US."), symbol.count > 3 {
            symbol.removeFirst(3)
        }
        if symbol.hasSuffix(".US"), symbol.count > 3 {
            symbol.removeLast(3)
        }
        return symbol
    }
}
