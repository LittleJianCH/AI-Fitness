import Foundation

public enum NumericInput {
    /// Parse the entire localized input, never a valid prefix followed by invalid text.
    public static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = input.wholeMatch(of: .localizedDouble(locale: locale))?.output,
              value.isFinite else { return nil }
        return value
    }
}
