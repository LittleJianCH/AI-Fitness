import SwiftUI

enum FitnessStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let radius: CGFloat = 30
}

extension View {
    func fitnessCard() -> some View {
        background(FitnessStyle.surface, in: RoundedRectangle(cornerRadius: FitnessStyle.radius, style: .continuous))
    }
}

struct FitnessSectionTitle: View {
    let title: LocalizedStringResource
    var color: Color = .primary
    var body: some View {
        LocalizedText(title).font(.title3.weight(.bold)).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading).accessibilityAddTraits(.isHeader)
    }
}

struct FitnessStat: View {
    let title: LocalizedStringResource
    let value: String
    var color: Color = .primary
    var prominent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalizedText(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(prominent ? .system(.largeTitle, design: .rounded, weight: .semibold) : .system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit().foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct FitnessIntro: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let symbol: String
    var color: Color = .blue
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: symbol).font(.system(.largeTitle, design: .rounded)).foregroundStyle(color)
                .padding(14).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
            LocalizedText(title).font(.title2.bold())
            LocalizedText(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }
}
