/**
 * CoreAudioCapture.h
 *
 * macOS system audio loopback capture — replaces the Windows WASAPI loopback
 * in code/audio/loopback-capture.cpp.
 *
 * macOS does not expose a public system-audio loopback API before macOS 13.
 * We support two modes:
 *
 *   1. ScreenCaptureKit (macOS 13+, Ventura and later)
 *      Uses SCStreamConfiguration with capturesSampleBuffer = YES to grab the
 *      system mix as PCM.  This is the preferred path.
 *
 *   2. AggregateDevice / virtual audio device fallback (macOS 12 and earlier)
 *      Instructs the user to install BlackHole or Soundflower and select it as
 *      the input device.  The capture then uses AudioUnit (kAudioUnitType_IO)
 *      to read from that input.
 *
 * In both cases the callback delivers interleaved float32 stereo PCM at the
 * native sample rate (typically 44100 or 48000 Hz).  The data is resampled
 * to 44100 and converted to the unsigned 8-bit format that MilkDrop expects
 * (pcmLeftOut / pcmRightOut arrays of SAMPLE_SIZE=576 bytes each).
 */

#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#endif

#include <functional>
#include <atomic>
#include <vector>
#include <mutex>
#include <cstdint>

// Number of PCM samples MilkDrop reads per frame (matches plugin.cpp SAMPLE_SIZE).
static constexpr int kMilkDropSampleSize = 576;

// Callback fired on the audio thread with fresh PCM data.
// left/right are arrays of kMilkDropSampleSize unsigned bytes (0-255).
using AudioCallback = std::function<void(const uint8_t* left,
                                         const uint8_t* right,
                                         int sampleCount)>;

class CoreAudioCapture {
public:
    CoreAudioCapture();
    ~CoreAudioCapture();

    // Start capturing. Returns true on success.
    // On macOS 13+ attempts ScreenCaptureKit; falls back to AudioUnit input.
    bool Start(AudioCallback cb);
    void Stop();

    bool IsRunning() const { return m_running.load(); }

    // Fill MilkDrop-style PCM buffers (called from the render thread if needed).
    // Copies the most recently captured data into dst_left / dst_right.
    void GetLatestPCM(uint8_t* dst_left, uint8_t* dst_right, int count);

private:
    AudioCallback       m_callback;
    std::atomic<bool>   m_running { false };

    // Double-buffered PCM ring buffer
    std::mutex          m_mutex;
    std::vector<float>  m_ringL;
    std::vector<float>  m_ringR;
    int                 m_writePos = 0;

    // Latest snap (filled by audio thread, read by render thread)
    uint8_t m_snapL[kMilkDropSampleSize] = {};
    uint8_t m_snapR[kMilkDropSampleSize] = {};

    // ── ScreenCaptureKit path ─────────────────────────────────────────────────
#ifdef __OBJC__
    id m_scStream;    // SCStream*
    id m_scDelegate;  // id<SCStreamOutput>
    bool StartSCK();
    void StopSCK();
#endif

    // ── AudioUnit / input device path ────────────────────────────────────────
    void* m_audioUnit = nullptr;  // AudioUnit (opaque to non-ObjC headers)
    bool  StartAudioUnit();
    void  StopAudioUnit();

    // Called from audio callbacks with interleaved float32 stereo samples.
    void OnSamples(const float* interleaved, int frameCount, int channels,
                   double sampleRate);

    // Resample from arbitrary rate to 44100 and quantise to uint8.
    static void ResampleAndQuantise(const float* src, int srcCount,
                                    double srcRate,
                                    uint8_t* dst, int dstCount);
};
