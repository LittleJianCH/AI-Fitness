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

                if store.items.isEmpty, store.isLoading {
                    ProgressView("正在加载运动…")
                } else if store.items.isEmpty, store.hasLoaded, store.message == nil {
                    ContentUnavailableView("暂无运动记录", systemImage: "figure.run", description: Text("当前筛选下没有记录。"))
                }
                ForEach(store.items, id: \.id) { row in
                    NavigationLink(value: row.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(row.displayTitle).font(.headline)
                                Spacer()
                                Text(row.summary.sportName).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(row.range.rangeStart.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundStyle(.secondary)
                            HStack(spacing: 20) {
                                Label(WorkoutFormat.distance(row.summary.recordedCommonSummary.summaryDistance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                Label(WorkoutFormat.duration(row.summary.recordedCommonSummary.summaryTimerTime), systemImage: "stopwatch")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                    }
                    .accessibilityIdentifier("workout-\(row.id)")
                }
                if let message = store.message {
                    Section {
                        Text(message).foregroundStyle(.red)
                        Button("重试") { action = Task { await store.refresh(sport: sport) } }
                    }
                }
                if store.nextCursor != nil {
                    Button {
                        action = Task { await store.loadMore() }
                    } label: {
                        if store.isLoading { ProgressView() } else { Text("加载更多") }
                    }
                    .disabled(store.isLoading)
                    .accessibilityIdentifier("loadMoreWorkouts")
                }
            }
            .navigationTitle("运动记录")
            .navigationDestination(for: String.self) { id in
                WorkoutDetailScreen(id: id, api: api, session: session)
            }
            .refreshable { await store.refresh(sport: sport) }
            .task(id: sport) { await store.refresh(sport: sport) }
            .onDisappear { action?.cancel() }
        }
    }
}
