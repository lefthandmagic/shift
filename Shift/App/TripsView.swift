import SwiftUI

struct TripsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete: Trip?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.trips) { trip in
                        Button {
                            model.selectTrip(id: trip.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: trip.id == model.activeTripID ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(trip.id == model.activeTripID ? ShiftTheme.accent : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(trip.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(trip.dateSpanLabel)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(trip.compactRoute)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if model.trips.count > 1 {
                                Button(role: .destructive) {
                                    confirmDelete = trip
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        model.generatePlan()
                    } label: {
                        Label("Generate schedule", systemImage: "sparkles")
                    }
                    NavigationLink {
                        ItineraryView()
                    } label: {
                        Label("Edit itinerary", systemImage: "pencil")
                    }
                    Button {
                        model.addTrip(Trips.blank())
                    } label: {
                        Label("New trip", systemImage: "plus")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ShiftTheme.bg.ignoresSafeArea())
            .navigationTitle("Trips")
            .confirmationDialog(
                "Delete \(confirmDelete?.name ?? "trip")?",
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let id = confirmDelete?.id {
                        model.deleteTrip(id: id)
                    }
                    confirmDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    confirmDelete = nil
                }
            }
        }
    }
}
