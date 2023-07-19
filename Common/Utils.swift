//
//  Utils.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 14/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import Foundation
import ZIPFoundation

extension String: Error {}

extension Double {
    func formatted(_ format: String) -> String {
        return String(format: "\(format)", self)
    }
}

/// If the zip file was created on Mac OS X ignore the embedded mac resource fork information and hidden files.
func extractZipFile(from: URL, to: URL) {
    Task {
        
        if let archive = Archive(url: from, accessMode: .read) {
            
            for entry in archive {
                let entryURL = to.appendingPathComponent(entry.path)
                
                // Skip hidden files and __MACOSX folder
                let pathComponents = entry.path.components(separatedBy: "/")
                if pathComponents.contains("__MACOSX") || pathComponents.last?.hasPrefix(".") == true {
                    continue
                }
                
                do {
                    try _ = archive.extract(entry, to: entryURL)
                } catch {
                    // Error handling
                    print("Error extracting \(entry.path): \(error.localizedDescription)")
                }
            }
        }
    }
}

extension Array {
    /// Get an element from an Array safely to avoid runtime crashes when accessing an index out of range on an Array.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

/// Returns an array of booleans that indicates at which steps a preview should be generated.
///
/// - Parameters:
///   - numInferenceSteps: The total number of inference steps.
///   - numPreviews: The desired number of previews.
///
/// - Returns: An array of booleans of size `numInferenceSteps`, where `true` values represent steps at which a preview should be made.
func previewIndices(_ numInferenceSteps: Int, _ numPreviews: Int) -> [Bool] {
    // Ensure valid parameters
    guard numInferenceSteps > 0, numPreviews > 0 else {
        return [Bool](repeating: false, count: numInferenceSteps)
    }

    // Compute the ideal (floating-point) step size, which represents the average number of steps between previews
    let idealStep = Double(numInferenceSteps) / Double(numPreviews)

    // Compute the actual steps at which previews should be made. For each preview, we multiply the ideal step size by the preview number, and round to the nearest integer.
    // The result is converted to a `Set` for fast membership tests.
    let previewIndices: Set<Int> = Set((0..<numPreviews).map { previewIndex in
        return Int(round(Double(previewIndex) * idealStep))
    })
    
    // Construct an array of booleans where each value indicates whether or not a preview should be made at that step.
    let previewArray = (0..<numInferenceSteps).map { previewIndices.contains($0) }

    return previewArray
}
