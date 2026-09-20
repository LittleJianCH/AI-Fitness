import Foundation

// Run on macOS against an already-built iOS app bundle. This checks the compiled
// native resources without adding app-bundle ownership to FitnessCore.
precondition(CommandLine.arguments.count == 2, "Pass the path to a compiled Fitness.app bundle")
let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
precondition(Bundle(url: appURL) != nil, "The compiled app bundle must exist")

func text(_ value: String.LocalizationValue, language: String) -> String {
    String(localized: LocalizedStringResource(value, locale: Locale(identifier: language), bundle: .atURL(appURL)))
}

precondition(text("Welcome back", language: "en") == "Welcome back")
precondition(text("Welcome back", language: "zh-Hans") == "欢迎回来")
precondition(text("Workouts", language: "zh-Hans") == "运动")
precondition(text("Workout history", language: "zh-Hans") == "运动记录")
precondition(text("Start", language: "zh-Hans") == "开始")
precondition(text("Route start", language: "zh-Hans") == "起点")
let one = 1
let two = 2
precondition(text("Preview selection (\(one))", language: "en") == "Preview 1 workout")
precondition(text("Preview selection (\(two))", language: "en") == "Preview 2 workouts")
precondition(text("Preview selection (\(two))", language: "zh-Hans") == "预览已选 2 条")
let load = "3.5"
precondition(text("\(one) workouts · Known load \(load)", language: "en") == "1 workout · Known load 3.5")
let title = "Settings"
precondition(text("\(title)", language: "zh-Hans") == title)
let missing = "A synthetic untranslated message"
precondition(text("A synthetic untranslated message", language: "zh-Hans") == missing)
var resource = LocalizedStringResource("Welcome back", locale: Locale(identifier: "en"), bundle: .atURL(appURL))
precondition(String(localized: resource) == "Welcome back")
resource.locale = Locale(identifier: "zh-Hans")
precondition(String(localized: resource) == "欢迎回来")
for language in ["en", "zh-Hans"] {
    guard let bundle = Bundle(url: appURL.appendingPathComponent("\(language).lproj")) else {
        fatalError("Missing compiled language bundle: \(language)")
    }
    for key in ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"] {
        let purpose = bundle.localizedString(forKey: key, value: nil, table: "InfoPlist")
        precondition(purpose != key && !purpose.isEmpty)
    }
}
print("Compiled native resources: both locales, plurals, active resource locale, verbatim content, missing-key fallback and permission purposes passed.")
