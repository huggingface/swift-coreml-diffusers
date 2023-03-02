//
//  HistoryView.swift
//  Diffusion-macOS
//
//  Created by Daniel Colish on 2/28/23.
//


import SwiftUI

struct HistoryView: View {
    @ObservedObject var context = GenerationContext()
    @State private var disclosedHistory = true
    func computeUnitsToString(units: ComputeUnits) -> String{
        switch(units) {
        case ComputeUnits.cpuAndGPU:
            return "CPU and GPU"
        case ComputeUnits.cpuAndNeuralEngine:
            return "CPU and ANE"
        case ComputeUnits.cpuOnly:
            return "CPU"
        default:
            return "ALL"
        }
    }
    
    var body: some View {
        VStack (alignment: .leading) {
            Label("Generation History", systemImage: "fossil.shell.fill")
                .font(.headline)
                .fontWeight(.bold)
            VStack {
                List(context.dataStore.historyItems) { item in
                    VStack(alignment: .leading) {
                        Text("Prompt: " + item.prompt)
                            .font(.body)
                        if (!item.negativePrompt.isEmpty) {
                            Text("Negative Prompt: " + item.negativePrompt)
                                .font(.body)
                        }
                        Text("Seed: " + item.seed.formatted()).font(.body)
                        Text("Steps: " + item.steps.formatted()).font(.body)
                        Text("Guidance: " + item.guidance.formatted()).font(.body)
                        Text("Compute: " + self.computeUnitsToString(units: ComputeUnits(rawValue: item.computeUnits) ?? ComputeUnits.all)).font(.body)
                        Text("Timing: " + item.timing.formatted()).font(.body)
                    }
                }
                .textSelection(.enabled)
            }
            .navigationTitle("Generation History")
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
    }
}
