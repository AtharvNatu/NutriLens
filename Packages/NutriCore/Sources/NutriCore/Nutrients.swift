import Foundation

/// Energy and macronutrients for some amount of food.
///
/// Energy is in kilocalories (the "Calories" on food labels); macros are in grams.
public struct Nutrients: Codable, Hashable, Sendable {
    public var kilocalories: Double
    public var protein: Double
    public var carbohydrates: Double
    public var fat: Double

    public init(kilocalories: Double, protein: Double, carbohydrates: Double, fat: Double) {
        self.kilocalories = kilocalories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }

    public static let zero = Nutrients(kilocalories: 0, protein: 0, carbohydrates: 0, fat: 0)

    /// Atwater factors used to turn grams of macronutrient into kilocalories.
    public enum EnergyPerGram {
        public static let protein = 4.0
        public static let carbohydrates = 4.0
        public static let fat = 9.0
    }

    /// Returns these nutrients multiplied by `factor` (negative factors are treated as zero).
    public func scaled(by factor: Double) -> Nutrients {
        let f = factor.isFinite ? max(0, factor) : 0
        return Nutrients(
            kilocalories: kilocalories * f,
            protein: protein * f,
            carbohydrates: carbohydrates * f,
            fat: fat * f
        )
    }

    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            kilocalories: lhs.kilocalories + rhs.kilocalories,
            protein: lhs.protein + rhs.protein,
            carbohydrates: lhs.carbohydrates + rhs.carbohydrates,
            fat: lhs.fat + rhs.fat
        )
    }

    public static func += (lhs: inout Nutrients, rhs: Nutrients) {
        lhs = lhs + rhs
    }

    /// Kilocalories implied by the macros alone (ignores fibre and alcohol).
    public var kilocaloriesFromMacros: Double {
        protein * EnergyPerGram.protein
            + carbohydrates * EnergyPerGram.carbohydrates
            + fat * EnergyPerGram.fat
    }

    /// Share of macro energy coming from protein, carbohydrates and fat (each 0...1, summing to 1),
    /// or all zero when there are no macros.
    public var macroEnergySplit: (protein: Double, carbohydrates: Double, fat: Double) {
        let total = kilocaloriesFromMacros
        guard total > 0 else { return (0, 0, 0) }
        return (
            protein * EnergyPerGram.protein / total,
            carbohydrates * EnergyPerGram.carbohydrates / total,
            fat * EnergyPerGram.fat / total
        )
    }
}

extension Sequence where Element == Nutrients {
    /// Sum of all nutrients in the sequence.
    public func total() -> Nutrients {
        reduce(.zero, +)
    }
}
