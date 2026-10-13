import SwiftUI
import Charts
import PhotosUI

/// Weight's companions: tape measurements and progress photos.
struct BodySection: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Section {
            NavigationLink { MeasurementsView() } label: {
                HStack {
                    Label("Measurements", systemImage: "ruler")
                    Spacer()
                    if let waist = BodyMeasurements.change(BodyMeasurements.readings(store.data.measurementLog, site: BodySite.waist.rawValue)) {
                        Text("Waist \(waist.latest.cm.number) cm").font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            NavigationLink { ProgressPhotosView() } label: { Label("Progress photos", systemImage: "camera") }
        } header: { Text("Body") } footer: {
            Text("Measurements sync with iCloud like the rest of your data. Progress photos stay on this iPhone.")
        }
    }
}

// MARK: Measurements

struct MeasurementsView: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false

    private var entries: [BodyMeasurement] { store.data.measurementLog }

    var body: some View {
        LeanrList {
            let sites = BodyMeasurements.sites(in: entries)
            if entries.isEmpty {
                Section {
                    ContentUnavailableView("No measurements yet", systemImage: "ruler",
                                           description: Text("Waist, hips, chest and more. Scales miss what a tape measure shows, so these are worth taking monthly."))
                }
            } else {
                Section {
                    ForEach(sites, id: \.self) { site in
                        if let change = BodyMeasurements.change(BodyMeasurements.readings(entries, site: site)) {
                            NavigationLink { MeasurementChart(site: site) } label: { row(site, change) }
                        }
                    }
                } header: { Text("Latest") } footer: {
                    Text("Changes compare the latest reading with the one before it, and with your first.")
                }
            }
            Section {
                Button { adding = true } label: { Label("Add measurements", systemImage: "plus.circle.fill") }
            } footer: {
                Text("Measure at the same spot each time, relaxed, in the morning if you can. Skip any site you don't want to track.")
            }
            if !entries.isEmpty {
                Section("History") {
                    ForEach(entries.sorted { $0.date > $1.date }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.roboto(.headline))
                            Text(summary(entry)).font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                store.change(undo: "Deleted measurements") { $0.measurements?.removeAll { $0.id == entry.id } }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Measurements")
        .sheet(isPresented: $adding) { NavigationStack { MeasurementEntrySheet() } }
    }

    private func row(_ site: String, _ change: BodyMeasurements.Change) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(BodyMeasurements.title(site)).font(.roboto(.headline))
                if let first = change.first, let since = change.sinceFirst {
                    Text("\(BodyMeasurements.signed(since)) since \(first.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                } else {
                    Text("First reading \(change.latest.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(change.latest.cm.number) cm").font(.roboto(.headline)).monospacedDigit()
                if let last = change.sinceLast {
                    Text("\(BodyMeasurements.signed(last)) last time").font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func summary(_ entry: BodyMeasurement) -> String {
        let known = BodyMeasurements.sites(in: [entry])
        return known.compactMap { site in entry.values[site].map { "\(BodyMeasurements.title(site)) \($0.number)" } }.joined(separator: " · ") + " cm"
    }
}

/// Measurements for one day, any sites you like.
private struct MeasurementEntrySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var values: [String: Double] = [:]

    private var cleaned: [String: Double] { values.filter { (5...300).contains($0.value) }.mapValues(\.tenth) }

    var body: some View {
        LeanrForm {
            Section { DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date) }
            Section {
                ForEach(BodySite.allCases) { site in
                    let last = BodyMeasurements.change(BodyMeasurements.readings(store.data.measurementLog, site: site.rawValue))?.latest.cm
                    VStack(alignment: .leading, spacing: 2) {
                        OptionalNumberField(title: "\(site.title) (cm)", value: Binding(get: { values[site.rawValue] }, set: { values[site.rawValue] = $0 }))
                        if let last { Text("Last time \(last.number) cm").font(.roboto(.caption)).foregroundStyle(.secondary) }
                    }
                }
            } footer: { Text("Leave a site blank to skip it. Each reading must be between 5 and 300 cm.") }
        }
        .navigationTitle("Add measurements").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let entry = BodyMeasurement(date: date, values: cleaned)
                    if store.change(undo: "Saved measurements", { $0.measurements = $0.measurementLog + [entry] }) { dismiss() }
                }.disabled(cleaned.isEmpty)
            }
        }
    }
}

private struct MeasurementChart: View {
    @Environment(AppStore.self) private var store
    let site: String
    private var readings: [BodyMeasurements.Reading] { BodyMeasurements.readings(store.data.measurementLog, site: site) }

    var body: some View {
        LeanrList {
            Section {
                if readings.count >= 2 {
                    Chart(readings, id: \.date) { reading in
                        LineMark(x: .value("Day", reading.date), y: .value("cm", reading.cm)).foregroundStyle(.tint).interpolationMethod(.monotone)
                        PointMark(x: .value("Day", reading.date), y: .value("cm", reading.cm)).foregroundStyle(.tint)
                    }
                    .chartYScale(domain: domain).frame(height: 200)
                    .accessibilityLabel("\(BodyMeasurements.title(site)) chart")
                } else {
                    Text("Take a second measurement to see how it changes.").foregroundStyle(.secondary)
                }
            }
            Section("Readings") {
                ForEach(readings.reversed(), id: \.date) { reading in
                    LabeledContent(reading.date.formatted(date: .abbreviated, time: .omitted), value: "\(reading.cm.number) cm")
                }
            }
        }
        .navigationTitle(BodyMeasurements.title(site))
    }

    private var domain: ClosedRange<Double> {
        let values = readings.map(\.cm)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        return (low - 2).rounded(.down)...(high + 2).rounded(.up)
    }
}

// MARK: Progress photos

/// The photo files, observed. Works on this device only.
@MainActor @Observable
final class ProgressPhotoLibrary {
    private let files: ProgressPhotoFiles
    private(set) var photos: [ProgressPhoto]
    var problem: String?
    @ObservationIgnored private let cache = NSCache<NSUUID, UIImage>()

    init(files: ProgressPhotoFiles = .standard) {
        self.files = files
        photos = files.load()
    }

    /// Saves a picture from the camera or Photos, shrunk to a sensible size.
    @discardableResult func add(_ data: Data, date: Date = Date()) -> Bool {
        guard let jpeg = ProgressPhotoFiles.prepared(data) else { problem = "That photo couldn't be read."; return false }
        do { try files.add(jpeg: jpeg, date: date) } catch { problem = "Couldn't save the photo. Check your iPhone's storage."; return false }
        photos = files.load()
        return true
    }

    func update(_ photo: ProgressPhoto) {
        do { try files.update(photo) } catch { problem = "Couldn't save the change." }
        photos = files.load()
    }

    func remove(_ photo: ProgressPhoto) {
        do { try files.remove(photo.id) } catch { problem = "Couldn't delete the photo." }
        cache.removeObject(forKey: photo.id as NSUUID)
        photos = files.load()
    }

    func thumbnail(_ photo: ProgressPhoto) -> UIImage? {
        if let cached = cache.object(forKey: photo.id as NSUUID) { return cached }
        guard let image = files.thumbnail(photo.id).map({ UIImage(cgImage: $0) }) else { return nil }
        cache.setObject(image, forKey: photo.id as NSUUID)
        return image
    }

    func image(_ photo: ProgressPhoto) -> UIImage? { files.data(photo.id).flatMap(UIImage.init(data:)) }
}

struct ProgressPhotosView: View {
    @State private var library = ProgressPhotoLibrary()
    @State private var pickerItem: PhotosPickerItem?
    @State private var camera = false
    @State private var viewing: ProgressPhoto?
    @State private var comparing = false
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        LeanrList {
            if library.photos.isEmpty {
                Section {
                    ContentUnavailableView("No photos yet", systemImage: "camera",
                                           description: Text("Take one in the same spot and light every few weeks. Photos can show change the scale doesn't."))
                }
            } else {
                Section {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(library.photos) { photo in
                            Button { viewing = photo } label: {
                                VStack(spacing: 4) {
                                    Group {
                                        if let image = library.thumbnail(photo) {
                                            Image(uiImage: image).resizable().scaledToFill()
                                        } else { Color.secondary.opacity(0.2) }
                                    }
                                    .frame(minHeight: 120).frame(maxWidth: .infinity).aspectRatio(0.75, contentMode: .fit).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Text(photo.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.roboto(.caption)).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Progress photo, \(photo.date.formatted(date: .long, time: .omitted))")
                        }
                    }.padding(.vertical, 4)
                }
                if library.photos.count >= 2 {
                    Section { Button { comparing = true } label: { Label("Compare two photos", systemImage: "rectangle.split.2x1") } }
                }
            }
            Section {
                Label("Stay on this iPhone", systemImage: "lock.fill").foregroundStyle(.secondary)
            } footer: {
                Text("Leanr doesn't upload these. They aren't part of iCloud sync, backups or exports, and \"Delete all my data\" removes them. Your iPhone's own backup may include them, like any app's files.")
            }
        }
        .navigationTitle("Progress photos")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { camera = true } label: { Image(systemName: "camera") }.accessibilityLabel("Take a photo")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) { Image(systemName: "photo.on.rectangle") }
                    .accessibilityLabel("Choose from Photos")
            }
        }
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { library.add(data) }
                else { library.problem = "That photo couldn't be opened." }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $camera) {
            ProgressCameraPicker { taken in
                camera = false
                if let data = taken?.jpegData(compressionQuality: 0.9) { library.add(data) }
            }.ignoresSafeArea()
        }
        .sheet(item: $viewing) { photo in NavigationStack { ProgressPhotoDetail(library: library, photo: photo) } }
        .sheet(isPresented: $comparing) { NavigationStack { ProgressPhotoCompare(library: library) } }
        .alert("Progress photos", isPresented: Binding(get: { library.problem != nil }, set: { if !$0 { library.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(library.problem ?? "") }
    }
}

private struct ProgressPhotoDetail: View {
    @Environment(\.dismiss) private var dismiss
    let library: ProgressPhotoLibrary
    @State private var photo: ProgressPhoto
    @State private var note: String
    @State private var confirming = false
    private let original: ProgressPhoto

    init(library: ProgressPhotoLibrary, photo: ProgressPhoto) {
        self.library = library; original = photo
        _photo = State(initialValue: photo); _note = State(initialValue: photo.note ?? "")
    }

    private var changed: Bool { photo.date != original.date || note != (original.note ?? "") }

    var body: some View {
        LeanrList {
            Section {
                if let image = library.image(original) {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Progress photo")
                }
            }
            Section {
                DatePicker("Taken", selection: $photo.date, in: ...Date(), displayedComponents: .date)
                TextField("Note", text: $note, axis: .vertical)
            }
            Section {
                Button(role: .destructive) { confirming = true } label: { Label("Delete photo", systemImage: "trash").frame(maxWidth: .infinity) }
            }
        }
        .navigationTitle(photo.date.formatted(date: .abbreviated, time: .omitted)).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(changed ? "Cancel" : "Close") { dismiss() } }
            if changed {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = photo
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved.note = trimmed.isEmpty ? nil : trimmed
                        library.update(saved); dismiss()
                    }
                }
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) { library.remove(original); dismiss() }
        } message: { Text("It can't be recovered.") }
    }
}

/// Two photos side by side, each with your trend weight at the time.
private struct ProgressPhotoCompare: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let library: ProgressPhotoLibrary
    @State private var beforeID: UUID?
    @State private var afterID: UUID?

    private var points: [WeightTrend.Point] { WeightTrend.points(store.data.weightLog) }
    private func photo(_ id: UUID?) -> ProgressPhoto? { library.photos.first { $0.id == id } }

    var body: some View {
        LeanrList {
            Section {
                Picker("Before", selection: $beforeID) { ForEach(library.photos) { Text(label($0)).tag(Optional($0.id)) } }
                Picker("After", selection: $afterID) { ForEach(library.photos) { Text(label($0)).tag(Optional($0.id)) } }
            }
            Section {
                HStack(alignment: .top, spacing: 10) {
                    side("Before", photo(beforeID))
                    side("After", photo(afterID))
                }
            }
        }
        .navigationTitle("Compare").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            if beforeID == nil { beforeID = library.photos.last?.id }
            if afterID == nil { afterID = library.photos.first?.id }
        }
    }

    private func label(_ photo: ProgressPhoto) -> String { photo.date.formatted(.dateTime.day().month(.abbreviated).year()) }

    private func side(_ title: String, _ photo: ProgressPhoto?) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.roboto(.caption, weight: .bold)).foregroundStyle(.secondary)
            if let photo, let image = library.image(photo) {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 10))
                Text(label(photo)).font(.roboto(.caption))
                if let weight = points.last(where: { $0.date <= photo.date.addingTimeInterval(86_399) }) {
                    Text("\(weight.trend.number) kg").font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Color.secondary.opacity(0.2).aspectRatio(0.75, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }.frame(maxWidth: .infinity)
    }
}

/// The system camera, for one photo.
private struct ProgressCameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
