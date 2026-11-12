import NutriCore
import SwiftUI

/// One exercise at a time: prescription, last time, Digital Crown inputs and a one-tap "Done set".
struct StrengthView: View {
    @Bindable var session: StrengthSession
    @FocusState private var field: Field?

    enum Field: Hashable { case reps, load, left }

    var body: some View {
        ZStack {
            if let item = session.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        header(item)
                        inputs(item)
                        doneButton(item)
                        loggedSets(item)
                        navigation
                    }
                }
                .id(item.id)
            }
            if session.restUntil != nil {
                RestOverlay(session: session)
            }
        }
        .onAppear { field = .reps }
    }

    private func header(_ item: StrengthSession.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(session.index + 1) of \(session.items.count)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(item.exercise.name)
                .font(.headline)
                .lineLimit(2)
            Text("\(item.prescription.label) · \(PlanPhase.forWeek(session.week).repsInReserve)")
                .font(.footnote)
                .foregroundStyle(.orange)
            if let last = item.history.last {
                Text("Last: " + last.map { "\($0.reps)" }.joined(separator: ", ") + " @ " + ProgressionAdvice.kg(last.map(\.loadKg).max() ?? 0))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let note = item.planned.note {
                Text("Keep it \(note).").font(.footnote).foregroundStyle(.yellow)
            }
        }
    }

    private func inputs(_ item: StrengthSession.Item) -> some View {
        HStack(spacing: 4) {
            CrownField(title: item.prescription.seconds ? "Sec" : "Reps", value: $session.reps, range: 1...120, step: 1,
                       text: "\(Int(session.reps.rounded()))", focused: field == .reps)
                .focused($field, equals: .reps)
                .onTapGesture { field = .reps }
            if item.exercise.usesLoad {
                CrownField(title: "kg", value: $session.load, range: 0...60, step: 0.5,
                           text: session.load.formatted(.number.precision(.fractionLength(0...1))), focused: field == .load)
                    .focused($field, equals: .load)
                    .onTapGesture { field = .load }
            }
            CrownField(title: "Left", value: $session.repsLeft, range: 0...4, step: 1,
                       text: session.repsLeft >= 4 ? "4+" : "\(Int(session.repsLeft.rounded()))", focused: field == .left)
                .focused($field, equals: .left)
                .onTapGesture { field = .left }
        }
    }

    private func doneButton(_ item: StrengthSession.Item) -> some View {
        let count = session.sets(for: item).count
        return Button {
            session.logSet()
            Haptics.play(.click)
            field = .reps
        } label: {
            Label(count >= item.prescription.sets ? "Extra set" : "Done set \(count + 1)/\(item.prescription.sets)", systemImage: "checkmark")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .tint(.green)
    }

    @ViewBuilder private func loggedSets(_ item: StrengthSession.Item) -> some View {
        let sets = session.sets(for: item)
        if !sets.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(sets.enumerated()), id: \.offset) { n, set in
                    Text("\(n + 1). \(set.reps)\(item.prescription.seconds ? " s" : "") · \(ProgressionAdvice.kg(set.loadKg)) · \(set.repsInReserve.map { $0 >= 4 ? "4+" : "\($0)" } ?? "–") left")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.green)
                }
                Button("Undo last set", role: .destructive) { session.removeLastSet() }
                    .font(.footnote)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
        }
    }

    private var navigation: some View {
        HStack {
            Button { session.index -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(session.index == 0)
            Button("Skip") { session.skip() }
                .font(.footnote)
                .disabled(session.index >= session.items.count - 1)
            Button { session.index += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(session.index >= session.items.count - 1)
        }
        .buttonStyle(.bordered)
    }
}

/// A value the Digital Crown changes while it's selected (tap to select).
struct CrownField: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let text: String
    let focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(focused ? 0.18 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focused ? Color.green : .clear, lineWidth: 2))
        .focusable()
        .digitalCrownRotation($value, from: range.lowerBound, through: range.upperBound, by: step,
                               sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityElement(children: .combine)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

/// Rest countdown with a tap on the wrist when it's over.
struct RestOverlay: View {
    let session: StrengthSession

    var body: some View {
        if let until = session.restUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = until.timeIntervalSince(context.date)
                VStack(spacing: 6) {
                    Text(remaining > 0 ? "Rest" : "Next set")
                        .font(.headline)
                        .foregroundStyle(remaining > 0 ? .orange : .green)
                    Text(remaining > 0 ? ElapsedTime.format(remaining.rounded(.up)) : "Go")
                        .font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    if let next = session.current {
                        Text(next.exercise.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Button(remaining > 0 ? "Skip rest" : "OK") { session.endRest() }
                        .tint(remaining > 0 ? .gray : .green)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }
            .task(id: until) {
                let wait = until.timeIntervalSinceNow
                if wait > 10 {
                    try? await Task.sleep(for: .seconds(wait - 10))
                    guard !Task.isCancelled else { return }
                    Haptics.play(.click)
                }
                try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                Haptics.play(.success)
            }
        }
    }
}
