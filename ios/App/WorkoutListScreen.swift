import FitnessCore
import SwiftUI

@MainActor
struct WorkoutListScreen: View {
    let api: FitnessAPI
    let session: SessionStore
    @State private var store: WorkoutListStore
    @State private var sport: WorkoutSportFilter?
    @State private var action: Task<Void, Never>?

    init(api: FitnessAPI, session: SessionStore) {
        self.api = api
        self.session = session
        _store = State(initialValue: WorkoutListStore(service: api, session: session))
    }

    private var months: [(date: Date, items: [WorkoutCard])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.items) { row in
            calendar.dateInterval(of: .month, for: row.range.rangeStart)?.start ?? row.range.rangeStart
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("运动类型", selection: $sport) {
                    Text("全部").tag(Optional<WorkoutSportFilter>.none)
                    Text("骑行").tag(Optional(WorkoutSportFilter.cycling))
                    Text("跑步").tag(Optional(WorkoutSportFilter.running))
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("sportFilter")
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 14, trailing: 20))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)

                if store.items.isEmpty, store.isLoading {
                    ProgressView("正在加载运动…").frame(maxWidth: .infinity).padding(32)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else if store.items.isEmpty, store.hasLoaded, store.message == nil {
                    ContentUnavailableView("暂无运动记录", systemImage: "figure.run", description: Text("当前筛选下没有记录。"))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(months, id: \.date) { month in
                    Section {
                        ForEach(month.items, id: \.id) { row in
                            NavigationLink(value: row.id) { WorkoutRow(card: row) }
                                .accessibilityIdentifier("workout-\(row.id)")
                                .listRowInsets(EdgeInsets(top: 24, leading: 40, bottom: 24, trailing: 34))
                                .listRowSeparator(.hidden)
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: FitnessStyle.radius, style: .continuous)
                                        .fill(FitnessStyle.surface).padding(.horizontal, 20).padding(.vertical, 6)
                                )
                        }
                    } header: {
                        Text(month.date.formatted(.dateTime.year().month(.wide)))
                            .font(.title2.bold()).foregroundStyle(Color.primary).textCase(nil).padding(.vertical, 6)
                    }
                }
                if let message = store.message {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                        Button("重试") { action = Task { await store.refresh(sport: sport) } }.buttonStyle(.bordered)
                    }
                    .padding().fitnessCard().listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                if store.nextCursor != nil {
                    Button { action = Task { await store.loadMore() } } label: {
                        HStack {
                            Spacer()
                            if store.isLoading { ProgressView() } else { Label("加载更多", systemImage: "arrow.down") }
                            Spacer()
                        }.padding(10)
                    }
                    .disabled(store.isLoading).accessibilityIdentifier("loadMoreWorkouts")
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(FitnessStyle.background)
            .navigationTitle("运动记录")
            .navigationDestination(for: String.self) { id in
                WorkoutDetailScreen(id: id, api: api, session: session)
            }
            .refreshable { await store.refresh(sport: sport) }
            .task(id: sport) { await store.loadIfNeeded(sport: sport) }
            .onDisappear { action?.cancel() }
        }
    }
}

private struct WorkoutRow: View {
    let card: WorkoutCard
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var running: Bool { card.summary.sportName == "跑步" }
    private var accent: Color { running ? .orange : .blue }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: running ? "figure.run" : "figure.outdoor.cycle")
                    .font(.title2.weight(.medium)).foregroundStyle(accent).frame(width: 44, height: 44)
                    .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(card.summary.sportName)
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.displayTitle).font(.headline).foregroundStyle(.primary)
                    Text(card.range.rangeStart.formatted(.dateTime.day().weekday(.wide).hour().minute()))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                FitnessStat(title: "距离", value: WorkoutFormat.distance(card.summary.recordedCommonSummary.summaryDistance), color: accent)
                FitnessStat(title: "计时时间", value: WorkoutFormat.duration(card.summary.recordedCommonSummary.summaryTimerTime))
            }
        }
        .padding(.trailing, 4)
    }
}
