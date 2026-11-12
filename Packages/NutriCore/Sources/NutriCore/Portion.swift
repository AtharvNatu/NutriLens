import Foundation

/// How much of a food was eaten.
public enum Portion: Hashable, Sendable {
    /// A weight in grams.
    case grams(Double)
    /// A number of the food's typical servings (may be fractional, e.g. 1.5).
    case servings(Double)

    /// The portion's weight in grams for `food`. Negative or non-finite amounts count as zero.
    public func grams(for food: FoodItem) -> Double {
        let raw: Double
        switch self {
        case .grams(let g): raw = g
        case .servings(let s): raw = s * food.servingGrams
        }
        return raw.isFinite ? max(0, raw) : 0
    }

    /// The portion expressed as a number of servings of `food`.
    public func servings(for food: FoodItem) -> Double {
        guard food.servingGrams > 0 else { return 0 }
        return grams(for: food) / food.servingGrams
    }
}

extension FoodItem {
    /// Nutrients in `portion` of this food, scaled linearly from the per-100 g values.
    public func nutrients(for portion: Portion) -> Nutrients {
        per100g.scaled(by: portion.grams(for: self) / 100)
    }
}

/// Helpers for portion pickers in the UI.
public enum PortionPresets {
    /// Serving multipliers offered as quick choices.
    public static let servingMultipliers: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2, 3]

    /// Rounds a serving count to the nearest quarter, keeping it at least a quarter.
    public static func roundedServings(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return max(0.25, (value * 4).rounded() / 4)
    }
}
