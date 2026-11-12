import NutriCore
import PhotosUI
import SwiftUI

/// Outcome of saving a meal, shown at the top of the Log tab.
struct SaveResult: Equatable {
    var text: String
    /// True when the meal was kept locally but couldn't be written to Apple Health.
    var isWarning = false
}

enum LogRoute: Hashable {
    case search
    case custom
    case myFoods
    case editor(FoodItem, MealSource)
    /// Build a dish from ingredients, starting from these dishes (the photo's guesses).
    case builder([FoodItem])
}

/// Photo → on-device recognition → pick the dish → confirm the portion → save.
struct LogFoodView: View {
    @Binding var section: FoodSection
    @Environment(AppEnvironment.self) private var env
    @State private var path: [LogRoute] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoThumbnail: Data?
    @State private var candidates: [FoodCandidate] = []
    @State private var isAnalyzing = false
    @State private var analysisMessage: String?
    @State private var showingCamera = false
    @State private var savedMessage: SaveResult?
    @State private var demoPhotoShown = false

    private var cameraAvailable: Bool {
        // Demo mode can show the button in the Simulator (which has no camera) for checking its look.
        UIImagePickerController.isSourceTypeAvailable(.camera) || (env.isDemo && UserDefaults.standard.bool(forKey: "demoCameraButton"))
    }

    /// Below this top-guess confidence the user is told the recogniser isn't sure.
    static let confidentThreshold = 0.3

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let savedMessage {
                    Section {
                        Label(savedMessage.text, systemImage: savedMessage.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(savedMessage.isWarning ? .orange : .green)
                    }
                }
                if let photo {
                    photoSection(photo)
                    resultsSection
                } else {
                    captureSection
                }
                everyDaySection
                manualSection
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { FoodSectionPicker(section: $section) }
            }
            .navigationDestination(for: LogRoute.self) { route in
                switch route {
                case .search:
                    FoodSearchView()
                case .custom:
                    CustomFoodEditor { food in path.append(.editor(food, .custom)) }
                case .myFoods:
                    MyFoodsView()
                case .builder(let starts):
                    DishBuilderView(starts: starts, initial: nil) { food in
                        path.append(.editor(food, photo != nil ? .photo : .custom))
                    }
                case .editor(let food, let source):
                    MealEditorView(
                        food: food,
                        source: source,
                        photoData: source == .photo ? photoThumbnail : nil,
                        onSaved: finishSaving
                    )
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await loadPickedPhoto(item) }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    Task { await analyze(image) }
                }
                .ignoresSafeArea()
            }
            .task {
                if env.isDemo, LaunchArguments.current.demoPhoto, !demoPhotoShown {
                    demoPhotoShown = true
                    await analyze(DemoContent.samplePhoto())
                }
            }
        }
    }

    // MARK: Sections

    private var captureSection: some View {
        Section {
            VStack(spacing: 14) {
                Image(systemName: "fork.knife.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Snap your meal")
                    .font(.title3.bold())
                Text("NutriLens recognises the dish on your iPhone, then you confirm it and the portion.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if cameraAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        // Explicit white: inside a List, iOS tints row icons with the accent colour, which is
                        // the same as this button's fill, so the camera icon disappeared.
                        Label("Take Photo", systemImage: "camera.fill")
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } footer: {
            Text("Recognition: \(env.recognizer.engine.displayName). Photos never leave this device.")
        }
    }

    private func photoSection(_ image: UIImage) -> some View {
        Section {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .listRowInsets(EdgeInsets())
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Another photo", systemImage: "photo")
                }
                Spacer()
                Button("Clear", systemImage: "xmark.circle", role: .destructive, action: reset)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder private var resultsSection: some View {
        Section {
            if isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Recognising food…").foregroundStyle(.secondary)
                }
            } else {
                ForEach(candidates) { candidate in
                    NavigationLink(value: LogRoute.editor(candidate.food, .photo)) {
                        CandidateRow(candidate: candidate, isTop: candidate.id == candidates.first?.id)
                    }
                }
                if let analysisMessage {
                    Text(analysisMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                NavigationLink(value: LogRoute.builder(candidates.map(\.food))) {
                    Label("Describe what's in it", systemImage: "list.bullet.clipboard")
                }
                NavigationLink(value: LogRoute.search) {
                    Label("Not right? Search all foods", systemImage: "magnifyingglass")
                }
            }
        } header: {
            Text(candidates.isEmpty ? "Result" : "Is this…?")
        } footer: {
            if !isAnalyzing {
                Text("Photo guesses can be off. Close but not quite? Describe what's in it.")
            }
        }
    }

    /// Foods you have every day, one tap away (the seeds and nuts mix at lunch and dinner).
    @ViewBuilder private var everyDaySection: some View {
        let daily = Self.everyDayFoodIDs.compactMap { env.database.food(id: $0) }
        if !daily.isEmpty {
            Section("Every day") {
                ForEach(daily) { food in
                    NavigationLink(value: LogRoute.editor(food, .search)) { FoodRow(food: food) }
                }
            }
        }
    }

    /// Your coffee (three cups a day, milk set each time) and the seeds and nuts mix.
    static let everyDayFoodIDs = ["coffee_buffalo_milk", "seed_nut_mix"]

    private var manualSection: some View {
        Section("Manual entry") {
            NavigationLink(value: LogRoute.search) {
                Label("Search food list", systemImage: "list.bullet.rectangle")
            }
            NavigationLink(value: LogRoute.builder([])) {
                Label("New dish: say what's in it", systemImage: "mic")
            }
            NavigationLink(value: LogRoute.myFoods) {
                Label("My foods", systemImage: "person.crop.square")
            }
            NavigationLink(value: LogRoute.custom) {
                Label("Add a food of your own", systemImage: "square.and.pencil")
            }
        }
    }

    // MARK: Actions

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                analysisMessage = "That photo couldn't be opened."
                return
            }
            await analyze(image)
        } catch {
            analysisMessage = "That photo couldn't be opened: \(error.localizedDescription)"
        }
    }

    private func analyze(_ image: UIImage) async {
        savedMessage = nil
        let normalized = ImageProcessing.normalized(image)
        photo = normalized
        photoThumbnail = ImageProcessing.thumbnailJPEG(normalized)
        candidates = []
        analysisMessage = nil
        isAnalyzing = true
        defer { isAnalyzing = false }
        guard let cgImage = normalized.cgImage else {
            analysisMessage = "That image couldn't be read. Search for the food instead."
            return
        }
        do {
            candidates = try await env.recognizer.recognize(cgImage)
            if candidates.isEmpty {
                analysisMessage = "No food from the list was recognised. Search for it or add a custom food."
            } else if let best = candidates.first, best.confidence < Self.confidentThreshold {
                analysisMessage = "Not sure about this one. If none of these is right, search for the food."
            }
        } catch {
            analysisMessage = "Recognition isn't available (\(error.localizedDescription)). Search for the food instead."
        }
    }

    private func reset() {
        photo = nil
        photoThumbnail = nil
        candidates = []
        analysisMessage = nil
    }

    private func finishSaving(_ result: SaveResult) {
        reset()
        path = []
        savedMessage = result
    }
}

private struct CandidateRow: View {
    let candidate: FoodCandidate
    let isTop: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.food.name).font(isTop ? .headline : .body)
                let shown = RecipePreferences.asUsual(candidate.food)
                Text("\(Format.kcal(shown.perServing.kilocalories)) kcal · \(Format.grams(shown.perServing.protein)) protein · \(shown.servingLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(candidate.confidence.formatted(.percent.precision(.fractionLength(0))))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isTop ? Color.accentColor : .secondary)
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    LogFoodView(section: .constant(.log))
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
