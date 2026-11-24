import SwiftUI
import Combine

struct TodayView: View {
    @EnvironmentObject var state: AppState
    
    @State private var showTradeSheet = false
    @State private var showUnexpectedSheet = false
    @State private var unexpectedReason = ""
    
    @State private var now = Date()
    
    private var lastSmokedDate: Date? {
        state.todaySlots
            .compactMap { $0.smokedDate }
            .max()
    }
    
    private var timeSinceLastSmoked: String {
        guard let last = lastSmokedDate else { return "--:--:--" }
        let interval = Int(now.timeIntervalSince(last))
        let h = interval / 3600
        let m = (interval % 3600) / 60
        let s = interval % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    
    private var progressFraction: Double {
        guard state.totalPlanned > 0 else { return 0 }
        return Double(state.totalSmoked) / Double(state.totalPlanned)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Progress")
                        .font(.headline)
                    ProgressView(value: progressFraction)
                        .progressViewStyle(LinearProgressViewStyle())
                    Text("\(state.totalSmoked) / \(state.totalPlanned) smoked")
                        .font(.subheadline)
                }
                VStack(spacing: 8) {
                    Text("Time Since Last Cigarette")
                        .font(.headline)
                    Text(timeSinceLastSmoked)
                        .font(.system(.title, design: .monospaced))
                        .padding(6)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(6)
                }
                List {
                    Section(header: Text("Today's Slots")) {
                        ForEach(state.todaySlots) { slot in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(slot.timeString)
                                        .font(.headline)
                                    if let reason = slot.unexpectedReason, slot.isUnexpected {
                                        Text("Unexpected: \(reason)").font(.caption).foregroundColor(.gray)
                                    }
                                    if slot.isSkipped {
                                        Text("Skipped").font(.caption).foregroundColor(.orange)
                                    }
                                    if slot.isSmoked {
                                        Text("Smoked").font(.caption).foregroundColor(.green)
                                    }
                                }
                                Spacer()
                                if slot.isSmoked {
                                    Button("Undo") {
                                        state.undoSlot(id: slot.id)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                } else if slot.isSkipped {
                                    Button("Undo") {
                                        state.undoSlot(id: slot.id)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                } else {
                                    HStack(spacing: 8) {
                                        Button("Mark Smoked") {
                                            state.markSlotSmoked(id: slot.id)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        Button("Skip") {
                                            state.skipSlot(id: slot.id)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                HStack(spacing: 20) {
                    Button("Smoke Now (Trade)") {
                        showTradeSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    Button("+1 Unexpected") {
                        unexpectedReason = ""
                        showUnexpectedSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom)
            }
            .padding(.horizontal)
            .navigationTitle("Today")
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                now = Date()
            }
            .sheet(isPresented: $showTradeSheet) {
                TradeSheetView(showSheet: $showTradeSheet)
                    .environmentObject(state)
            }
            .sheet(isPresented: $showUnexpectedSheet) {
                UnexpectedSheetView(showSheet: $showUnexpectedSheet, unexpectedReason: $unexpectedReason)
                    .environmentObject(state)
            }
        }
    }
}

private struct TradeSheetView: View {
    @EnvironmentObject var state: AppState
    @Binding var showSheet: Bool
    
    var tradableSlotsSkipped: [Slot] {
        state.todaySlots.filter { $0.isSkipped }
    }
    var tradableSlotsAvailable: [Slot] {
        state.todaySlots.filter { !$0.isSkipped && !$0.isSmoked }
    }
    
    var body: some View {
        NavigationView {
            List {
                if !tradableSlotsSkipped.isEmpty {
                    Section(header: Text("Skipped Slots")) {
                        ForEach(tradableSlotsSkipped) { slot in
                            Button(slot.timeString) {
                                state.confirmSwapSlot(slotId: slot.id, fromSkipped: true)
                                showSheet = false
                            }
                        }
                    }
                }
                if !tradableSlotsAvailable.isEmpty {
                    Section(header: Text("Available Slots")) {
                        ForEach(tradableSlotsAvailable) { slot in
                            Button(slot.timeString) {
                                state.confirmSwapSlot(slotId: slot.id, fromSkipped: false)
                                showSheet = false
                            }
                        }
                    }
                }
                if tradableSlotsSkipped.isEmpty && tradableSlotsAvailable.isEmpty {
                    Text("No tradable slots available")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
            .navigationTitle("Trade Slot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        showSheet = false
                    }
                }
            }
        }
    }
}

private struct UnexpectedSheetView: View {
    @EnvironmentObject var state: AppState
    @Binding var showSheet: Bool
    @Binding var unexpectedReason: String
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Reason (optional)")) {
                    TextField("Enter reason", text: $unexpectedReason)
                        .disableAutocorrection(true)
                }
                Section {
                    Button("Add Unexpected Slot") {
                        state.addUnexpected(reason: unexpectedReason.isEmpty ? nil : unexpectedReason)
                        showSheet = false
                    }
                    .disabled(false)
                }
            }
            .navigationTitle("+1 Unexpected")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSheet = false
                    }
                }
            }
        }
    }
}

// MARK: - Models (for preview/testing purpose)

final class AppState: ObservableObject {
    @Published var totalPlanned: Int = 5
    @Published var totalSmoked: Int = 2
    @Published var todaySlots: [Slot] = []
    
    func markSlotSmoked(id: UUID) {
        if let idx = todaySlots.firstIndex(where: { $0.id == id }) {
            todaySlots[idx].isSmoked = true
            todaySlots[idx].isSkipped = false
            todaySlots[idx].smokedDate = Date()
            totalSmoked = todaySlots.filter { $0.isSmoked }.count
        }
    }
    func skipSlot(id: UUID) {
        if let idx = todaySlots.firstIndex(where: { $0.id == id }) {
            todaySlots[idx].isSkipped = true
            todaySlots[idx].isSmoked = false
            todaySlots[idx].smokedDate = nil
            totalSmoked = todaySlots.filter { $0.isSmoked }.count
        }
    }
    func undoSlot(id: UUID) {
        if let idx = todaySlots.firstIndex(where: { $0.id == id }) {
            todaySlots[idx].isSkipped = false
            todaySlots[idx].isSmoked = false
            todaySlots[idx].smokedDate = nil
            totalSmoked = todaySlots.filter { $0.isSmoked }.count
        }
    }
    func confirmSwapSlot(slotId: UUID, fromSkipped: Bool) {
        // Simple swap logic: mark tradable slot as smoked if fromSkipped, else mark skipped
        if let idx = todaySlots.firstIndex(where: { $0.id == slotId }) {
            if fromSkipped {
                todaySlots[idx].isSmoked = true
                todaySlots[idx].isSkipped = false
                todaySlots[idx].smokedDate = Date()
            } else {
                todaySlots[idx].isSkipped = true
                todaySlots[idx].isSmoked = false
                todaySlots[idx].smokedDate = nil
            }
            totalSmoked = todaySlots.filter { $0.isSmoked }.count
        }
    }
    func addUnexpected(reason: String?) {
        let newSlot = Slot(id: UUID(), time: Date(), isSmoked: true, isSkipped: false, unexpectedReason: reason, isUnexpected: true, smokedDate: Date())
        todaySlots.append(newSlot)
        totalSmoked = todaySlots.filter { $0.isSmoked }.count
        totalPlanned += 1
    }
}

struct Slot: Identifiable {
    let id: UUID
    let time: Date
    var isSmoked: Bool
    var isSkipped: Bool
    var unexpectedReason: String?
    var isUnexpected: Bool
    var smokedDate: Date?
    
    var isSmokedComputed: Bool { isSmoked }
    var timeString: String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: time)
    }
}

struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        let state = AppState()
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        state.todaySlots = [
            Slot(id: UUID(), time: cal.date(byAdding: .hour, value: 9, to: base)!, isSmoked: true, isSkipped: false, unexpectedReason: nil, isUnexpected: false, smokedDate: Date().addingTimeInterval(-3600)),
            Slot(id: UUID(), time: cal.date(byAdding: .hour, value: 12, to: base)!, isSmoked: false, isSkipped: true, unexpectedReason: nil, isUnexpected: false, smokedDate: nil),
            Slot(id: UUID(), time: cal.date(byAdding: .hour, value: 15, to: base)!, isSmoked: false, isSkipped: false, unexpectedReason: nil, isUnexpected: false, smokedDate: nil),
        ]
        state.totalPlanned = 3
        state.totalSmoked = 1
        return TodayView()
            .environmentObject(state)
    }
}
