//
//  Utils_macOS.swift
//  Diffusion-macOS
//
//  Created by Dolmere on 31/07/2023.
//

import SwiftUI

extension CGImage {
    static func fromData(_ imageData: Data) -> CGImage? {
        if let image = NSBitmapImageRep(data: imageData)?.cgImage {
            return image
        }
        return nil
    }
}
