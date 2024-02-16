//
//  RingBuffer.h
//  Roamly
//
//  Created by Haolin Zhang on 2/15/24.
//

#import <Foundation/Foundation.h>

@interface RingBuffer : NSObject

// Initializes the ring buffer with a specific capacity.
- (instancetype)initWithCapacity:(NSUInteger)capacity;

// Adds a sample to the ring buffer.
- (void)addSample:(float)sample;

// Adds multiple samples to the ring buffer.
- (void)addSamples:(const float *)samples count:(NSUInteger)count;

// Reads samples from the ring buffer into a provided buffer.
- (void)readSamples:(float *)buffer count:(NSUInteger)count;

// Clears the ring buffer.
- (void)clear;

@end
