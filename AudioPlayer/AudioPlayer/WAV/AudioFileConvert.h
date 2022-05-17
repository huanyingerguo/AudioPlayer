//
//  AudioFileConvert.h
//  AudioPlayer
//
//  Created by jinglin sun on 2021/7/21.
//  Copyright © 2021 Sun,Jinglin. All rights reserved.
//

#ifndef AudioFileConvert_h
#define AudioFileConvert_h

#include <stdio.h>
typedef unsigned long       DWORD;
typedef unsigned char       BYTE;
typedef unsigned short      WORD;

struct audio_FMT {
    WORD nChannleNumber;
    DWORD nSampleRate;
    WORD nBitsPerSample;
};

typedef struct audio_FMT audioFMT;

 
int a_law_pcm_to_wav(const char *pcm_file, const char *wav);
int a_law_pcm_to_wav2(const char *pcm_file, const char *wav, audioFMT pcmFmt);
#endif /* AudioFileConvert_h */
