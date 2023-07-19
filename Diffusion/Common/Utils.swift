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
    /// Apply String() formatting to a Double number. For instance %.2f, etc
    /// examples: https://www.waldo.com/blog/swift-string-format
    func formatted(_ format: String) -> String {
        return String(format: "\(format)", self)
    }
}

/// Extracts the first 200 characters from a string and replaces whitespace characters with an underscore.
///
/// Examples usage: safestring = "really long string  with tabs       and spaces".first200
///
/// - Returns: A substring with the first 200 characters of the `String` operated on.
extension String {
    /// Convert a String by extracting the first 200 characters while replacing whitespace characters with underscores.
    var first200Safe: String {
        let endIndex = index(startIndex, offsetBy: Swift.min(200, count))
        let substring = String(self[startIndex..<endIndex])
        
        // Replace whitespace with underscore or dash
        let replacedSubstring = substring
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "\t", with: "_")
            .replacingOccurrences(of: "\n", with: "_")

        // Remove unsafe characters from the substring
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filteredSubstring = replacedSubstring
            .components(separatedBy: allowedCharacters.inverted)
            .joined()

        return filteredSubstring
    }
}

/// Allows the safe access ot an array subscript. If the subscript is missing then nil is returned.
///  access as Array[safe: indexNumber] and returns an optional generic `Element`.
///
/// - Parameters:
///   - safe: The index inside the `Array` you'd like to retrive an `Element` from.
///
/// - Returns: A generic `Element` instance of nil if the `safe` index is invalid.
extension Array {
    /// Get an element from an Array safely to avoid runtime crashes when accessing an index out of range on an Array.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
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
