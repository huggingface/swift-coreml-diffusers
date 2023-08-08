//
//  ModelsViewModel.swift
//  Diffusion
//
//  Created by Dolmere on 15/06/2023.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//
// Allows for the selection of the folder on the file system where the user will download and store their .mlmodlc folders
// The selected folder will be tracked for changes allowing for the dynamic updates of installed models in the UI

import Foundation
import Combine
import ZIPFoundation

class ModelsViewModel: ObservableObject {
    private var settings: Settings

    @Published var modelsFolderURL: URL {
        didSet {
            loadModels()
            // save the new models folder into userdefaults and save userdefaults
            Settings.shared.defaults.set(modelsFolderURL.absoluteString, forKey: Settings.Keys.modelsFolderURL.rawValue)
            Settings.shared.defaults.synchronize()
        }
    }

    // Unkown models discovered in the models folder when loadModels() runs.
    @Published var addonModels: [ModelInfo] = [] {
        didSet {
            updateFilters()
        }
    }

    // Track readiness state of models as they're encountered. Preferred access is through getter and setter `getModelReadiness` and `setModelReadiness`
    @Published var modelReadinessWrappers: [ModelReadiness] = []

    // Known models defined as built-in. Downloadable by the app.
    @Published var builtinModels: [ModelInfo] = ModelInfo.BUILTIN_MODELS

    // Models that are added by the user and match the currently selected variant
    @Published var filteredAddonModels: [ModelInfo] = []

    // Models that are built-in and match the currently selected variant
    @Published var filteredBuiltinModels: [ModelInfo] = []

    @Published var filteredModels: [ModelInfo] = []

    private var folderMonitor: DispatchSourceFileSystemObject?

    init(settings: Settings) {
        self.settings = settings
        var possibleURL: URL?
        var unwrappedURL: URL
        if let customString = settings.defaults.string(forKey: Settings.Keys.modelsFolderURL.rawValue) {
            possibleURL = URL(string: customString)
        } else {
            possibleURL = DEFAULT_MODELS_FOLDER
        }
        if let possibleReal = possibleURL {
            unwrappedURL = possibleReal
        } else {
            unwrappedURL = DEFAULT_MODELS_FOLDER
        }
        modelsFolderURL = unwrappedURL

        // Make default models folder if missing
        let fileExists = FileManager.default.fileExists(atPath: DEFAULT_MODELS_FOLDER.path)
        if !fileExists {
            do {
                try FileManager.default.createDirectory(atPath: DEFAULT_MODELS_FOLDER.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Error creating DEFAULT_MODELS_FOLDER: \(error)")
                return
            }
        }

        startMonitoring()
        // Load all models present in the models folder
        loadModels()
    }

    func getModelReadiness(_ model: ModelInfo) -> ModelReadiness {
        var mrw: ModelReadinessState = ModelReadinessState.unknown
        if let modelAlreadyTracked = modelReadinessWrappers.first(where: { $0.modelInfo.fileSystemFileName == model.fileSystemFileName }) {
            // If a matching readiness item is found in memory return it
            return modelAlreadyTracked
        } else {
            //model not tracked and in an unknown state so
            let fileExists = modelReady(model: model)
            if fileExists {
                mrw = .ready
            }
        }
        // Now create, insert and return unknown or ready state readiness
        let newModelReadiness = ModelReadiness(modelInfo: model, state: mrw)
        setModelReadiness(of: model, to: mrw)
        return newModelReadiness
    }

    /// Use setReadiness to ensure that UI affecting changes happen on the main thread!
    func setModelReadiness(of model: ModelInfo, to state: ModelReadinessState) {
        DispatchQueue.main.async {
            if let matchingReadinessItem = self.modelReadinessWrappers.first(where: { $0.modelInfo.fileSystemFileName == model.fileSystemFileName }) {
                // If a matching readiness item is found in memory, update its status
                matchingReadinessItem.state = state
            } else {
                // Create a new model readiness item and insert it
                let newModelReadiness = ModelReadiness(modelInfo: model, state: state)
                self.modelReadinessWrappers.append(newModelReadiness)
            }
        }
    }


    /// When the variant changes try to select the model with that variant or sets the model to `nil`
    // TODO: This is probably best moved to State.swift/Settings -- dolmere
    func setSelectedModelFor(variant: AttentionVariant) {
        if (Settings.shared.currentModel.variant == variant) {
            //no work to do here, the correct model is already selected
            return
        }
        if let model = self.modelFrom(humanReadableFileName: Settings.shared.currentModel.humanReadableFileName, variant: variant) {
            Settings.shared.currentModel = model
        }
    }

    public func startMonitoring() {
        let fileDescriptor = open(modelsFolderURL.path, O_EVTONLY)
        folderMonitor = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .all, queue: .main)

        folderMonitor?.setEventHandler { [self] in
            self.folderContentsDidChange()
        }

        folderMonitor?.resume()
    }

    public func stopMonitoring() {
        folderMonitor?.cancel()
    }

    private func folderContentsDidChange() {
//        print("folderContentsDidChange! reloading models.")
        loadModels()
    }

    /// return a modelinfo representation of a known model on disk given its decomposed human readable file name
    public func modelFrom(humanReadableFileName: String, variant: AttentionVariant) -> ModelInfo? {
        if let addonFound = addonModels.first(where: { $0.humanReadableFileName == humanReadableFileName && $0.variant == variant }) {
            return addonFound
        }
        return builtinModels.first(where: { $0.humanReadableFileName == humanReadableFileName && $0.variant == variant })
    }

    func loadModels() {
        let modelInfoArray = reloadAddonModelInfo(builtinModels: self.builtinModels)

        DispatchQueue.main.async {
            self.addonModels = modelInfoArray
        }
        // Now update the filtered array of models
        updateFilters()
    }

    public func updateFilters() {
        DispatchQueue.main.async {
            let newAddonFiltered = self.addonModels.filter { $0.variant == convertUnitsToVariant(computeUnits: Settings.shared.userSelectedComputeUnits) }
            self.filteredAddonModels = newAddonFiltered
            let newBuiltinFiltered = self.builtinModels.filter { $0.variant == convertUnitsToVariant(computeUnits: Settings.shared.userSelectedComputeUnits) }
            self.filteredBuiltinModels = newBuiltinFiltered
            self.filteredModels = self.filteredBuiltinModels + self.filteredAddonModels
        }
    }

    // Utility function used to help convert filesystem model name to human readable string
    func replaceUnderscoresAndDashes(string: String) -> String {
        let pattern = "[-_]"
        let replaced = string.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        return replaced
    }

    // Utility function used to help convert filesystem model name to human readable string
    func replaceVariantInfo(string: String) -> String {
        let pattern = "(compiled)|(original)|(split)|(einsum)"
        let replaced = string.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return replaced
    }

    // Utility function used to help convert filesystem model name to human readable string
    func removeVersion(from: String) -> String {
        let pattern = "(v).*"
        let replaced = from.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return replaced
    }

    // Utility function used to help convert filesystem model name to human readable string
    func getVersion(from string: String) -> String? {
        let pattern = "(v).*"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        guard let match = regex.firstMatch(in: string, options: [], range: NSRange(location: 0, length: string.count)) else {
            return nil
        }

        let matchedRange = match.range(at: 0)
        let matchedSubstring = (string as NSString).substring(with: matchedRange)

        return matchedSubstring
    }

    // Utility function used to help convert filesystem model name to human readable string
    func detectAttentionVariant(from filename: String) -> AttentionVariant {
        if filename.contains("original") {
            return .original
        } else if filename.contains("palettized") {
            return .splitEinsumV2
        } else if filename.contains("einsum") {
            return .splitEinsum
        } else {
            // Default to original if "original", "einsum" or "einsumV2" were not found in the model's filename
            return .original
        }
    }

/*
 // Better API for getting vocab and merges files. Best to put directly into ModelInfo? Or in modelViewModel?
    var vocabFileInBundleURL: URL {
        let fileName = "vocab"
        guard let url = Bundle.module.url(forResource: fileName, withExtension: "json") else {
            fatalError("BPE tokenizer vocabulary file is missing from bundle")
        }
        return url
    }
    var mergesFileInBundleURL: URL {
        let fileName = "merges"
        guard let url = Bundle.module.url(forResource: fileName, withExtension: "txt") else {
            fatalError("BPE tokenizer merges file is missing from bundle")
        }
        return url
    }
*/

    // Read through the selected models directory and load any directories that look like valid models
    func reloadAddonModelInfo(builtinModels: [ModelInfo]) -> [ModelInfo] {
        do {
            var modelInfoArray: [ModelInfo] = []
            let folderContents = try FileManager.default.contentsOfDirectory(at: self.modelsFolderURL, includingPropertiesForKeys: nil, options: []) // DirectoryEnumerationOptions.skipsHiddenFiles? -- dolmere
            let visibleFiles = folderContents.filter { fileURL in
                let fileName = fileURL.lastPathComponent
                // TODO: Filter out any items which are not folders and that do not contain the paths filename/merges.txt and filename/vocab.json -- dolmere
                return !fileName.hasPrefix(".")
            }
            let filenames = visibleFiles.map { $0.lastPathComponent }
            for compareFileName in filenames {
                var calculatedFileName: String = ""
                var version: String = ""
                var variant: AttentionVariant = .original
                if let _ = builtinModels.first(where: { $0.fileSystemFileName == compareFileName }) {
                    // ignore builtin models as they have already been processed above
                } else if let _ = builtinModels.first(where: { $0.fileSystemFileName + "_original_compiled" == compareFileName }) {
                    // ignore builtin models as they have already been processed above
                } else if let _ = builtinModels.first(where: { $0.fileSystemFileName + "_split_einsum_v2_compiled" == compareFileName }) {
                    // ignore builtin models as they have already been processed above
                } else if let _ = builtinModels.first(where: { $0.fileSystemFileName + "_split_einsum_compiled" == compareFileName }) {
                    // ignore builtin models as they have already been processed above
                } else {
                    // The file found in the models folder is not a built in model! Load it up...
                    calculatedFileName = replaceUnderscoresAndDashes(string: compareFileName)
                    variant = detectAttentionVariant(from: compareFileName)
                    calculatedFileName = replaceVariantInfo(string: calculatedFileName)
                    version = getVersion(from: calculatedFileName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "v0.0"
                    // take out the version and remove any whitespace characters from the front and back of the string
                    let humanReadableFileName = removeVersion(from: calculatedFileName).trimmingCharacters(in: .whitespacesAndNewlines)
                    let modelInfo = ModelInfo(modelId: UUID().uuidString,
                                              modelVersion: version, variant: variant,
                                              builtin: false,
                                              humanReadableFileName: humanReadableFileName,
                                              fileSystemFileName: compareFileName)
                    modelInfoArray.append(modelInfo)
                }
            }
            return modelInfoArray
        } catch {
            print("Error initializing ModelsFolderObservableModel: \(error.localizedDescription)")
        }
        //TODO: better error handling! -- dolmere
        return []
    }

    private func modelReady(model: ModelInfo) -> Bool {
        var ready = false
        let appendPath = model.fileSystemFileName
        /// check that this model's fodler exists in the models folders
        let fileExists = FileManager.default.fileExists(atPath: modelsFolderURL.appendingPathComponent(appendPath).path)
        if fileExists {
            /// check that the models folder is indeed a folder and contains a merges.txt key file
            let mergesExists = FileManager.default.fileExists(atPath: modelsFolderURL.appendingPathComponent(appendPath).appendingPathComponent("merges.txt").path)
            if mergesExists {
                /// check that the models folder is indeed a folder and contains a vocab.txt key file
                let vocabExists = FileManager.default.fileExists(atPath: modelsFolderURL.appendingPathComponent(appendPath).appendingPathComponent("vocab.json").path)
                if vocabExists {
                    ready = true
                }
            }
        }
        return ready
    }

}
