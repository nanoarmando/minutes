// Adapted from Muesli (https://github.com/Muesli-HQ/muesli),
// native/MuesliNative/Sources/AudioGraphExceptionBridge/include/AudioGraphExceptionBridge.h
// Copyright (c) 2026 Pranav Hari. MIT License; see THIRD_PARTY_NOTICES.md.

#import <Foundation/Foundation.h>
#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

/// AVAudioEngine raises Objective-C exceptions while a hardware route is settling (for example when AirPods
/// connect). Swift cannot catch them, so every engine call that may throw goes through these wrappers and
/// returns an NSError instead.
FOUNDATION_EXPORT AVAudioFormat * _Nullable MinutesAudioGraphInputFormat(AVAudioEngine *engine, NSError * _Nullable * _Nullable error);
FOUNDATION_EXPORT NSError * _Nullable MinutesAudioGraphInstallInputTap(
    AVAudioEngine *engine,
    AVAudioFrameCount bufferSize,
    AVAudioNodeTapBlock block
);
FOUNDATION_EXPORT NSError * _Nullable MinutesAudioGraphStartEngine(AVAudioEngine *engine);
FOUNDATION_EXPORT NSError * _Nullable MinutesAudioGraphStopEngine(AVAudioEngine *engine);

NS_ASSUME_NONNULL_END
