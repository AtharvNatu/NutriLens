import NutriCore
import SwiftUI

enum Format {
    static func kcal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...(value < 10 ? 1 : 0)))) + " g"
    }

    static func signedKcal(_ value: Double) -> String {
        let rounded = value.rounded()
        return (rounded > 0 ? "+" : rounded < 0 ? "−" : "") + kcal(abs(rounded))
    }

    static func duration(_ interval: TimeInterval) -> String {
        Duration.seconds(interval).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }

    static func servings(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

enum Palette {
    static let eaten = Color.orange
    static let burned = Color.pink
    static let net = Color.teal
    static let protein = Color.red
    static let carbohydrates = Color.blue
    static let fat = Color.yellow
    static let steps = Color.green
}

/// Rounded "card" container used on the dashboard.
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

struct CardHeader: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(tint)
    }
}

/// Circular progress ring.
struct ProgressRing<Center: View>: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                // Over target: a second lap in a warning colour.
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(Color.red, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center
        }
        .animation(.easeOut, value: progress)
    }
}

/// Horizontal progress bar for a macronutrient.
struct MacroBar: View {
    let name: String
    let grams: Double
    let target: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Format.grams(grams)) / \(Format.grams(target))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(grams, max(target, 1)), total: max(target, 1))
                .tint(grams > target ? .red : tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small labelled number.
struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title3.bold().monospacedDigit())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MealRow: View {
    let entry: MealEntry
    /// Off when the row already sits under its meal's heading.
    var showsMealType = true

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.medium)).lineLimit(1)
                Text("\(showsMealType ? "\(entry.mealType.displayName) · " : "")\(entry.date.formatted(date: .omitted, time: .shortened)) · \(Format.grams(entry.grams))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("P \(Format.grams(entry.protein))  C \(Format.grams(entry.carbohydrates))  F \(Format.grams(entry.fat))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.kcal(entry.kilocalories)).font(.body.bold().monospacedDigit())
                Text("kcal").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var thumbnail: some View {
        if let data = entry.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            Image(systemName: entry.mealType.symbolName)
                .font(.body)
                .foregroundStyle(Palette.eaten)
                .frame(width: 40, height: 40)
                .background(Palette.eaten.opacity(0.15), in: .rect(cornerRadius: 8))
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.symbolName)
                .font(.title3)
                .foregroundStyle(Palette.burned)
                .frame(width: 40, height: 40)
                .background(Palette.burned.opacity(0.15), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.body.weight(.medium))
                Text("\(workout.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) · \(Format.duration(workout.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(workout.sourceName).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let energy = workout.energyBurned {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.kcal(energy)).font(.body.bold().monospacedDigit())
                    Text("kcal").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
