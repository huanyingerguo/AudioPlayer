//
//  AudioFileConvert.c
//  AudioPlayer
//
//  Created by jinglin sun on 2021/7/21.
//  Copyright © 2021 Sun,Jinglin. All rights reserved.
//

#include "AudioFileConvert.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

using namespace std;

struct tagHXD_WAVFLIEHEAD
{
    char RIFFNAME[4];
    DWORD nRIFFLength;
    char WAVNAME[4];
    char FMTNAME[4];
    DWORD nFMTLength;
    WORD nAudioFormat;
    
    WORD nChannleNumber;
    DWORD nSampleRate;
    DWORD nBytesPerSecond;
    WORD nBytesPerSample;
    WORD    nBitsPerSample;
    char    DATANAME[4];
    DWORD   nDataLength;
};

typedef struct tagHXD_WAVFLIEHEAD HXD_WAVFLIEHEAD;
 
int a_law_pcm_to_wav(const char *pcm_file, const char *wav)
{
    // 开始准备WAV的文件头
    HXD_WAVFLIEHEAD DestionFileHeader;
    DestionFileHeader.RIFFNAME[0] = 'R';
    DestionFileHeader.RIFFNAME[1] = 'I';
    DestionFileHeader.RIFFNAME[2] = 'F';
    DestionFileHeader.RIFFNAME[3] = 'F';
    
    DestionFileHeader.WAVNAME[0] = 'W';
    DestionFileHeader.WAVNAME[1] = 'A';
    DestionFileHeader.WAVNAME[2] = 'V';
    DestionFileHeader.WAVNAME[3] = 'E';
    
    DestionFileHeader.FMTNAME[0] = 'f';
    DestionFileHeader.FMTNAME[1] = 'm';
    DestionFileHeader.FMTNAME[2] = 't';
    DestionFileHeader.FMTNAME[3] = 0x20;
    DestionFileHeader.nFMTLength = 16;  //  表示 FMT 的长度
    DestionFileHeader.nAudioFormat = 6; //这个表示a law PCM
    
    DestionFileHeader.DATANAME[0] = 'd';
    DestionFileHeader.DATANAME[1] = 'a';
    DestionFileHeader.DATANAME[2] = 't';
    DestionFileHeader.DATANAME[3] = 'a';
    DestionFileHeader.nBitsPerSample = 8;
    DestionFileHeader.nBytesPerSample = 1;    //
    DestionFileHeader.nSampleRate = 8000;    //
    DestionFileHeader.nBytesPerSecond = 8000;
    DestionFileHeader.nChannleNumber = 1;
    
    // 文件头的基本部分
    int nFileLen = 0;
    int nSize = sizeof(DestionFileHeader);
    
    FILE *fp_s = NULL;
    FILE *fp_d = NULL;
    
    fp_s = fopen(pcm_file, "rb");
    if (fp_s == NULL)
        return -1;
    
    fp_d = fopen(wav, "wb+");
    if (fp_d == NULL)
        return -2;
    
    
    int nWrite = fwrite(&DestionFileHeader, 1, nSize, fp_d);     //将文件头写入wav文件
    if (nWrite != nSize)
    {
        fclose(fp_s);
        fclose(fp_d);
        return -3;
    }
    
    while( !feof(fp_s))
    {
        char readBuf[4096];
        int nRead = fread(readBuf, 1, 4096, fp_s);    //将pcm文件读到readBuf
        if (nRead > 0)
        {
            fwrite(readBuf, 1, nRead, fp_d);      //将readBuf文件的数据写到wav文件
        }
        
        nFileLen += nRead;
    }
    fseek(fp_d, 0L, SEEK_SET);   //将读写位置移动到文件开头
    
    DestionFileHeader.nRIFFLength = nFileLen - 8 + nSize;
    DestionFileHeader.nDataLength = nFileLen;
    nWrite = fwrite(&DestionFileHeader, 1, nSize, fp_d);   //重新将文件头写入到wav文件
    if (nWrite != nSize)
    {
        fclose(fp_s);
        fclose(fp_d);
        return -4;
    }
    
    fclose(fp_s);
    fclose(fp_d);
    
    return nFileLen;
}

//读文件，返回内存指针，记得free
void* ReadFile(const char *path, unsigned int *len)
{
    FILE *f = fopen(path, "rb");
    if (f == NULL)
        return NULL;
    fseek(f, 0, SEEK_END);
    *len = ftell(f);
    fseek(f, 0, SEEK_SET);
    void *buffer = malloc(*len);
    *len = fread(buffer, 1, *len, f);
    fclose(f);
    return buffer;
}


//pcm转wav，返回wav内存指针和wav长度
void* pcmToWav(const void *pcm, unsigned int pcmlen, unsigned int *wavlen, audioFMT pcmFmt){
    //44字节wav头
    void *wav = malloc(pcmlen + 44);
    //wav文件多了44个字节
    *wavlen = pcmlen + 44;
    //添加wav文件头
    memcpy(wav, "RIFF", 4);
    *(int *)((char*)wav + 4) = pcmlen + 36;
    memcpy(((char*)wav + 8), "WAVEfmt ", 8);
    *(int *)((char*)wav + 16) = 16;
    *(short *)((char*)wav + 20) = 1;
    *(short *)((char*)wav + 22) = pcmFmt.nChannleNumber;
    *(int *)((char*)wav + 24) = pcmFmt.nSampleRate;
    *(int *)((char*)wav + 28) = pcmFmt.nChannleNumber * pcmFmt.nSampleRate * pcmFmt.nBitsPerSample / 8;
    *(short *)((char*)wav + 32) = pcmFmt.nBitsPerSample / 8;
    *(short *)((char*)wav + 34) = pcmFmt.nBitsPerSample;
    strcpy((char*)((char*)wav + 36), "data");
    *(int *)((char*)wav + 40) = pcmlen;
 
    //拷贝pcm数据到wav中
    memcpy((char*)wav + 44, pcm, pcmlen);
    return wav;
}

//pcm文件转wav文件，pcmfilePath:pcm文件路劲，wavfilePath:生成的wav路劲
int pcmfileToWavfile(const char *pcmfilePath, const char *wavfilePath, audioFMT pcmFmt)
{
    unsigned int pcmlen;
    //读取文件获得pcm流，也可以从其他方式获得
    void *pcm = ReadFile(pcmfilePath, &pcmlen);
    if (pcm == NULL)
    {
        printf("not found file\n");
        return 1;
    }
 
    //pcm转wav
    unsigned int wavLen;
    void *wav = pcmToWav(pcm, pcmlen, &wavLen, pcmFmt);
 
    FILE *fwav = fopen(wavfilePath, "wb");
    fwrite(wav, 1, wavLen, fwav);
    fclose(fwav);
    free(pcm);
    free(wav);
    return 0;
}

int a_law_pcm_to_wav2(const char *pcm_file, const char *wav, audioFMT pcmFmt)
{
    return pcmfileToWavfile(pcm_file, wav, pcmFmt);
}

