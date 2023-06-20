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
