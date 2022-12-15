//
//  TextToImageView.swift
//  Diffusion
//
//  Created by Pedro Cuenca on December 2022.
//  See LICENSE at https://github.com/huggingface/swift-coreml-diffusers/LICENSE
//

import SwiftUI
import Combine
import StableDiffusion

enum GenerationState {
    case startup
    case running(StableDiffusionProgress?)
    case idle(String)
}

struct TextToImageView: View {
    @EnvironmentObject var context: DiffusionGlobals
	
	@State private var image: CGImage? = nil
	@State private var state: GenerationState = .startup
    @State private var prompt = "Labrador in the style of Vermeer"
	@State private var scheduler = StableDiffusionScheduler.dpmpp
	@State private var width = 512.0
	@State private var height = 512.0
	@State private var steps = 25.0
	@State private var numImages = 1.0
	@State private var seed: UInt32? = nil
	@State private var safetyOn: Bool = true

    @State private var progressSubscriber: Cancellable?

    func submit() {
        if case .running = state { return }
        Task {
            state = .running(nil)
            image = await generate(pipeline: context.pipeline, prompt: prompt)
            state = .idle(prompt)
        }
    }
    
    var body: some View {
		VStack(alignment: .leading) {
            HStack {
                TextField("Prompt", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submit()
                    }
                Button("Generate") {
                    submit()
                }
                .padding()
                .buttonStyle(.borderedProminent)
            }
			Spacer()
			HStack(alignment: .top) {
				VStack(alignment: .leading) {
					Group {
						Text("Image Width")
						Slider(value: $width, in: 64...2048, step: 8, label: {},
							   minimumValueLabel: {Text("64")},
							   maximumValueLabel: {Text("2048")})
						Text("Image Height")
						Slider(value: $height, in: 64...2048, step: 8, label: {},
							   minimumValueLabel: {Text("64")},
							   maximumValueLabel: {Text("2048")})
					}
					Text("Number of Inference Steps")
					Slider(value: $steps, in: 1...300, step: 1, label: {},
						minimumValueLabel: {Text("1")},
						maximumValueLabel: {Text("300")})
					Text("Number of Images")
					Slider(value: $numImages, in: 1...8, step: 1, label: {},
						minimumValueLabel: {Text("1")},
						maximumValueLabel: {Text("8")})
					Text("Safety")
					Toggle("", isOn: $safetyOn)
					Text("Seed Check On?")
					TextField("", value: $seed, format: .number)
				}
				Spacer()
				VStack {
					PreviewView(image: $image, state: $state)
						.scaledToFit()
				}
			}
            Spacer()
        }
        .padding()
        .onAppear {
            progressSubscriber = context.pipeline?.progressPublisher.sink { progress in
                guard let progress = progress else { return }
                state = .running(progress)
            }
        }
    }
	
	func generate(pipeline: Pipeline?, prompt: String) async -> CGImage? {
		guard let pipeline = pipeline else { return nil }
		return try? pipeline.generate(prompt: prompt, scheduler: scheduler, numInferenceSteps: Int(steps), safetyOn: safetyOn, seed: seed)
	}
}

struct TextToImageView_Previews: PreviewProvider {
	static var previews: some View {
		TextToImageView().environmentObject(DiffusionGlobals())
	}
}
