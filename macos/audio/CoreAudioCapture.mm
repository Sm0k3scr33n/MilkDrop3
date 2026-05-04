/**
 * CoreAudioCapture.mm
 *
 * macOS system audio loopback capture implementation.
 */

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>

// ScreenCaptureKit is available on macOS 13+
#if __has_include(<ScreenCaptureKit/ScreenCaptureKit.h>)
  #import <ScreenCaptureKit/ScreenCaptureKit.h>
  #define HAS_SCREEN_CAPTURE_KIT 1
#else
  #define HAS_SCREEN_CAPTURE_KIT 0
#endif

#include "CoreAudioCapture.h"
#include <cstring>
#include <cmath>
#include <algorithm>

// ──────────────────────────────────────────────────────────────────────────────
// SCStream output delegate (ScreenCaptureKit path)
// ──────────────────────────────────────────────────────────────────────────────
#if HAS_SCREEN_CAPTURE_KIT

@interface MilkDropSCKDelegate : NSObject <SCStreamOutput>
@property (nonatomic, assign) CoreAudioCapture* capture;
@end

@implementation MilkDropSCKDelegate

- (void)stream:(SCStream*)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
                   ofType:(SCStreamOutputType)type
{
    if (type != SCStreamOutputTypeAudio) return;

    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription* asbd =
        CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
    if (!asbd) return;

    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (!block) return;

    size_t totalBytes = 0;
    char* rawBytes = nullptr;
    CMBlockBufferGetDataPointer(block, 0, nullptr, &totalBytes, &rawBytes);
    if (!rawBytes) return;

    int channels   = (int)asbd->mChannelsPerFrame;
    int frameCount = (int)CMSampleBufferGetNumSamples(sampleBuffer);
    double rate    = asbd->mSampleRate;

    // SCKit delivers non-interleaved float32 by default.
    // Convert to interleaved for our callback.
    bool isInterleaved = (asbd->mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0;
    std::vector<float> interleaved(frameCount * 2);

    if (isInterleaved && channels >= 2) {
        const float* src = reinterpret_cast<const float*>(rawBytes);
        memcpy(interleaved.data(), src, frameCount * 2 * sizeof(float));
    } else {
        // Non-interleaved: plane 0 = L, plane 1 = R
        const float* L = reinterpret_cast<const float*>(rawBytes);
        const float* R = L + frameCount;
        for (int i = 0; i < frameCount; ++i) {
            interleaved[i*2]   = L[i];
            interleaved[i*2+1] = (channels >= 2) ? R[i] : L[i];
        }
    }

    if (self.capture)
        self.capture->OnSamples(interleaved.data(), frameCount, 2, rate);
}

@end

#endif // HAS_SCREEN_CAPTURE_KIT

// ──────────────────────────────────────────────────────────────────────────────
// AudioUnit render callback (input device path)
// ──────────────────────────────────────────────────────────────────────────────
static OSStatus AudioUnitRenderCallback(
    void*                        inRefCon,
    AudioUnitRenderActionFlags*  ioFlags,
    const AudioTimeStamp*        inTimeStamp,
    UInt32                       inBusNumber,
    UInt32                       inNumberFrames,
    AudioBufferList*             ioData)
{
    auto* cap = reinterpret_cast<CoreAudioCapture*>(inRefCon);

    // Render into ioData
    AudioUnit au = (AudioUnit)cap->m_audioUnit;
    AudioUnitRender(au, ioFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData);

    if (ioData && ioData->mNumberBuffers > 0) {
        // Assume interleaved float32 stereo
        const float* samples = reinterpret_cast<const float*>(ioData->mBuffers[0].mData);
        int channels = ioData->mBuffers[0].mNumberChannels;
        cap->OnSamples(samples, (int)inNumberFrames, channels, 44100.0);
    }
    return noErr;
}

// ──────────────────────────────────────────────────────────────────────────────
// CoreAudioCapture implementation
// ──────────────────────────────────────────────────────────────────────────────

CoreAudioCapture::CoreAudioCapture() {
    m_ringL.resize(kMilkDropSampleSize * 8, 0.0f);
    m_ringR.resize(kMilkDropSampleSize * 8, 0.0f);
}

CoreAudioCapture::~CoreAudioCapture() {
    Stop();
}

bool CoreAudioCapture::Start(AudioCallback cb) {
    m_callback = cb;

#if HAS_SCREEN_CAPTURE_KIT
    if (@available(macOS 13.0, *)) {
        if (StartSCK()) {
            m_running = true;
            return true;
        }
        NSLog(@"[CoreAudioCapture] SCK start failed; falling back to AudioUnit input");
    }
#endif

    if (StartAudioUnit()) {
        m_running = true;
        return true;
    }

    NSLog(@"[CoreAudioCapture] Failed to start audio capture. "
           "For system audio on macOS 12 or earlier, install BlackHole "
           "(https://github.com/ExistentialAudio/BlackHole) and select it "
           "as the MilkDrop input device.");
    return false;
}

void CoreAudioCapture::Stop() {
    if (!m_running.load()) return;
    m_running = false;

#if HAS_SCREEN_CAPTURE_KIT
    StopSCK();
#endif
    StopAudioUnit();
}

void CoreAudioCapture::GetLatestPCM(uint8_t* dst_left, uint8_t* dst_right, int count) {
    std::lock_guard<std::mutex> lk(m_mutex);
    memcpy(dst_left,  m_snapL, std::min(count, kMilkDropSampleSize));
    memcpy(dst_right, m_snapR, std::min(count, kMilkDropSampleSize));
}

// ── ScreenCaptureKit ─────────────────────────────────────────────────────────
#if HAS_SCREEN_CAPTURE_KIT

bool CoreAudioCapture::StartSCK() {
    if (@available(macOS 13.0, *)) {
        __block bool success = false;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [SCShareableContent getShareableContentWithCompletionHandler:
            ^(SCShareableContent* content, NSError* error) {
            if (error || !content) {
                NSLog(@"[CoreAudioCapture] SCK getShareableContent error: %@", error);
                dispatch_semaphore_signal(sem);
                return;
            }

            SCStreamConfiguration* cfg = [SCStreamConfiguration new];
            cfg.capturesSampleBuffer       = YES;
            cfg.sampleRate                 = 44100;
            cfg.channelCount               = 2;
            // Minimal video (required even for audio-only streams on some versions)
            cfg.width  = 2;
            cfg.height = 2;

            SCContentFilter* filter = [[SCContentFilter alloc]
                initWithDisplay:content.displays.firstObject
                excludingWindows:@[]];

            MilkDropSCKDelegate* delegate = [MilkDropSCKDelegate new];
            delegate.capture = this;
            m_scDelegate = delegate;

            SCStream* stream = [[SCStream alloc] initWithFilter:filter
                                                  configuration:cfg
                                                       delegate:nil];
            [stream addStreamOutput:delegate
                               type:SCStreamOutputTypeAudio
                 sampleHandlerQueue:dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)
                              error:nil];

            NSError* startErr = nil;
            [stream startCaptureWithCompletionHandler:^(NSError* e) {
                if (e) NSLog(@"[CoreAudioCapture] SCK startCapture error: %@", e);
                success = (e == nil);
                dispatch_semaphore_signal(sem);
            }];
            m_scStream = stream;
        }];

        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC));
        return success;
    }
    return false;
}

void CoreAudioCapture::StopSCK() {
    if (@available(macOS 13.0, *)) {
        SCStream* stream = (SCStream*)m_scStream;
        [stream stopCaptureWithCompletionHandler:^(NSError*) {}];
        m_scStream   = nil;
        m_scDelegate = nil;
    }
}

#else
bool CoreAudioCapture::StartSCK() { return false; }
void CoreAudioCapture::StopSCK()  {}
#endif

// ── AudioUnit input (fallback) ────────────────────────────────────────────────
bool CoreAudioCapture::StartAudioUnit() {
    AudioComponentDescription desc = {};
    desc.componentType    = kAudioUnitType_IO;
    desc.componentSubType = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent comp = AudioComponentFindNext(nullptr, &desc);
    if (!comp) return false;

    AudioUnit au;
    if (AudioComponentInstanceNew(comp, &au) != noErr) return false;

    // Enable input bus
    UInt32 one = 1, zero = 0;
    AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input, 1, &one, sizeof(one));
    AudioUnitSetProperty(au, kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output, 0, &zero, sizeof(zero));

    // Set stream format: float32 interleaved stereo 44100
    AudioStreamBasicDescription fmt = {};
    fmt.mSampleRate       = 44100.0;
    fmt.mFormatID         = kAudioFormatLinearPCM;
    fmt.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel   = 32;
    fmt.mChannelsPerFrame = 2;
    fmt.mBytesPerFrame    = 8;
    fmt.mFramesPerPacket  = 1;
    fmt.mBytesPerPacket   = 8;

    AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                         kAudioUnitScope_Output, 1, &fmt, sizeof(fmt));

    // Install render callback
    AURenderCallbackStruct cb = { AudioUnitRenderCallback, this };
    AudioUnitSetProperty(au, kAudioOutputUnitProperty_SetInputCallback,
                         kAudioUnitScope_Global, 1, &cb, sizeof(cb));

    if (AudioUnitInitialize(au) != noErr) {
        AudioComponentInstanceDispose(au);
        return false;
    }
    if (AudioOutputUnitStart(au) != noErr) {
        AudioUnitUninitialize(au);
        AudioComponentInstanceDispose(au);
        return false;
    }

    m_audioUnit = au;
    return true;
}

void CoreAudioCapture::StopAudioUnit() {
    if (m_audioUnit) {
        AudioUnit au = (AudioUnit)m_audioUnit;
        AudioOutputUnitStop(au);
        AudioUnitUninitialize(au);
        AudioComponentInstanceDispose(au);
        m_audioUnit = nullptr;
    }
}

// ── Common audio data processing ──────────────────────────────────────────────
void CoreAudioCapture::OnSamples(const float* interleaved, int frameCount,
                                  int channels, double sampleRate)
{
    // De-interleave into ring buffer
    {
        std::lock_guard<std::mutex> lk(m_mutex);
        int cap = (int)m_ringL.size();
        for (int i = 0; i < frameCount; ++i) {
            m_ringL[m_writePos % cap] = interleaved[i * channels];
            m_ringR[m_writePos % cap] = (channels >= 2) ? interleaved[i * channels + 1]
                                                        : interleaved[i * channels];
            ++m_writePos;
        }
        // Take a snapshot of the latest kMilkDropSampleSize samples
        int readPos = m_writePos - kMilkDropSampleSize;
        for (int i = 0; i < kMilkDropSampleSize; ++i) {
            float l = m_ringL[(readPos + i + cap) % cap];
            float r = m_ringR[(readPos + i + cap) % cap];
            // Clamp to [-1,1] then map to [0,255]
            m_snapL[i] = (uint8_t)((std::clamp(l, -1.0f, 1.0f) * 0.5f + 0.5f) * 255.0f);
            m_snapR[i] = (uint8_t)((std::clamp(r, -1.0f, 1.0f) * 0.5f + 0.5f) * 255.0f);
        }
    }

    if (m_callback)
        m_callback(m_snapL, m_snapR, kMilkDropSampleSize);
}

void CoreAudioCapture::ResampleAndQuantise(const float* src, int srcCount,
                                            double srcRate,
                                            uint8_t* dst, int dstCount)
{
    double ratio = srcRate / 44100.0;
    for (int i = 0; i < dstCount; ++i) {
        double srcIdx = i * ratio;
        int    lo     = (int)srcIdx;
        double frac   = srcIdx - lo;
        float  v      = 0.0f;
        if (lo + 1 < srcCount)
            v = src[lo] * (1.0f - (float)frac) + src[lo+1] * (float)frac;
        else if (lo < srcCount)
            v = src[lo];
        dst[i] = (uint8_t)((std::clamp(v, -1.0f, 1.0f) * 0.5f + 0.5f) * 255.0f);
    }
}
