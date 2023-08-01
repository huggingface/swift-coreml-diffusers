//
//  Utils_iOS.swift
//  Diffusion
//
//  Created by Dolmere on 31/07/2023.
//

import SwiftUI

extension CGImage {
    static func fromData(_ imageData: Data) -> CGImage? {
        if let image = UIImage(data: imageData)?.cgImage {
            return image
        }
        return nil
    }
}
