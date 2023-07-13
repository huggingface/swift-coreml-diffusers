//
//  Utils.swift
//  Diffusion
//
//  Created by Pedro Cuenca on 14/1/23.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import Foundation

extension String: Error {}

extension Double {
    func formatted(_ format: String) -> String {
        return String(format: "\(format)", self)
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
        return [Bool](repeating: false, count: numInferenceSteps) // If parameters are not valid, return an array with only `false` values
    }

    // Compute the ideal (floating-point) step size, which represents the average number of steps between previews
    let idealStep = Double(numInferenceSteps) / Double(numPreviews)

    // Compute the actual steps at which previews should be made. For each preview, we multiply the ideal step size by the preview number, and round to the nearest integer.
    // The result is converted to a `Set` for fast membership tests.
    let previewIndices: Set<Int> = Set((0..<numPreviews).map { previewIndex in
        return Int(round(Double(previewIndex) * idealStep))
    })
    
    // Construct an array of booleans where each value indicates whether or not a preview should be made at that step.
    // For each step in the total number of steps, we check if it is in our set of preview indices, resulting in `true` or `false`.
    var previewArray = [Bool]()

    // For each step in the total number of steps
    for step in 0..<numInferenceSteps {
        // Check if the current step is in our set of preview indices
        // If it is, append `true` to our array, otherwise append `false`
        if previewIndices.contains(step) {
            previewArray.append(true)
        } else {
            previewArray.append(false)
        }
    }
    
    return previewArray
}
