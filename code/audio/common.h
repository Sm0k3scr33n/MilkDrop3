// common.h

#include <stdio.h>

#ifndef MILKDROP_MACOS
#include <windows.h>
#include <mmsystem.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mutex>

#include "log.h"
#include "cleanup.h"
#include "prefs.h"
#include "loopback-capture.h"
#include "audiobuf.h"
#else
// On macOS audio capture is handled by CoreAudioCapture.mm
#include <mutex>
#endif
