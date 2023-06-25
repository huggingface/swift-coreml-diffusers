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

extension String {
    var first200Safe: String {
        let endIndex = index(startIndex, offsetBy: Swift.min(200, count))
        let substring = String(self[startIndex..<endIndex])
        
        // Remove unsafe characters from the substring
        let safeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filteredSubstring = substring.components(separatedBy: safeCharacters.inverted).joined()
        
        return filteredSubstring
    }
}
