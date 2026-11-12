import Foundation
import HealthKit
import NutriCore

/// `HealthDataProviding` backed by HealthKit.
final class HealthKitService: HealthDataProviding {
    private let store = HKHealthStore()
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Authorization

    private static let mealTypes: [HKQuantityType] = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
    ]

    private static let bodyTypes: [HKQuantityType] = [
        HKQuantityType(.bodyMass),
        HKQuantityType(.bodyFatPercentage),
        HKQuantityType(.bodyMassIndex),
        HKQuantityType(.leanBodyMass),
        HKQuantityType(.waistCircumference),
    ]

    private static let sleepType = HKCategoryType(.sleepAnalysis)

    private static var shareTypes: Set<HKSampleType> {
        Set<HKSampleType>(mealTypes).union(bodyTypes).union([
            HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), sleepType,
        ])
    }

    private static var readTypes: Set<HKObjectType> {
        Set<HKObjectType>(mealTypes).union(bodyTypes).union([
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKObjectType.workoutType(),
            sleepType,
            HKQuantityType(.height),
            HKCharacteristicType(.biologicalSex),
            HKCharacteristicType(.dateOfBirth),
        ])
    }

    func shouldRequestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: Self.shareTypes, read: Self.readTypes)
            return status == .shouldRequest
        } catch {
            return true
        }
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    // MARK: Helpers

    private func datePredicate(_ start: Date, _ end: Date) -> NSPredicate {
        HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
    }

    private func taggedPredicate(_ start: Date, _ end: Date) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            datePredicate(start, end),
            HKQuery.predicateForObjects(withMetadataKey: HealthSyncKey.recordID),
        ])
    }

    private func metadata(name: String? = nil, nutriLensID: UUID?, payload: String?) -> [String: Any] {
        var metadata: [String: Any] = [:]
        if let name { metadata[HKMetadataKeyFoodType] = name }
        if let nutriLensID { metadata[HealthSyncKey.recordID] = nutriLensID.uuidString }
        if let payload { metadata[HealthSyncKey.payload] = payload }
        return metadata
    }

    private static func tag(of object: HKObject) -> (UUID?, String?) {
        let id = (object.metadata?[HealthSyncKey.recordID] as? String).flatMap(UUID.init(uuidString:))
        return (id, object.metadata?[HealthSyncKey.payload] as? String)
    }

    // MARK: Activity

    func activity(for days: [Date]) async throws -> [Date: ActivitySummary] {
        guard isAvailable, let first = days.min(), let last = days.max() else { return [:] }
        let start = calendar.startOfDay(for: first)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return [:] }

        async let steps = dailySums(.stepCount, unit: .count(), from: start, to: end)
        async let active = dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        async let basal = dailySums(.basalEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        let (s, a, b) = try await (steps, active, basal)

        var result: [Date: ActivitySummary] = [:]
        for day in days.map(calendar.startOfDay(for:)) {
            result[day] = ActivitySummary(steps: s[day] ?? 0, activeEnergy: a[day] ?? 0, basalEnergy: b[day] ?? 0)
        }
        return result
    }

    /// Per-day cumulative sums keyed by start of day. Health de-duplicates overlapping
    /// sources (e.g. iPhone and Apple Watch steps) in statistics queries.
    private func dailySums(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [Date: Double] {
        let type = HKQuantityType(identifier)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: datePredicate(start, end)),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await query.result(for: store)
            var sums: [Date: Double] = [:]
            for statistics in collection.statistics() {
                sums[calendar.startOfDay(for: statistics.startDate)] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
            }
            return sums
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined || error.code == .errorAuthorizationDenied {
            return [:]
        }
    }

    // MARK: Workouts

    func workouts(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        guard isAvailable else { return [] }
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(datePredicate(start, end))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 200
        )
        return try await query.result(for: store).map(summary)
    }

    func nutriLensWorkouts(from start: Date, to end: Date) async throws -> [WorkoutSummary] {
        guard isAvailable else { return [] }
        let query = HKSampleQueryDescriptor(
            predicates: [.workout(taggedPredicate(start, end))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try await query.result(for: store).map(summary)
    }

    func stepCount(from start: Date, to end: Date) async throws -> Double {
        guard isAvailable, end > start else { return 0 }
        let query = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.stepCount), predicate: datePredicate(start, end)),
            options: .cumulativeSum
        )
        do {
            return try await query.result(for: store)?.sumQuantity()?.doubleValue(for: .count()) ?? 0
        } catch let error as HKError where error.code == .errorAuthorizationNotDetermined || error.code == .errorAuthorizationDenied || error.code == .errorNoData {
            return 0
        }
    }

    private func summary(_ workout: HKWorkout) -> WorkoutSummary {
        let info = WorkoutActivityInfo(workout.workoutActivityType)
        let (id, payload) = Self.tag(of: workout)
        return WorkoutSummary(
            id: workout.uuid,
            name: info.name,
            symbolName: info.symbolName,
            start: workout.startDate,
            end: workout.endDate,
            energyBurned: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            sourceName: workout.sourceRevision.source.name,
            nutriLensID: id,
            payload: payload,
            isCardio: WorkoutActivityInfo.isCardio(workout.workoutActivityType)
        )
    }

    func saveWorkout(kind: ActivityKind, start: Date, end: Date, kilocalories: Double, nutriLensID: UUID?, payload: String?) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = WorkoutActivityInfo.healthKitType(for: kind)
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: start)
        if kilocalories > 0 {
            let energy = HKQuantitySample(
                type: HKQuantityType(.activeEnergyBurned),
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                start: start,
                end: end
            )
            try await builder.addSamples([energy])
        }
        let tags = metadata(nutriLensID: nutriLensID, payload: payload)
        if !tags.isEmpty { try await builder.addMetadata(tags) }
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { throw HealthDataError.notFound }
        return workout.uuid
    }

    func deleteWorkout(id: UUID) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let query = HKSampleQueryDescriptor(predicates: [.workout(HKQuery.predicateForObject(with: id))], sortDescriptors: [], limit: 1)
        guard let workout = try await query.result(for: store).first else { throw HealthDataError.notFound }
        try await store.delete(workout)
    }

    func latestBodyMass() async throws -> Double? {
        guard isAvailable else { return nil }
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await query.result(for: store).first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    // MARK: Meals

    func saveMeal(_ meal: MealSample) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        let tags = metadata(name: meal.name, nutriLensID: meal.nutriLensID, payload: meal.payload)
        func sample(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double) -> HKQuantitySample {
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: max(0, value)),
                             start: meal.date, end: meal.date, metadata: tags)
        }
        let samples: Set<HKSample> = [
            sample(.dietaryEnergyConsumed, .kilocalorie(), meal.nutrients.kilocalories),
            sample(.dietaryProtein, .gram(), meal.nutrients.protein),
            sample(.dietaryCarbohydrates, .gram(), meal.nutrients.carbohydrates),
            sample(.dietaryFatTotal, .gram(), meal.nutrients.fat),
        ]
        let food = HKCorrelation(type: HKCorrelationType(.food), start: meal.date, end: meal.date, objects: samples, metadata: tags)
        try await store.save(food)
        return food.uuid
    }

    func deleteMeal(id: UUID) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let query = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: HKQuery.predicateForObject(with: id))],
            sortDescriptors: [],
            limit: 1
        )
        guard let correlation = try await query.result(for: store).first else { throw HealthDataError.notFound }
        // Deleting a correlation leaves its samples behind, so delete them too.
        let objects: [HKObject] = [correlation] + Array(correlation.objects)
        try await store.delete(objects)
    }

    func mealRecords(from start: Date, to end: Date) async throws -> [MealRecord] {
        guard isAvailable else { return [] }
        let query = HKSampleQueryDescriptor(
            predicates: [.correlation(type: HKCorrelationType(.food), predicate: taggedPredicate(start, end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).compactMap { correlation in
            let (id, payload) = Self.tag(of: correlation)
            guard let id else { return nil }
            var n = Nutrients.zero
            for case let sample as HKQuantitySample in correlation.objects {
                switch sample.quantityType {
                case HKQuantityType(.dietaryEnergyConsumed): n.kilocalories += sample.quantity.doubleValue(for: .kilocalorie())
                case HKQuantityType(.dietaryProtein): n.protein += sample.quantity.doubleValue(for: .gram())
                case HKQuantityType(.dietaryCarbohydrates): n.carbohydrates += sample.quantity.doubleValue(for: .gram())
                case HKQuantityType(.dietaryFatTotal): n.fat += sample.quantity.doubleValue(for: .gram())
                default: break
                }
            }
            let name = correlation.metadata?[HKMetadataKeyFoodType] as? String ?? "Meal"
            return MealRecord(healthKitID: correlation.uuid, nutriLensID: id, payload: payload, name: name, date: correlation.startDate, nutrients: n)
        }
    }

    // MARK: Sleep

    func sleepSamples(from start: Date, to end: Date) async throws -> [SleepSample] {
        guard isAvailable else { return [] }
        // Include nights that started before `start` but ended inside the range.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: Self.sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await query.result(for: store).compactMap { sample in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .inBed: stage = .inBed
            case .awake: stage = .awake
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepREM: stage = .rem
            default: stage = .asleepUnspecified
            }
            return SleepSample(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    func saveSleep(start: Date, end: Date) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let inBed = HKCategorySample(type: Self.sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue, start: start, end: end)
        let asleep = HKCategorySample(type: Self.sleepType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: start, end: end)
        try await store.save([inBed, asleep])
    }

    // MARK: Body

    private static let bodyUnits: [(HKQuantityTypeIdentifier, BodyMetric, HKUnit, Double)] = [
        (.bodyMass, .weight, .gramUnit(with: .kilo), 1),
        (.bodyFatPercentage, .bodyFat, .percent(), 100),
        (.bodyMassIndex, .bmi, .count(), 1),
        (.leanBodyMass, .leanBodyMass, .gramUnit(with: .kilo), 1),
        (.waistCircumference, .waist, .meterUnit(with: .centi), 1),
    ]

    func bodySamples(from start: Date, to end: Date) async throws -> [BodySample] {
        guard isAvailable else { return [] }
        struct Key: Hashable { var time: Int; var source: String }
        var grouped: [Key: BodySample] = [:]
        for (identifier, metric, unit, scale) in Self.bodyUnits {
            let query = HKSampleQueryDescriptor(
                predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: datePredicate(start, end))],
                sortDescriptors: [SortDescriptor(\.startDate)]
            )
            for sample in try await query.result(for: store) {
                let source = sample.sourceRevision.source.bundleIdentifier
                let key = Key(time: Int(sample.startDate.timeIntervalSince1970 / 60), source: source)
                var body = grouped[key] ?? BodySample(id: sample.uuid, date: sample.startDate, values: [:], sourceName: sample.sourceRevision.source.name)
                body.values[metric] = sample.quantity.doubleValue(for: unit) * scale
                let (id, payload) = Self.tag(of: sample)
                if metric == .weight { body.id = sample.uuid }
                body.nutriLensID = body.nutriLensID ?? id
                body.payload = body.payload ?? payload
                grouped[key] = body
            }
        }
        return grouped.values.sorted { $0.date < $1.date }
    }

    func saveBody(_ reading: BodyReading, date: Date, nutriLensID: UUID, payload: String?) async throws -> UUID {
        guard isAvailable else { throw HealthDataError.unavailable }
        var samples: [HKQuantitySample] = []
        var weightID: UUID?
        for (identifier, metric, unit, scale) in Self.bodyUnits {
            guard let value = reading.values[metric] else { continue }
            // The full payload rides on the weight sample; the rest just carry the record ID.
            let tags = metadata(nutriLensID: nutriLensID, payload: metric == .weight ? payload : nil)
            let sample = HKQuantitySample(type: HKQuantityType(identifier), quantity: HKQuantity(unit: unit, doubleValue: value / scale),
                                          start: date, end: date, metadata: tags)
            if metric == .weight { weightID = sample.uuid }
            samples.append(sample)
        }
        guard !samples.isEmpty else { throw HealthDataError.notFound }
        try await store.save(samples)
        return weightID ?? samples[0].uuid
    }

    func healthProfile() async -> HealthProfile {
        guard isAvailable else { return HealthProfile() }
        var profile = HealthProfile()
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .male: profile.sex = .male
            case .female: profile.sex = .female
            default: profile.sex = nil
            }
        }
        if let components = try? store.dateOfBirthComponents() {
            profile.birthDate = Calendar(identifier: .gregorian).date(from: components)
        }
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.height))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        profile.heightCm = (try? await query.result(for: store))?.first?.quantity.doubleValue(for: .meterUnit(with: .centi))
        return profile
    }

    func deleteBody(nutriLensID: UUID) async throws {
        guard isAvailable else { throw HealthDataError.unavailable }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HealthSyncKey.recordID, allowedValues: [nutriLensID.uuidString])
        for (identifier, _, _, _) in Self.bodyUnits {
            _ = try await store.deleteObjects(of: HKQuantityType(identifier), predicate: predicate)
        }
    }
}
