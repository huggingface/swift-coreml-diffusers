#  Diffusers

This is a simple app that shows how to integrate Apple's [Core ML Stable Diffusion implementation](https://github.com/apple/ml-stable-diffusion) in a native Swift UI application. It can be used for faster iteration, or as sample code for other use cases.

This is what it looks like:
![App Screenshot](screenshot.jpg)

On first launch, the application downloads a zipped archive with a Core ML version of Runway's Stable Diffusion v1.5, from [this location in the Hugging Face Hub](https://huggingface.co/pcuenq/coreml-stable-diffusion/tree/main). This process takes a while, as several GB of data have to be downloaded and unarchived.

For faster inference, we use a very fast scheduler: [DPM-Solver++](https://github.com/LuChengTHU/dpm-solver) that we ported to Swift. Since this scheduler is still not available in Apple's GitHub repository, the application depends on the following fork instead: https://github.com/pcuenca/ml-stable-diffusion. Our Swift port is based on [Diffusers' DPMSolverMultistepScheduler](https://github.com/huggingface/diffusers/blob/main/src/diffusers/schedulers/scheduling_dpmsolver_multistep.py), with a number of simplifications.

## Compatibility

- macOS Ventura 13.1, iOS/iPadOS 16.2, Xcode 14.2.
- Performance (after the initial generation, which is slower)
  * ~8s in macOS on MacBook Pro M1 Max (64 GB). Model: Stable Diffusion v2-base, ORIGINAL attention implementation, CPU + GPU.
  * 23 ~ 30s on iPhone 13 Pro. Model: Stable Diffusion v2-base, SPLIT_EINSUM attention, CPU + Neural Engine, memory reduction enabled.

Performance on iPhone is somewhat erratic, sometimes it's ~20x slower and the phone heats up. This happens because the model could not be scheduled to run on the Neural Engine and everything happens in the CPU. We have not been able to determine the reasons for this problem. If you observe the same, here are some recommendations:
- Detach from Xcode
- Kill apps you are not using.
- Let the iPhone cool down before repeating the test.
- Reboot your device.

## How to Build

If you clone or fork this repo, please update `common.xcconfig` with your development team identifier. Code signing is required to run on iOS, but it's currently disabled for macOS.

## Limitations

- A handful of models are currently supported.
- The Core ML compute units have been hardcoded to CPU and GPU on macOS, and to CPU + Neural Engine on iOS/iPadOS.

## Next Steps

- Allow users to select compute units to verify the combination that achieves the best performance on their hardware.
- Implement other schedulers, additional options.
- Experiment with smaller distilled models.
