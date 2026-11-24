import SwiftUI

struct SevenDayStatsView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedDay: Date?
    
    // Last 7 days dates including today
    private var last7Days: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).map { calendar.date(byAdding: .day, value: -$0, to: today)! }.reversed()
    }
    
    // Metrics for last 7 days
    private var totalLast7Days: Int {
        last7Days.reduce(0) { $0 + state.totalCount(for: $1) }
    }
    
    private var plannedLast7Days: Int {
        last7Days.reduce(0) { $0 + state.plannedCount(for: $1) }
    }
    
    // Average per day since start (up to yesterday)
    private var averagePerDay: Double {
        guard let start = state.startDate else { return 0 }
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let days = calendar.dateComponents([.day], from: start, to: yesterday).day ?? 0
        guard days > 0 else { return 0 }
        let total = (0..<days).reduce(0) { sum, offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            return sum + state.totalCount(for: day)
        }
        return Double(total) / Double(days)
    }
    
    // Unexpected count last 7 days
    private var unexpectedLast7Days: Int {
        last7Days.reduce(0) { $0 + state.unexpectedCount(for: $1) }
    }
    
    // For bar chart max value
    private var maxCountIn7Days: Int {
        last7Days.map { state.totalCount(for: $0) }.max() ?? 1
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Summary cards
            HStack(spacing: 16) {
                card(title: "7-Day Total", mainValue: "\(totalLast7Days)", subtitle: "Planned: \(plannedLast7Days)")
                card(title: "Avg per Day", mainValue: String(format: "%.1f", averagePerDay), subtitle: "Since start (to yesterday)")
                card(title: "Unexpected", mainValue: "\(unexpectedLast7Days)", subtitle: "Last 7 days")
            }
            .padding(.horizontal)
            
            // Bar chart
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(last7Days, id: \.self) { day in
                    let count = state.totalCount(for: day)
                    VStack {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(height: maxCountIn7Days > 0 ? CGFloat(count) / CGFloat(maxCountIn7Days) * 100 : 0)
                        Text(day, style: .date)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)
            
            // List of daily logs
            List(last7Days, id: \.self) { day in
                Button(action: {
                    selectedDay = day
                }) {
                    HStack {
                        Text(day, style: .date)
                        Spacer()
                        Text("Total: \(state.totalCount(for: day))")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .sheet(item: $selectedDay) { day in
            DayDetailView(day: day)
                .environmentObject(state)
        }
        .navigationTitle("7-Day Stats & History")
    }
    
    private func card(title: String, mainValue: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(mainValue)
                .font(.largeTitle)
                .bold()
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(UIColor.secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

private struct DayDetailView: View {
    @EnvironmentObject var state: AppState
    let day: Date
    
    private var entries: [TimelineEntry] {
        state.timelineEntries(for: day)
            .sorted { $0.time < $1.time }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.time, style: .time)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(entry.type.rawValue.capitalized)
                                .font(.caption)
                                .padding(4)
                                .background(typeColor(entry.type).opacity(0.2))
                                .foregroundColor(typeColor(entry.type))
                                .cornerRadius(4)
                        }
                        if let reason = entry.reason, !reason.isEmpty {
                            Text(reason)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(day, formatter: dateFormatter)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController?.dismiss(animated: true)
                    }
                }
            }
        }
    }
    
    private func typeColor(_ type: TimelineEntryType) -> Color {
        switch type {
        case .scheduled:
            return .green
        case .unexpected:
            return .red
        case .traded:
            return .orange
        }
    }
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .full
        return df
    }
}

// MARK: - Sample AppState and related models for compilation

final class AppState: ObservableObject {
    var startDate: Date? = Calendar.current.date(byAdding: .month, value: -2, to: Date())
    
    func totalCount(for day: Date) -> Int {
        // Return total count for the day
        Int.random(in: 0...10)
    }
    
    func plannedCount(for day: Date) -> Int {
        // Return planned count for the day
        Int.random(in: 0...10)
    }
    
    func unexpectedCount(for day: Date) -> Int {
        // Return unexpected count for the day
        Int.random(in: 0...5)
    }
    
    func timelineEntries(for day: Date) -> [TimelineEntry] {
        // Return timeline entries for the day
        var entries = [TimelineEntry]()
        for hour in 8..<20 {
            let type: TimelineEntryType = [.scheduled, .unexpected, .traded].randomElement()!
            let reason = (type == .scheduled) ? "Scheduled event" : (type == .unexpected ? "Unexpected event" : "Traded event")
            let time = Calendar.current.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day)!
            entries.append(TimelineEntry(id: UUID(), time: time, type: type, reason: reason))
        }
        return entries
    }
}

struct TimelineEntry: Identifiable {
    let id: UUID
    let time: Date
    let type: TimelineEntryType
    let reason: String?
}

enum TimelineEntryType: String {
    case scheduled
    case unexpected
    case traded
}
