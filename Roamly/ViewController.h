//
//  ViewController.h
//  Roamly
//
//  Created by Haolin Zhang on 2/9/24.
//

#import <UIKit/UIKit.h>

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioQueue.h>

#define NUM_BUFFERS 3
#define MAX_AUDIO_SEC 30
#define SAMPLE_RATE 16000

#define NUM_BYTES_PER_BUFFER 16*1024

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
    int16_t * audioBufferI16;
    float   * audioBufferF32;

    struct whisper_context * ctx;

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

// To track which textview to update
@property (nonatomic, assign) BOOL isSelfTranscribing;

@end
