import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        TabView(selection: $state.activeTab) {
            TodayRootView()
                .environmentObject(state)
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(AppTab.today)

            WeeklyScheduleEditor()
                .environmentObject(ScheduleAppState())
                .tabItem {
                    Label("Schedule", systemImage: "calendar")
                }
                .tag(AppTab.schedule)

            StatsRootView()
                .environmentObject(state)
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
                .tag(AppTab.stats)
        }
        .onAppear { state.load() }
    }
}

// A thin wrapper to adapt TodayView to the shared AppState API
private struct TodayRootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        TodayView()
            .environmentObject(state)
    }
}

// A thin wrapper to present SevenDayStatsView as Stats tab
private struct StatsRootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationView {
            SevenDayStatsView()
                .environmentObject(state)
        }
    }
}

#Preview {
    ContentView()
}
