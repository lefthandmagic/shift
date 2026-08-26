import SwiftUI

struct ItineraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Trip") {
                TextField("Name", text: Binding(
                    get: { model.trip.name },
                    set: { model.trip.name = $0; model.persist() }
                ))
                Picker("Home timezone", selection: Binding(
                    get: { model.trip.homeTimeZoneIdentifier },
                    set: {
                        model.trip.homeTimeZoneIdentifier = $0
                        model.rebuild()
                    }
                )) {
                    ForEach(TimeZoneCatalog.options(including: model.trip.homeTimeZoneIdentifier)) { option in
                        Text(option.name).tag(option.identifier)
                    }
                }
            }

            Section {
                ForEach(model.trip.segments) { segment in
                    NavigationLink {
                        SegmentEditorView(segmentID: segment.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(segment.name)
                                if segment.isFlight {
                                    Text("Flight")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.25), in: Capsule())
                                }
                            }
                            Text(rangeLabel(segment))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { model.trip.segments[$0].id }
                    ids.forEach { model.deleteSegment(id: $0) }
                }
                Button("Add stop") {
                    model.addSegment()
                }
            } header: {
                Text("Stops")
            } footer: {
                Text("Editing a start or end time also moves the neighbouring stop so the trip stays in one line. ATL → LAX is still a placeholder until you book — change Atlanta’s end or LA’s start.")
            }

            Section("Events") {
                ForEach(model.trip.events) { event in
                    NavigationLink {
                        EventEditorView(eventID: event.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.name)
                            Text(eventRangeLabel(event))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    let ids = indexSet.map { model.trip.events[$0].id }
                    ids.forEach { model.deleteEvent(id: $0) }
                }
                Button("Add event") {
                    model.addEvent()
                }
            }

            Section {
                Button("Reset to US trip (29 Aug–11 Sep)", role: .destructive) {
                    confirmReset = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ShiftTheme.bg.ignoresSafeArea())
        .navigationTitle("Itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Generate") { model.generatePlan() }
            }
        }
        .confirmationDialog("Reset itinerary?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset to default US trip", role: .destructive) {
                model.resetTrip()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces your edits with the baked-in AMS → Miami → Atlanta → LA → SF trip.")
        }
    }

    private func rangeLabel(_ segment: TripSegment) -> String {
        let tz = segment.timeZone
        let start = ClockMath.format(segment.start, timeZone: tz, template: "EEE d MMM HH:mm")
        let end = ClockMath.format(segment.end, timeZone: tz, template: "EEE d MMM HH:mm")
        return "\(start) → \(end) · \(tz.identifier)"
    }

    private func eventRangeLabel(_ event: TripEvent) -> String {
        let tz = model.trip.homeTimeZone
        let start = ClockMath.format(event.start, timeZone: tz, template: "EEE d MMM HH:mm")
        let end = ClockMath.format(event.end, timeZone: tz, template: "HH:mm")
        return "\(start)–\(end)"
    }
}

struct SegmentEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let segmentID: UUID
    @State private var draft: TripSegment
    @State private var confirmDelete = false

    init(segmentID: UUID) {
        self.segmentID = segmentID
        _draft = State(initialValue: TripSegment(
            id: segmentID,
            name: "",
            timeZone: TimeZone(identifier: "UTC")!,
            start: Date(),
            end: Date(),
            isFlight: false
        ))
    }

    var body: some View {
        Form {
            Section("Stop") {
                TextField("Name", text: $draft.name)
                Picker("Timezone", selection: timezoneBinding) {
                    ForEach(TimeZoneCatalog.options(including: draft.timeZoneIdentifier)) { option in
                        Text(option.name).tag(option.identifier)
                    }
                }
                Toggle("This is a flight", isOn: $draft.isFlight)
            }
            Section {
                DatePicker("Starts", selection: $draft.start)
                    .environment(\.timeZone, draft.timeZone)
                DatePicker("Ends", selection: $draft.end)
                    .environment(\.timeZone, draft.timeZone)
            } footer: {
                Text("Times are in this stop’s timezone. Saving also updates the neighbouring stops so they meet.")
            }
            if model.trip.segments.count > 1 {
                Section {
                    Button("Delete stop", role: .destructive) {
                        confirmDelete = true
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ShiftTheme.bg.ignoresSafeArea())
        .navigationTitle(draft.name.isEmpty ? "Stop" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveAndDismiss() }
            }
        }
        .onAppear {
            if let live = model.trip.segments.first(where: { $0.id == segmentID }) {
                draft = live
            }
        }
        .confirmationDialog("Delete this stop?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.deleteSegment(id: segmentID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var timezoneBinding: Binding<String> {
        Binding(
            get: { draft.timeZoneIdentifier },
            set: { newID in
                let from = draft.timeZone
                let to = TimeZone(identifier: newID) ?? from
                draft.start = ClockMath.keepingWallClock(draft.start, from: from, to: to)
                draft.end = ClockMath.keepingWallClock(draft.end, from: from, to: to)
                draft.timeZoneIdentifier = newID
            }
        )
    }

    private func saveAndDismiss() {
        model.replaceSegment(draft)
        dismiss()
    }
}

struct EventEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let eventID: UUID
    @State private var draft: TripEvent
    @State private var confirmDelete = false

    init(eventID: UUID) {
        self.eventID = eventID
        _draft = State(initialValue: TripEvent(id: eventID, name: "", start: Date(), end: Date()))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                DatePicker("Starts", selection: $draft.start)
                    .environment(\.timeZone, model.trip.homeTimeZone)
                DatePicker("Ends", selection: $draft.end)
                    .environment(\.timeZone, model.trip.homeTimeZone)
            } header: {
                Text("Event")
            } footer: {
                Text("Event times use the trip’s home timezone (\(model.trip.homeTimeZone.identifier)). Shift uses this to keep bedtime after the event on that day.")
            }
            Section {
                Button("Delete event", role: .destructive) {
                    confirmDelete = true
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ShiftTheme.bg.ignoresSafeArea())
        .navigationTitle(draft.name.isEmpty ? "Event" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    model.replaceEvent(draft)
                    dismiss()
                }
            }
        }
        .onAppear {
            if let live = model.trip.events.first(where: { $0.id == eventID }) {
                draft = live
            }
        }
        .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                model.deleteEvent(id: eventID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
