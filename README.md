# Whisper iOS

An Obj-C application for automatic offline speech recognition.
The inference runs locally, on-device. Forked from [whisper.cpp](https://github.com/ggerganov/whisper.cpp) project

## System setting

- Xcode 15.2 

- iOS 17.3.1 (Xcode 15 emulator currently have some bug to run CoreML models, so only run with real iPhone for now)

- Developer mode on

## Note

The `ggml-tiny`, `ggml-tiny.en`, `ggml-base` and `ggml-base.en` model has already been converted to Core ML model and packed in this project.
If you need more model, follow [this](https://github.com/ggerganov/whisper.cpp/tree/master/models#1-use-download-ggml-modelsh-to-download-pre-converted-models) 
instruction to download the `ggml-*.bin` model file and [this](https://github.com/ggerganov/whisper.cpp/blob/master/README.md#core-ml-support) 
instruction to convert `ggml-*.bin` files to `*.mlmodelc` (coreml) file

## What is different

- Always run on real time mode

- Limited `n_threads` to 4 when transcribing, less system resource usage

- Abstract the frontend and backend

- Use circular buffer to enable unlimited processing real time audio

## Usage

```bash
git clone https://github.com/Chrisz236/whisper_ios.git

cd whisper_ios/Roamly/ && mkdir models && cd models

# for tiny model (39M parameters) 
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin

# for tiny.en model (39M parameters) 
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin

# for base model (74M parameters)
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin

# for base.en model (74M parameters)
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

cd ../../ && open Roamly.xcodeproj/

```

after open the project in Xcode, drag the `bin` files from `models` folder to Xcode workspace (on the left where files are listed)

## Run on Xcode emulator

Xcode 15 has BUG on run CoreML application, this approach is current not work (02/19/2024)

To run project on Xcode emulator, add following code snippet after `struct whisper_context_params cparams = whisper_context_default_params();` in `- (void)viewDidLoad` function in `ViewController.m`

```objective-c
#if TARGET_OS_SIMULATOR
        cparams.use_gpu = false;
        NSLog(@"Running on simulator, using CPU");
#endif
```

refer [original](https://github.com/ggerganov/whisper.cpp/blob/master/examples/whisper.objc/whisper.objc/ViewController.m) for more detail