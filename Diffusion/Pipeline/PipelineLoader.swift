//
//  PipelineLoader.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//


import CoreML
import Combine

import Path
import ZIPFoundation
import StableDiffusion

class PipelineLoader {
    static let models = Path.applicationSupport / "hf-diffusion-models"
    
    let model: ModelInfo
    let maxSeed: UInt32
    
    private var downloadSubscriber: Cancellable?

    init(model: ModelInfo, maxSeed: UInt32 = UInt32.max) {
        self.model = model
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
    static func removeAll() {
        try? models.delete()
    }
}

extension PipelineLoader {
    func cancel() { downloader?.cancel() }
}

extension PipelineLoader {
    var url: URL {
        return model.bestURL
    }
    
    var filename: String {
        return url.lastPathComponent
    }
    
    var downloadedPath: Path { PipelineLoader.models / filename }
    var downloadedURL: URL { downloadedPath.url }

    var uncompressPath: Path { downloadedPath.parent }
    
    var packagesFilename: String { downloadedPath.basename(dropExtension: true) }
    var compiledPath: Path { downloadedPath.parent/packagesFilename }

    var downloaded: Bool {
        return downloadedPath.exists
    }
    
    var ready: Bool {
        return compiledPath.exists
    }
        
    // TODO: maybe receive Progress to add another progress as child
    func prepare() async throws -> Pipeline {
        do {
            try PipelineLoader.models.mkdir(.p)
            try await download()
            try await unzip()
            let pipeline = try await load(url: compiledPath.url)
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
            try FileManager().unzipItem(at: downloadedURL, to: uncompressPath.url)
        } catch {
            // Cleanup if error occurs while unzipping
            try uncompressPath.delete()
            throw error
        }
        try downloadedPath.delete()
        state = .readyOnDisk
    }
    
    func load(url: URL) async throws -> StableDiffusionPipeline {
        let beginDate = Date()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = model.bestComputeUnits
        let pipeline = try StableDiffusionPipeline(resourcesAt: url,
                                                   configuration: configuration,
                                                   disableSafety: false,
                                                   reduceMemory: model.reduceMemory)
        print("Pipeline loaded in \(Date().timeIntervalSince(beginDate))")
        state = .loaded
        return pipeline
    }
}
