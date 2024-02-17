//
//  ViewController.m
//  Roamly
//
//  Created by Haolin Zhang on 2/9/24.
//

#import "ViewController.h"

#import "whisper.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)setupAudioFormat:(AudioStreamBasicDescription*)format
{
    format->mSampleRate       = WHISPER_SAMPLE_RATE;
    format->mFormatID         = kAudioFormatLinearPCM;
    format->mFramesPerPacket  = 1;
    format->mChannelsPerFrame = 1;
    format->mBytesPerFrame    = 2;
    format->mBytesPerPacket   = 2;
    format->mBitsPerChannel   = 16;
    format->mReserved         = 0;
    format->mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger;
}

- (NSString *)getModelName {
//    return @"ggml-base";
//    return @"ggml-tiny";
    return @"ggml-tiny.en";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:[self getModelName] ofType:@"bin"];
    NSLog(@"Loading model from %@", modelPath);
    self.selfTextView.text = @"Loading model";
    
    struct whisper_context_params cparams = whisper_context_default_params();
    stateInp.ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);
    stateInp.isRealtime = true;
    
    if (stateInp.ctx == NULL) {
        NSLog(@"Failed to load model");
        return;
    }
    
    [self setupAudioFormat:&stateInp.dataFormat];
        
    // number of samples to transcribe
    stateInp.n_samples = TRANSCRIBE_STEP_MS*SAMPLE_RATE/1000; // 500ms * 16000sample/s
     
    // here we allocate the memory for pcmf32, to be used to transcribe
    stateInp.audioBufferF32 = malloc(stateInp.n_samples*sizeof(float));
    stateInp.audioRingBuffer = [[RingBuffer alloc] initWithCapacity:RING_BUFFER_LEN_SEC*SAMPLE_RATE];
    
//    stateInp.testBuffer = malloc(30*16000*sizeof(float));
//    stateInp.test_n = 0;
    
    stateInp.result = [NSMutableString stringWithString:@""];
    
    stateInp.isTranscribing = false;
    stateInp.isRealtime = true;
    
    // Init default UI
    [_selfStartButton setTitle:@"Start Capture" forState:UIControlStateNormal];
    [_selfStartButton setBackgroundColor:[UIColor lightGrayColor]];
    [_selfStartButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.selfTextView.layer.borderColor = [UIColor grayColor].CGColor;
    self.selfTextView.layer.borderWidth = 1.0;
    self.selfTextView.layer.cornerRadius = 5.0;

    self.selfTextView.text = @"Press \"Start Capture\" to start";
}

- (IBAction)selfStartButton:(id)sender {
    UIButton *button = (UIButton *)sender;
    self.isSelfTranscribing = YES;
    if (stateInp.isCapturing) {
        NSLog(@"Self stop capture");
        [self stopCapturing];
    } else {
        NSLog(@"Self start capture");
        [self startAudioCapturing];
    }
    [self updateButton:button forCapturingState:stateInp.isCapturing];
}

- (void)updateButton:(UIButton *)button forCapturingState:(BOOL)isCapturing {
    if (isCapturing) {
        [button setTitle:@"Stop Capturing" forState:UIControlStateNormal];
        [button setBackgroundColor:[UIColor grayColor]];
    } else {
        [button setTitle:@"Start Capture" forState:UIControlStateNormal];
        [button setBackgroundColor:[UIColor lightGrayColor]];
    }
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
}

// Frontend thread (main), keep enqueue the audio chunk
- (void)startAudioCapturing {
    if (stateInp.isCapturing) {
        [self stopCapturing];
        return;
    }
    
    stateInp.audioRingBuffer = [[RingBuffer alloc] initWithCapacity:RING_BUFFER_LEN_SEC*SAMPLE_RATE];

    NSLog(@"Start capturing");
    
    stateInp.vc = (__bridge void *)(self);
    OSStatus status = AudioQueueNewInput(&stateInp.dataFormat,
                                         AudioInputCallback,
                                         &stateInp,
                                         CFRunLoopGetCurrent(),
                                         kCFRunLoopCommonModes,
                                         0,
                                         &stateInp.queue);

    if (status == 0) {
        for (int i = 0; i < NUM_BUFFERS; i++) {
            AudioQueueAllocateBuffer(stateInp.queue, NUM_BYTES_PER_BUFFER, &stateInp.buffers[i]);
            AudioQueueEnqueueBuffer(stateInp.queue, stateInp.buffers[i], 0, NULL);
        }
        stateInp.isCapturing = true;
        AudioQueueStart(stateInp.queue, NULL);
    } else {
        [self stopCapturing];
    }
}

- (IBAction)stopCapturing {
    NSLog(@"Stop capturing");
    stateInp.isCapturing = false;

    AudioQueueStop(stateInp.queue, true);
    for (int i = 0; i < NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(stateInp.queue, stateInp.buffers[i]);
    }

    AudioQueueDispose(stateInp.queue, true);
    
    [self->stateInp.audioRingBuffer clear];
    stateInp.audioRingBuffer = nil;
}

- (NSString *)getTextFromCxt:(struct whisper_context *) ctx{
    NSString *result = @"";
    
    // get know how many segments model splits the given audio
    int n_segments = whisper_full_n_segments(self->stateInp.ctx);
    
    // concate text transcribed from each segment
    for (int i = 0; i < n_segments; i++) {
        const char * text_cur = whisper_full_get_segment_text(self->stateInp.ctx, i);
        // append the text to the result
        result = [result stringByAppendingString:[NSString stringWithUTF8String:text_cur]];
    }
    
    return result;
}

// Backend thread, keep dequeue audio queue and transcribe
- (IBAction)onTranscribe:(id)sender {
    if (stateInp.isTranscribing) {
        return;
    }

    NSLog(@"Processing %d samples", stateInp.n_samples);

    stateInp.isTranscribing = true;

    // dispatch the model to a background thread
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        float *transcribeSamples = (float *)malloc(sizeof(float) * self->stateInp.n_samples);
        // fetch n_sample from ring buffer to transcribeSamples
        [self->stateInp.audioRingBuffer readSamples:transcribeSamples count:self->stateInp.n_samples];
        
        for (int i = 0; i < 100; i++) {
            NSLog(@"Sample %d: %f", i, transcribeSamples[i]);
        }
        
        // run the model
        struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

        // get maximum number of threads on this device (max 8)
        // const int max_threads = MIN(8, (int)[[NSProcessInfo processInfo] processorCount]);
        const int max_threads = 4;
        
        params.print_realtime   = true;
        params.print_progress   = false;
        params.print_timestamps = true;
        params.print_special    = false;
        params.translate        = false;
        params.language         = "en";
        params.n_threads        = max_threads;
        params.offset_ms        = 0;
        params.no_context       = true;
        params.single_segment   = self->stateInp.isRealtime;
        params.no_timestamps    = params.single_segment;

        CFTimeInterval startTime = CACurrentMediaTime();

        whisper_reset_timings(self->stateInp.ctx);

        // param: ctx:            all whisper internal state weights
        //        params:         hyper parameters
        //        audioBufferF32: converted raw audio data
        //        n_samples:      number of samples in audioBufferF32
        if (whisper_full(self->stateInp.ctx, params, transcribeSamples, self->stateInp.n_samples) != 0) {
            NSLog(@"Failed to run the model");
            self->_selfTextView.text = @"Failed to run the model";

            return;
        }
        
//        if (whisper_full(self->stateInp.ctx, params, self->stateInp.testBuffer, self->stateInp.test_n) != 0) {
//            NSLog(@"Failed to run the model");
//            self->_selfTextView.text = @"Failed to run the model";
//
//            return;
//        }
        
        whisper_print_timings(self->stateInp.ctx);

        CFTimeInterval endTime = CACurrentMediaTime();

        NSLog(@"\nProcessing time: %5.3f, on %d threads", endTime - startTime, params.n_threads);
        
        [self->stateInp.result appendString:[self getTextFromCxt:self->stateInp.ctx]];
        
        NSLog(@"result: %@", [self getTextFromCxt:self->stateInp.ctx]);
        
//        NSString * rst = [self getTextFromCxt:self->stateInp.ctx];
        free(transcribeSamples);
        
//        const float tRecording = (float)self->stateInp.n_samples / (float)self->stateInp.dataFormat.mSampleRate;

//        // append processing time
//        result = [result stringByAppendingString:[NSString stringWithFormat:@"\n\n[recording time:  %5.3f s]", tRecording]];
//        result = [result stringByAppendingString:[NSString stringWithFormat:@"  \n[processing time: %5.3f s]", endTime - startTime]];

        // dispatch the result to the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.isSelfTranscribing) {
                    // update the textview with new result
                    self->_selfTextView.text = self->stateInp.result;
//                    self->_selfTextView.text = rst;
                }
                self->stateInp.isTranscribing = false;
            });
        });
    });
}

// function is called when buffer in AudioQueueBufferRef is FULL
// then this function will deep copy the content in that buffer to audioBufferI16
// Microphone -> AudioQueueBuffer --FULL--> offload to audioBufferI16 --onTranscribe--> audioBufferF32 --> ctx --> text
void AudioInputCallback(void * inUserData,
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs)
{
    StateInp * stateInp = (StateInp*)inUserData;

    if (!stateInp->isCapturing) {
        NSLog(@"Not capturing, ignoring audio");
        return;
    }
    
    // how many samples AudioBuffer captured
    const int n = inBuffer->mAudioDataByteSize / 2;

    // deep copy raw audio from AudioQueueBuffer to audioBufferF32 (also convert)
    for (int i = 0; i < n; i++) {
        float sample = (float)((short*)inBuffer->mAudioData)[i] / 32768.0f;
        [stateInp->audioRingBuffer addSample:sample];
//        stateInp->testBuffer[stateInp->test_n + i] = sample;
        
//        if (i < 50) {
//            NSLog(@"get sample %f", sample);
//        }
    }
    
    NSLog(@"%d new samples queued in ring buffer", n);
    
//    stateInp->test_n += n;

    // put the buffer back in the queue, keep refill
    AudioQueueEnqueueBuffer(stateInp->queue, inBuffer, 0, NULL);

    // dipatch onTranscribe() to the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        ViewController * vc = (__bridge ViewController *)(stateInp->vc);
        [vc onTranscribe:nil];
    });
}

@end
