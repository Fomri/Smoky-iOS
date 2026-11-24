import SwiftUI

// Assuming ScheduleAppState is defined like this:
class ScheduleAppState: ObservableObject {
    @Published var weeklySlots: [Weekday: [ScheduleSlot]] = [:] // Recurring slots per day
    @Published var nextSlots: [Weekday: [ScheduleSlot]] = [:]   // One-time override slots per day
    
    init() {
        resetSampleWeek()
    }
    
    func resetSampleWeek() {
        weeklySlots = [
            Weekday.mon: [ScheduleSlot(time: DateComponents.make(hour: 9, minute: 0), label: "Morning", count: 1),
                          ScheduleSlot(time: DateComponents.make(hour: 14, minute: 0), label: "Afternoon", count: 2)],
            Weekday.tue: [ScheduleSlot(time: DateComponents.make(hour: 10, minute: 0), label: "Meeting", count: 1)],
            Weekday.wed: [],
            Weekday.thu: [ScheduleSlot(time: DateComponents.make(hour: 13, minute: 0), label: "Lunch", count: 3)],
            Weekday.fri: [ScheduleSlot(time: DateComponents.make(hour: 16, minute: 0), label: "Wrap-up", count: 1)],
            Weekday.sat: [],
            Weekday.sun: []
        ]
        nextSlots = [:]
    }
}

enum Weekday: Int, CaseIterable, Identifiable {
    case sun, mon, tue, wed, thu, fri, sat
    
    var id: Int { rawValue }
    var shortName: String {
        switch self {
        case .sun: return "Sun"
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        }
    }
}

struct ScheduleSlot: Identifiable, Equatable {
    let id: UUID
    var time: DateComponents
    var label: String
    var count: Int
    
    init(id: UUID = UUID(), time: DateComponents, label: String, count: Int) {
        self.id = id
        self.time = time
        self.label = label
        self.count = count
    }
}

extension DateComponents {
    static func make(hour: Int, minute: Int) -> DateComponents {
        var dc = DateComponents()
        dc.hour = hour
        dc.minute = minute
        return dc
    }
    func toDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? now
    }
}

struct WeeklyScheduleEditor: View {
    enum Mode: String, CaseIterable, Identifiable {
        case recurring = "Recurring"
        case next = "Next"
        var id: String { rawValue }
    }
    
    @EnvironmentObject var state: ScheduleAppState
    @State private var mode: Mode = .recurring
    @State private var selectedDay: Weekday = .mon
    @State private var showAddSlotSheet = false
    @State private var editSlot: ScheduleSlot?
    @State private var showCopyDaySheet = false
    
    var slots: [ScheduleSlot] {
        switch mode {
            case .recurring: return state.weeklySlots[selectedDay] ?? []
            case .next: return state.nextSlots[selectedDay] ?? []
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                DayPicker(selectedDay: $selectedDay)
                    .padding(.vertical, 4)
                
                List {
                    ForEach(slots) { slot in
                        HStack {
                            Text(slot.time.toDate(), style: .time)
                                .font(.system(.body, design: .monospaced))
                            VStack(alignment: .leading) {
                                Text(slot.label)
                                    .font(.headline)
                                Text("Count: \(slot.count)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                editSlot = slot
                                showAddSlotSheet = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .onDelete { idxSet in
                        deleteSlots(at: idxSet)
                    }
                }
                
                HStack(spacing: 20) {
                    Button("Add Slot") {
                        editSlot = nil
                        showAddSlotSheet = true
                    }
                    Button("Copy Day") {
                        showCopyDaySheet = true
                    }
                    Spacer()
                }
                .padding([.horizontal, .bottom])
                
                HStack(spacing: 20) {
                    Button("Clear Day") {
                        clearDay()
                    }
                    Button("Reset Sample Week") {
                        state.resetSampleWeek()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            .navigationTitle("Schedule Editor")
            .sheet(isPresented: $showAddSlotSheet) {
                AddEditSlotView(
                    slot: $editSlot,
                    onSave: { newSlot in
                        saveSlot(newSlot)
                        showAddSlotSheet = false
                    },
                    onCancel: { showAddSlotSheet = false }
                )
                .environmentObject(state)
            }
            .sheet(isPresented: $showCopyDaySheet) {
                CopyDaySheet(
                    sourceDay: selectedDay,
                    onCopy: { targets in
                        copyDaySlots(to: targets)
                        showCopyDaySheet = false
                    },
                    onCancel: { showCopyDaySheet = false }
                )
                .environmentObject(state)
            }
        }
    }
    
    func saveSlot(_ slot: ScheduleSlot) {
        switch mode {
        case .recurring:
            var daySlots = state.weeklySlots[selectedDay] ?? []
            if let idx = daySlots.firstIndex(where: { $0.id == slot.id }) {
                daySlots[idx] = slot
            } else {
                daySlots.append(slot)
            }
            state.weeklySlots[selectedDay] = daySlots.sorted { ($0.time.hour ?? 0, $0.time.minute ?? 0) < ($1.time.hour ?? 0, $1.time.minute ?? 0) }
            
        case .next:
            var daySlots = state.nextSlots[selectedDay] ?? []
            if let idx = daySlots.firstIndex(where: { $0.id == slot.id }) {
                daySlots[idx] = slot
            } else {
                daySlots.append(slot)
            }
            state.nextSlots[selectedDay] = daySlots.sorted { ($0.time.hour ?? 0, $0.time.minute ?? 0) < ($1.time.hour ?? 0, $1.time.minute ?? 0) }
        }
    }
    
    func deleteSlots(at offsets: IndexSet) {
        switch mode {
        case .recurring:
            var daySlots = state.weeklySlots[selectedDay] ?? []
            daySlots.remove(atOffsets: offsets)
            state.weeklySlots[selectedDay] = daySlots
        case .next:
            var daySlots = state.nextSlots[selectedDay] ?? []
            daySlots.remove(atOffsets: offsets)
            state.nextSlots[selectedDay] = daySlots
        }
    }
    
    func clearDay() {
        switch mode {
        case .recurring:
            state.weeklySlots[selectedDay] = []
        case .next:
            state.nextSlots[selectedDay] = []
        }
    }
    
    func copyDaySlots(to targets: [Weekday]) {
        guard !targets.isEmpty else { return }
        let sourceSlots = slots
        switch mode {
        case .recurring:
            for day in targets {
                state.weeklySlots[day] = sourceSlots
            }
        case .next:
            for day in targets {
                state.nextSlots[day] = sourceSlots
            }
        }
    }
}

struct DayPicker: View {
    @Binding var selectedDay: Weekday
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.allCases) { day in
                Button(action: {
                    selectedDay = day
                }) {
                    Text(day.shortName)
                        .fontWeight(selectedDay == day ? .bold : .regular)
                        .padding(8)
                        .frame(minWidth: 30)
                        .background(selectedDay == day ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct AddEditSlotView: View {
    @EnvironmentObject var state: ScheduleAppState
    @Binding var slot: ScheduleSlot?
    
    @State private var time: Date = Date()
    @State private var label: String = ""
    @State private var count: Int = 1
    
    var onSave: (ScheduleSlot) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(WheelDatePickerStyle())
                TextField("Label", text: $label)
                Picker("Count", selection: $count) {
                    ForEach(1...3, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .navigationTitle(slot == nil ? "Add Slot" : "Edit Slot")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let calendar = Calendar.current
                        let comps = calendar.dateComponents([.hour, .minute], from: time)
                        let newSlot = ScheduleSlot(
                            id: slot?.id ?? UUID(),
                            time: comps,
                            label: label,
                            count: count
                        )
                        onSave(newSlot)
                    }
                    .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .onAppear {
                if let slot = slot {
                    let calendar = Calendar.current
                    let date = slot.time.toDate()
                    time = date
                    label = slot.label
                    count = slot.count
                } else {
                    let calendar = Calendar.current
                    let now = Date()
                    let comps = calendar.dateComponents([.hour, .minute], from: now)
                    time = calendar.date(from: comps) ?? now
                    label = ""
                    count = 1
                }
            }
        }
    }
}

struct CopyDaySheet: View {
    @EnvironmentObject var state: ScheduleAppState
    
    let sourceDay: Weekday
    @State private var selectedDays: [Weekday: Bool] = [:]
    
    var onCopy: ([Weekday]) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Copy \(sourceDay.shortName) slots to:")) {
                    ForEach(Weekday.allCases) { day in
                        if day != sourceDay {
                            Toggle(day.shortName, isOn: Binding(
                                get: { selectedDays[day] ?? false },
                                set: { selectedDays[day] = $0 }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Copy Day")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") {
                        let targets = selectedDays.filter { $0.value }.map { $0.key }
                        onCopy(targets)
                    }
                    .disabled(!selectedDays.values.contains(true))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .onAppear {
                for day in Weekday.allCases where day != sourceDay {
                    selectedDays[day] = false
                }
            }
        }
    }
}

struct WeeklyScheduleEditor_Previews: PreviewProvider {
    static var previews: some View {
        WeeklyScheduleEditor()
            .environmentObject(ScheduleAppState())
    }
}
