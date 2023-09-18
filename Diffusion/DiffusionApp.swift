//
//  DiffusionApp.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI

@main
struct DiffusionApp: App {
    var body: some Scene {
        WindowGroup {
            LoadingView()
        }
    }
}

let BENCHMARK = true
let runningOnMac = ProcessInfo.processInfo.isMacCatalystApp
let deviceHas6GBOrMore = ProcessInfo.processInfo.physicalMemory > 5910000000   // Reported by iOS 17 beta (21A5319a) on iPhone 13 Pro: 5917753344

let deviceSupportsQuantization = {
    if #available(iOS 17, *) {
        true
    } else {
        false
    }
}()
