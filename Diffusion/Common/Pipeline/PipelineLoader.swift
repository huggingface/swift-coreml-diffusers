//
//  PipelineLoader.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//


import CoreML
import Combine

import ZIPFoundation
import StableDiffusion

class PipelineLoader {
    static let models = URL.applicationSupportDirectory.appendingPathComponent("hf-diffusion-models")
    let model: ModelInfo
    let computeUnits: ComputeUnits
    let maxSeed: UInt32
    
    private var downloadSubscriber: Cancellable?

    init(model: ModelInfo, computeUnits: ComputeUnits? = nil, maxSeed: UInt32 = UInt32.max) {
        self.model = model
        self.computeUnits = computeUnits ?? model.defaultComputeUnits
        self.maxSeed = maxSeed
        state = .undetermined
        setInitialState()
    }
        
    enum PipelinePreparationPhase {
        case undetermined
        case waitingToDownload
        case downloading(Double)
        case downloaded
        case uncompressing
        case readyOnDisk
        case loaded
        case failed(Error)
    }
    
    var state: PipelinePreparationPhase {
        didSet {
            statePublisher.value = state
        }
    }
    private(set) lazy var statePublisher: CurrentValueSubject<PipelinePreparationPhase, Never> = CurrentValueSubject(state)
    private(set) var downloader: Downloader? = nil

    func setInitialState() {
        if ready {
            state = .readyOnDisk
            return
        }
        if downloaded {
            state = .downloaded
            return
        }
        state = .waitingToDownload
    }
}

extension PipelineLoader {
    // Note: this function is currently unused. Marked for deletion. -- dolmere
    static func removeAll() {
        let enumerator = FileManager.default.enumerator(at: models, includingPropertiesForKeys: nil)

        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                print("Failed to delete: \(fileURL), error: \(error.localizedDescription)")
            }
        }
    }
}


extension PipelineLoader {
    func cancel() { downloader?.cancel() }
}

extension PipelineLoader {
    var url: URL {
        return model.modelURL(for: variant)
    }
    
    var filename: String {
        return url.lastPathComponent
    }
    
    var downloadedURL: URL { PipelineLoader.models.appendingPathComponent(filename) }

    var uncompressURL: URL { PipelineLoader.models.deletingLastPathComponent() }
    
    var packagesFilename: String { PipelineLoader.models.appendingPathComponent((filename as NSString).deletingPathExtension).path }
    
    var compiledURL: URL { downloadedURL.deletingLastPathComponent().appendingPathComponent(packagesFilename)  }

    var downloaded: Bool {
        return FileManager.default.fileExists(atPath: downloadedURL.path)
    }
    
    var ready: Bool {
        return FileManager.default.fileExists(atPath: compiledURL.path)
    }
    
    var variant: AttentionVariant {
        switch computeUnits {
        case .cpuOnly           : return .original          // Not supported yet
        case .cpuAndGPU         : return .original
        case .cpuAndNeuralEngine: return model.supportsAttentionV2 ? .splitEinsumV2 : .splitEinsum
        case .all               : return .splitEinsum
        @unknown default:
            fatalError("Unknown MLComputeUnits")
        }
    }
    
    // TODO: maybe receive Progress to add another progress as child
    func prepare() async throws -> Pipeline {
        do {
            // Make default models folder if missing
            let fileExists = FileManager.default.fileExists(atPath: PipelineLoader.models.path)
            if !fileExists {
                do {
                    try FileManager.default.createDirectory(atPath: PipelineLoader.models.path, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print("Error creating PipelineLoader.models path: \(error)")
                }
            }

            try await download()
            try await unzip()
            let pipeline = try await load(url: compiledURL)
            return Pipeline(pipeline, maxSeed: maxSeed)
        } catch {
            state = .failed(error)
            throw error
        }
    }
    
    @discardableResult
    func download() async throws -> URL {
        if ready || downloaded { return downloadedURL }
        
        let downloader = Downloader(from: url, to: downloadedURL)
        self.downloader = downloader
        downloadSubscriber = downloader.downloadState.sink { state in
            if case .downloading(let progress) = state {
                self.state = .downloading(progress)
            }
        }
        try downloader.waitUntilDone()
        return downloadedURL
    }
    
    func unzip() async throws {
        guard downloaded else { return }
        state = .uncompressing
        do {
            try FileManager().unzipItem(at: downloadedURL, to: uncompressURL)
        } catch {
            // Cleanup if error occurs while unzipping
            try FileManager.default.removeItem(at: uncompressURL)
            throw error
        }
        try FileManager.default.removeItem(at: downloadedURL)
        state = .readyOnDisk
    }
    
    func load(url: URL) async throws -> StableDiffusionPipeline {
        let beginDate = Date()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let pipeline = try StableDiffusionPipeline(resourcesAt: url,
                                                   controlNet: [],
                                                   configuration: configuration,
                                                   disableSafety: false,
                                                   reduceMemory: model.reduceMemory)
        try pipeline.loadResources()
        print("Pipeline loaded in \(Date().timeIntervalSince(beginDate))")
        state = .loaded
        return pipeline
    }
}
