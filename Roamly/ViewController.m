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
//    return @"ggml-tiny.en";
    return @"ggml-base.en";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:[self getModelName] ofType:@"bin"];
    NSLog(@"Loading model from %@", modelPath);
    self.selfTextView.text = @"Loading model";
    
    struct whisper_context_params cparams = whisper_context_default_params();
    stateInp.ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);
    
    if (stateInp.ctx == NULL) {
        NSLog(@"Failed to load model");
        return;
    }
    
    [self setupAudioFormat:&stateInp.dataFormat];
        
    // number of samples to transcribe
    stateInp.n_samples = TRANSCRIBE_STEP_MS*SAMPLE_RATE/1000; // 3000ms * 16000sample/s
    stateInp.result = [NSMutableString stringWithString:@""];
    stateInp.audioRingBuffer = [[RingBuffer alloc] initWithCapacity:RING_BUFFER_LEN_SEC*SAMPLE_RATE];
    
    stateInp.isTranscribing = false;
    stateInp.excludedStrings = @[@"[BLANK_AUDIO]", @"(clapping)", @"(crowd murmuring)", @"[APPLAUSE]"];
    
    // Init default UI
    [_selfStartButton setTitle:@"Start Capture" forState:UIControlStateNormal];
    [_selfStartButton setBackgroundColor:[UIColor lightGrayColor]];
    [_selfStartButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.selfTextView.layer.borderColor = [UIColor grayColor].CGColor;
    self.selfTextView.layer.borderWidth = 1.0;
    self.selfTextView.layer.cornerRadius = 5.0;

    self.selfTextView.text = @"Press \"Start Capture\" to start";
    
    stateInp.audioWave = [NSMutableString stringWithString:@""];
}

- (IBAction)selfStartButton:(id)sender {
    UIButton *button = (UIButton *)sender;
    self.isSelfTranscribing = YES;
    if (stateInp.isCapturing) {
        NSLog(@"Stop capture");
        [self stopCapturing];
    } else {
        NSLog(@"Start capture");
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

- (void)startAudioCapturing {
    if (stateInp.isCapturing) {
        [self stopCapturing];
        return;
    }
    
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
        
        // Cancel any existing timer if it exists
        [self->stateInp.transcriptionTimer invalidate];
        
        // Wait TRANSCRIBE_STEP_MS ms to start the first transcription
        self->stateInp.transcriptionTimer = [NSTimer scheduledTimerWithTimeInterval:TRANSCRIBE_STEP_MS / 1000.0
                                                                              target:self
                                                                            selector:@selector(initialTranscriptionCall)
                                                                            userInfo:nil
                                                                             repeats:NO];
    } else {
        [self stopCapturing];
    }
}

- (void)initialTranscriptionCall {
    NSUInteger sampleCount = TRANSCRIBE_STEP_MS * SAMPLE_RATE / 1000;
    [self transcribeFromRingBuffer:stateInp.audioRingBuffer startingAtIndex:0 sampleCount:sampleCount];
    
    // Setup a regular call with offset
    self->stateInp.transcriptionTimer = [NSTimer scheduledTimerWithTimeInterval:TRANSCRIBE_OFFSET_MS / 1000.0
                                                                          target:self
                                                                        selector:@selector(regularTranscriptionCall)
                                                                        userInfo:nil
                                                                         repeats:YES];
}

- (void)regularTranscriptionCall {
    static NSUInteger startIndex = 0;
    NSUInteger sampleCount = TRANSCRIBE_STEP_MS * SAMPLE_RATE / 1000;
    NSUInteger stepSize = TRANSCRIBE_OFFSET_MS * SAMPLE_RATE / 1000;
    
    startIndex += stepSize;
    
    [self transcribeFromRingBuffer:stateInp.audioRingBuffer startingAtIndex:startIndex sampleCount:sampleCount];
}

- (IBAction)stopCapturing {
    NSLog(@"Stop capturing");
    stateInp.isCapturing = false;

    AudioQueueStop(stateInp.queue, true);
    for (int i = 0; i < NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(stateInp.queue, stateInp.buffers[i]);
    }

    AudioQueueDispose(stateInp.queue, true);
    
    [self->stateInp.transcriptionTimer invalidate];
    self->stateInp.transcriptionTimer = nil;
    
//    [self sendPostRequestWithString:self->stateInp.audioWave];
//    self->stateInp.audioWave = [NSMutableString stringWithString:@""];
}

- (NSString *)getTextFromCxt:(struct whisper_context *)ctx {
    NSMutableString *result = [NSMutableString string];
    
    int n_segments = whisper_full_n_segments(ctx);
    
    for (int i = 0; i < n_segments; i++) {
        const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
        const int64_t t1 = whisper_full_get_segment_t1(ctx, i);
        
        const char *text_cur = whisper_full_get_segment_text(ctx, i);
        NSString *segmentText = [NSString stringWithUTF8String:text_cur];
        
        [result appendFormat:@"[%5.3f --> %5.3f]  %@\n", t0/100.0, t1/100.0, segmentText];
    }
    
    return result;
}

- (void)transcribeFromRingBuffer:(RingBuffer *)ringBuffer startingAtIndex:(NSUInteger)startIndex sampleCount:(NSInteger)count {
    if (!ringBuffer || count == 0) {
        NSLog(@"Invalid ring buffer or count");
        return;
    }

    // Allocate memory for the segment to transcribe
    float *segment = (float *)malloc(sizeof(float) * count);
    if (!segment) {
        NSLog(@"Failed to allocate memory for audio segment");
        return;
    }

    // Use peekSamples to copy the required audio data without modifying the buffer's read pointer
    [ringBuffer peekSamples:segment count:count fromIndex:startIndex];

    // Dispatch transcription work to a background queue
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Prepare transcription parameters
        struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        const int max_threads = 2; // Use a suitable number of threads
        
        params.print_realtime   = true;
        params.print_progress   = false;
        params.print_timestamps = true;
        params.print_special    = false;
        params.translate        = false;
        params.language         = "en";
        params.n_threads        = max_threads;
        params.offset_ms        = 0;
        params.no_context       = true;
        params.single_segment   = false;
        params.no_timestamps    = false;
        
        params.split_on_word    = true;
        params.max_len          = 1;
        params.token_timestamps = true;
        
        // Perform the transcription
        if (whisper_full(self->stateInp.ctx, params, segment, (int)count) != 0) {
            NSLog(@"Failed to run the model");
        } else {
            NSString *transcriptionResult = [self getTextFromCxt:self->stateInp.ctx];
            NSLog(@"Transcription result: \n%@", transcriptionResult);
            
            // Dispatch back to the main thread for any UI updates
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_selfTextView.text = [self->_selfTextView.text stringByAppendingString:transcriptionResult];
            });
        }
        
        // Free the allocated memory
        free(segment);
    });
}

// function is called when buffer in AudioQueueBufferRef is FULL
// then this function will deep copy the content in that buffer to audioBufferI16
// Old path:
//          Microphone -> AudioQueueBuffer --FULL--> offload to audioBufferI16 --onTranscribe--> audioBufferF32 --> ctx --> text
// New path:
//          Microphone -> AudioQueueBuffer --FULL--> offload to audioRingBuffer ---onTranscribe--> segment --> ctx --> text
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
    
//    float sum = 0.0f;
    for (int i = 0; i < n; i++) {
        float sample = (float)((short*)inBuffer->mAudioData)[i] / 32768.0f;
        [stateInp->audioRingBuffer addSample:sample];
//        sum += fabs(sample);

//        [stateInp->audioWave appendString:[NSString stringWithFormat:@"%f", sample]];
//        [stateInp->audioWave appendString:@", "];
    }
    
//    NSLog(@"Avg in buffer: %f", sum / n);
    
    // put the buffer back in the queue, keep refill
    AudioQueueEnqueueBuffer(stateInp->queue, inBuffer, 0, NULL);
}

- (IBAction)buttonClear:(id)sender {
    self->_selfTextView.text = @"";
    self->stateInp.result = [NSMutableString stringWithString:@""];
}

- (void)sendPostRequestWithString:(NSString *)string {
    // URL of the local server
    NSURL *url = [NSURL URLWithString:@"http://10.0.0.25:1100/"];
    
    // Create a NSMutableURLRequest using the URL
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    // Set the request's content type to application/json
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    // Set the request method to POST
    [request setHTTPMethod:@"POST"];
    
    // Prepare the JSON payload
    NSDictionary *jsonPayload = @{@"values": string};
    
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonPayload options:0 error:&error];
    if (!jsonData) {
        NSLog(@"Failed to serialize JSON: %@", error);
        return;
    }
    
    // Set the request's HTTP body
    [request setHTTPBody:jsonData];
    
    // Create an NSURLSession
    NSURLSession *session = [NSURLSession sharedSession];
    
    // Create a data task
    NSURLSessionDataTask *dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"Error sending request: %@", error);
            return;
        }
        
        // Handle the response
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 200) {
            NSLog(@"Successfully sent data to server.");
        } else {
            NSLog(@"Server returned status code: %ld", (long)httpResponse.statusCode);
        }
    }];
    
    // Start the data task
    [dataTask resume];
}

@end
