//
//  PreviewView.swift
//  Diffusion
//
//  Created by Fahim Farook on 15/12/2022.
//

import SwiftUI

struct PreviewView: View {
	var image: Binding<CGImage?>
	var state: Binding<GenerationState>
		
	var body: some View {
		switch state.wrappedValue {
		case .startup: return AnyView(Image("placeholder").resizable())
		case .running(let progress):
			guard let progress = progress, progress.stepCount > 0 else {
				// The first time it takes a little bit before generation starts
				return AnyView(ProgressView())
			}
			let step = Int(progress.step) + 1
			let fraction = Double(step) / Double(progress.stepCount)
			let label = "Step \(step) of \(progress.stepCount)"
			return AnyView(ProgressView(label, value: fraction, total: 1).padding())
		case .idle(let lastPrompt):
			guard let theImage = image.wrappedValue else {
				return AnyView(Image(systemName: "exclamationmark.triangle").resizable())
			}
							  
			let imageView = Image(theImage, scale: 1, label: Text("generated"))
			return AnyView(
				VStack {
				imageView.resizable().clipShape(RoundedRectangle(cornerRadius: 20))
					ShareLink(item: imageView, preview: SharePreview(lastPrompt, image: imageView))
			})
		}
	}
}


struct PreviewView_Previews: PreviewProvider {
    static var previews: some View {
		PreviewView(image: .constant(nil), state: .constant(.startup))
    }
}
