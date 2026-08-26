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
                                    Text(trip.routeSummary)
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
                } header: {
                    Text("Your trips")
                } footer: {
                    Text("Select a trip to make it active, then generate its shift schedule. Edit stops in the itinerary.")
                }

                Section("Build a plan") {
                    Button {
                        model.generatePlan()
                    } label: {
                        Label("Generate schedule for \(model.trip.name)", systemImage: "sparkles")
                    }
                    NavigationLink {
                        ItineraryView()
                    } label: {
                        Label("Edit itinerary", systemImage: "pencil")
                    }
                }

                Section("Add") {
                    Button {
                        model.addTrip(Trips.blank())
                    } label: {
                        Label("New blank trip", systemImage: "plus")
                    }
                    Button {
                        model.duplicateActive()
                    } label: {
                        Label("Duplicate current trip", systemImage: "plus.square.on.square")
                    }
                    Button {
                        model.addTrip(Trips.usAugust2026())
                    } label: {
                        Label("Add US Aug–Sep 2026 template", systemImage: "airplane.departure")
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
