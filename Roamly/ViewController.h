//
//  ViewController.h
//  Roamly
//
//  Created by Haolin Zhang on 2/9/24.
//

#import <UIKit/UIKit.h>

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioQueue.h>

#import "RingBuffer.h"

#define NUM_BUFFERS 3
#define TRANSCRIBE_STEP_MS 3000
#define RING_BUFFER_LEN_SEC 30
#define SAMPLE_RATE 16000
#define NUM_BYTES_PER_BUFFER 1600  // 0.05s per buffer

// silence detection setup
#define WHISPER_MAX_LEN_SEC 30
#define SILENCE_THOLD 0.008
#define MIN_SILENCE_MS 100

typedef struct
{
    int ggwaveId;
    bool isCapturing;
    bool isTranscribing;
    bool isRealtime;
    UILabel * labelReceived;

    AudioQueueRef queue;
    AudioStreamBasicDescription dataFormat;
    AudioQueueBufferRef buffers[NUM_BUFFERS];
    
    int n_samples;
    RingBuffer * audioRingBuffer;
    
    // ctx includes model current status
    struct whisper_context * ctx;
    
    NSMutableString * result;
    NSTimer * transcriptionTimer;
    
    NSMutableString * audioWave;
    
    NSArray * excludedStrings;

    void * vc;
} StateInp;

// callback used to process captured audio
void AudioInputCallback(void * inUserData,
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs);

@interface ViewController : UIViewController

{
    StateInp stateInp;
}

@property (weak, nonatomic) IBOutlet UITextView *selfTextView;
- (IBAction)selfStartButton:(id)sender;

@property (weak, nonatomic) IBOutlet UIButton *selfStartButton;
- (IBAction)buttonClear:(id)sender;

// To track which textview to update
@property (nonatomic, assign) BOOL isSelfTranscribing;

@end
