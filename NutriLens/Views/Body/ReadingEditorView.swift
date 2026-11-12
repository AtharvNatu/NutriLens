import NutriCore
import SwiftData
import SwiftUI

/// Review or edit a scale reading (all 22 values plus waist) before saving.
struct ReadingEditorView: View {
    let source: BodyReadingSource
    let existing: BodyMeasurement?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var values: [BodyMetric: Double]
    @State private var statuses: [BodyMetric: String]
    @State private var note: String
    @State private var saveToHealth = true
    @State private var isSaving = false
    @State private var error: String?
    private let recognised: Set<BodyMetric>

    init(reading: BodyReading, source: BodyReadingSource, existing: BodyMeasurement?) {
        self.source = source
        self.existing = existing
        _date = State(initialValue: reading.date ?? .now)
        _values = State(initialValue: reading.values)
        _statuses = State(initialValue: reading.statuses)
        _note = State(initialValue: existing?.note ?? "")
        recognised = source == .screenshot && existing == nil ? Set(reading.values.keys) : []
    }

    var body: some View {
        NavigationStack {
            Form {
                if source == .screenshot && existing == nil {
                    Section {
                        Label("Read \(recognised.count) of 22 values. Check each against your screenshot; edit anything misread.",
                              systemImage: recognised.count >= 20 ? "checkmark.seal" : "exclamationmark.triangle")
                            .foregroundStyle(recognised.count >= 20 ? .green : .orange)
                    }
                }
                Section {
                    DatePicker("Measured", selection: $date)
                }
                Section("Main") {
                    ForEach([BodyMetric.weight, .bodyFat, .muscleMass, .muscleMassPercent, .leanBodyMass, .bmi, .waist]) { row($0) }
                }
                Section("Composition") {
                    ForEach([BodyMetric.skeletalMuscle, .subcutaneousFat, .visceralFat, .bodyWater, .protein, .boneMass, .mineralSalt]) { row($0) }
                }
                Section("Scale app scores and targets") {
                    ForEach([BodyMetric.bmr, .metabolicAge, .healthScore, .obesityDegree, .bestVisualWeight, .standardWeight, .weightControl, .fatControl, .muscleControl]) { row($0) }
                }
                Section {
                    TextField("Note (e.g. after training, different clothes)", text: $note, axis: .vertical)
                    if env.health.isAvailable {
                        Toggle("Save weight, body fat, BMI, lean mass and waist to Apple Health", isOn: $saveToHealth)
                    }
                } footer: {
                    Text("All values are kept here; Apple Health gets weight, body fat, BMI, lean mass and waist.")
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
            }
            .navigationTitle(existing == nil ? "New reading" : "Edit reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Save") { Task { await save() } }.disabled(values.isEmpty)
                    }
                }
            }
        }
    }

    private func row(_ metric: BodyMetric) -> some View {
        HStack {
            Image(systemName: metric.symbolName).foregroundStyle(.secondary).frame(width: 22)
            Text(metric.displayName)
            if let status = statuses[metric] {
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            TextField("–", value: Binding(get: { values[metric] }, set: { values[metric] = $0 }), format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .foregroundStyle(recognised.contains(metric) ? Color.green : Color.primary)
            Text(metric.unit).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let reading = BodyReading(date: date, values: values.filter { $0.value.isFinite }, statuses: statuses)
        let measurement: BodyMeasurement
        if let existing {
            measurement = existing
            measurement.date = date
            measurement.apply(reading)
            measurement.note = note
        } else {
            measurement = BodyMeasurement(date: date, source: source, reading: reading, note: note)
            modelContext.insert(measurement)
        }
        if env.health.isAvailable && saveToHealth {
            do {
                if measurement.healthKitID != nil { try? await env.health.deleteBody(nutriLensID: measurement.id) }
                measurement.healthKitID = try await env.health.saveBody(reading, date: date, nutriLensID: measurement.id,
                                                                       payload: PayloadCoder.encode(measurement.payload))
            } catch HealthDataError.notFound {
                // Nothing Health can store (e.g. only scale scores); keep it local.
            } catch {
                self.error = "Saved in NutriLens, but not to Apple Health: \(error.localizedDescription)"
            }
        } else if measurement.healthKitID != nil, env.health.isAvailable {
            // Saving to Health was turned off for a reading that's already there: remove the old copy.
            try? await env.health.deleteBody(nutriLensID: measurement.id)
            measurement.healthKitID = nil
        }
        do {
            try modelContext.save()
        } catch {
            self.error = "Couldn't save: \(error.localizedDescription)"
            return
        }
        env.healthDidChange()
        if self.error == nil { dismiss() }
    }
}
