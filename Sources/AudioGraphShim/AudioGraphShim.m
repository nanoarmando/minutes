// Adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/AudioGraphExceptionBridge/AudioGraphExceptionBridge.m
// Copyright (c) 2026 Pranav Hari. MIT License; see THIRD_PARTY_NOTICES.md.

#import "AudioGraphShim.h"

static NSString *const MinutesAudioGraphErrorDomain = @"MinutesAudioGraph";

static NSError *MinutesAudioGraphError(NSString *message) {
    return [NSError errorWithDomain:MinutesAudioGraphErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSError *MinutesAudioGraphExceptionError(NSException *exception, NSString *operation) {
    return MinutesAudioGraphError([NSString stringWithFormat:@"%@ failed: %@", operation,
                                   exception.reason ?: exception.name]);
}

AVAudioFormat *MinutesAudioGraphInputFormat(AVAudioEngine *engine, NSError **error) {
    @try {
        AVAudioFormat *format = [engine.inputNode outputFormatForBus:0];
        if (format.streamDescription == NULL || format.sampleRate <= 0) {
            if (error) { *error = MinutesAudioGraphError(@"No microphone input is available"); }
            return nil;
        }
        return format;
    } @catch (NSException *exception) {
        if (error) { *error = MinutesAudioGraphExceptionError(exception, @"Read microphone format"); }
        return nil;
    }
}

NSError *MinutesAudioGraphInstallInputTap(AVAudioEngine *engine, AVAudioFrameCount bufferSize, AVAudioNodeTapBlock block) {
    @try {
        [engine.inputNode installTapOnBus:0 bufferSize:bufferSize format:nil block:block];
        return nil;
    } @catch (NSException *exception) {
        return MinutesAudioGraphExceptionError(exception, @"Install microphone tap");
    }
}

NSError *MinutesAudioGraphStartEngine(AVAudioEngine *engine) {
    @try {
        [engine prepare];
        NSError *error = nil;
        if (![engine startAndReturnError:&error]) {
            return error ?: MinutesAudioGraphError(@"Start audio engine failed");
        }
        return nil;
    } @catch (NSException *exception) {
        return MinutesAudioGraphExceptionError(exception, @"Start audio engine");
    }
}

// Stops the engine first and then removes the tap: removing a tap from a running engine can deadlock behind
// a route change.
NSError *MinutesAudioGraphStopEngine(AVAudioEngine *engine) {
    @try {
        [engine stop];
        [engine.inputNode removeTapOnBus:0];
        return nil;
    } @catch (NSException *exception) {
        return MinutesAudioGraphExceptionError(exception, @"Stop audio engine");
    }
}
