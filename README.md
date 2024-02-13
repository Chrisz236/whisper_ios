# Whisper iOS

An Obj-C application for automatic offline speech recognition.
The inference runs locally, on-device. Forked from [whisper.cpp](https://github.com/ggerganov/whisper.cpp) project

## Note

The `ggml-tiny` and `ggml-base` model has already been converted to Core ML model in this project.
Follow [this](https://github.com/ggerganov/whisper.cpp/tree/master/models#1-use-download-ggml-modelsh-to-download-pre-converted-models) 
instruction to download the `ggml-*.bin` model file and [this](https://github.com/ggerganov/whisper.cpp/blob/master/README.md#core-ml-support) 
instruction to convert `bin` files to `mlmodelc` (coreml) file

## Usage

```bash
git clone https://github.com/Chrisz236/whisper_ios.git

cd whisper_ios/Roamly/ && mkdir models && cd models

# for tiny model (39M parameters) 
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin

# for base model (74M parameters)
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin

cd ../../ && open Roamly.xcodeproj/

```

after open the project in Xcode, drag the `bin` files from `models` folder to Xcode workspace (on the left where files are listed)
