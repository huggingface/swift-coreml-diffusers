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
