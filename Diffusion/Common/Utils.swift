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

extension Array {
    /// Get an element from an Array safely to avoid runtime crashes when accessing an index out of range on an Array.
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
