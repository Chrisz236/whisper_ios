//
//  RingBuffer.m
//  Roamly
//
//  Created by Haolin Zhang on 2/16/24.
//

#import "RingBuffer.h"

@interface RingBuffer () {
    float *_buffer;
    NSUInteger _capacity;
    NSUInteger _head;
    NSUInteger _tail;
    BOOL _isFull;
}

@end

@implementation RingBuffer

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    if (self = [super init]) {
        _capacity = capacity;
        _buffer = (float *)malloc(sizeof(float) * capacity);
        _head = 0;
        _tail = 0;
        _isFull = NO;
    }
    return self;
}

- (void)dealloc {
    if (_buffer) {
        free(_buffer);
        _buffer = NULL;
    }
}

- (void)addSample:(float)sample {
    if (_isFull) {
        _tail = (_tail + 1) % _capacity; // Move tail forward if the buffer is full
    }

    _buffer[_head] = sample;
    _head = (_head + 1) % _capacity;
    _isFull = _head == _tail;
}

- (void)addSamples:(const float *)samples count:(NSUInteger)count {
    for (NSUInteger i = 0; i < count; i++) {
        [self addSample:samples[i]];
    }
}

- (void)readSamples:(float *)buffer count:(NSUInteger)count {
    NSUInteger available = [self availableSamples];
    count = MIN(count, available);

    for (NSUInteger i = 0; i < count; i++) {
        buffer[i] = _buffer[_tail];
        _tail = (_tail + 1) % _capacity;
    }
    
    if (_tail == _head) {
        _isFull = NO;
    }
}

- (float)getOneSample {
    if (_head == _tail && !_isFull) {
        // Buffer is empty, return 2.0
        return 2.0f;
    }

    float sample = _buffer[_tail];
    _tail = (_tail + 1) % _capacity;
    _isFull = NO; // Once we read a sample, the buffer can't be full

    return sample;
}

- (NSUInteger)availableSamples {
    if (_isFull) {
        return _capacity;
    } else if (_head >= _tail) {
        return _head - _tail;
    } else {
        return _head + (_capacity - _tail);
    }
}

- (void)clear {
    _head = 0;
    _tail = 0;
    _isFull = NO;
}

@end
