//
//  AudioPlayer.m
//  AudioPlayer
//
//  Created by sunjinglin on 2020/7/6.
//  Copyright © 2020 Sun,Jinglin. All rights reserved.
//

#import "AudioPlayer.h"
#import <AudioUnit/AudioUnit.h>
#import <AudioToolbox/AudioFile.h>
#import <AudioToolbox/AudioConverter.h>

#define kOutputBus 0
#define kInputBus 1
#define CONST_BUFFER_SIZE 0x10000
#define NO_MORE_DATA (-12306)

#define MAC_PLAT 1


@interface AudioPlayer ()
{
    AudioUnit unit;
    UInt32 maximuFramePerPacket;
    AudioFileID audioFileID;
    AudioStreamBasicDescription audioFileFormat;
    AudioStreamBasicDescription audioOutputFormat;
    AudioStreamPacketDescription *audioPacketFormat;
    
    AudioBufferList *buffList;
    Byte *convertBuffer;
    
    AudioConverterRef audioConverter;
};

@end

@implementation AudioPlayer

+ (instancetype)sharedInstance {
    static AudioPlayer *obj;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        obj = [[self alloc] init];
    });
    
    return obj;
}


- (instancetype) init {
    self = [super init];
    if (self) {
        self.readedPacket = 0;
    }
    
    return self;
}

- (void)prepareForPlayWork {
    [self prepareFileInfo];
    [self prepareAudioConverter];
    [self prepareForPlay];
}


#pragma mark- Logic
- (void)setFilePath:(NSString *)filePath {
    if (![filePath isEqualToString:_filePath]) {
        _filePath = filePath;
        [self prepareForPlayWork];
    }
}

- (void)play {
    if (self.isPlaying ||
        self.isRecording) {
        self.readedPacket = 0;
        [self pause];
    }
    
    [self configAudioUnit:NO];
    
    OSStatus status;
    status = AudioUnitInitialize(unit);
    CheckError(status, "AudioUnit初始化失败");
    
    status = AudioOutputUnitStart(unit);
    CheckError(status, "audioUnit开始失败");
    self.isPlaying = YES;
}

- (void)pause {
    OSStatus status;
    status = AudioOutputUnitStop(unit);
    CheckError(status, "audioUnit停止失败");
    
    status = AudioUnitUninitialize(unit);
    CheckError(status, "AudioUnits取消初始化失败");
    
    status = AudioComponentInstanceDispose(unit);
    CheckError(status, "audioUnit释放失败");
    self.isPlaying = NO;
    self.isRecording = NO;
}

- (void)record {
    if (self.isPlaying ||
        self.isRecording) {
        [self pause];
    }
    
    [self configAudioUnit:YES];
    
    OSStatus status;
    status = AudioUnitInitialize(unit);
    CheckError(status, "AudioUnit初始化失败");
    
    status = AudioOutputUnitStart(unit);
    CheckError(status, "audioUnit开始失败");
    self.isRecording = YES;
}

- (NSString *)getAudioStreamBasicDescriptionForInput {
    return [AudioPlayer audioStreamBasicDescription:audioFileFormat];
}

- (NSString *)getAudioStreamBasicDescriptionForOutput {
    return [AudioPlayer audioStreamBasicDescription:audioOutputFormat];
}

#pragma mark- Private Method
- (void)prepareFileInfo {
    NSURL *fileURL = [NSURL fileURLWithPath:self.filePath];
    AudioFileOpenURL((__bridge CFURLRef)fileURL, kAudioFileReadPermission, 0, &audioFileID);
    
    
    uint32_t size = sizeof(AudioStreamBasicDescription);
    AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &audioFileFormat);
    
    UInt32 packetCountSize = sizeof(_packetNums);
    AudioFileGetProperty(audioFileID, kAudioFilePropertyAudioDataPacketCount, &packetCountSize, &_packetNums);
    
    UInt32 framesize = sizeof(maximuFramePerPacket);
    AudioFileGetProperty(audioFileID, kAudioFilePropertyMaximumPacketSize, &framesize, &maximuFramePerPacket);
}

- (void)prepareAudioConverter {
    if (audioConverter) {
        AudioConverterDispose(audioConverter);
    }
    
    AudioStreamBasicDescription outputFormat = [self buildAudioStreamBasicDesc:32 sampleRate:44100 channelsPerFrame:1 framesPerPacket:1];
    
    OSStatus status = AudioConverterNew(&audioFileFormat, &outputFormat, &audioConverter);
    CheckError(status, "AudioConverterNew failed");
}

- (void)prepareForPlay {
    if (self->audioPacketFormat) {
        free(self->audioPacketFormat);
        self->audioPacketFormat = nil;
    }
    
    if (self->buffList) {
        for (int i = 0; i < self->buffList->mNumberBuffers; i++) {
            if (self->buffList->mBuffers[0].mData) {
                free(self->buffList->mBuffers[0].mData);
                self->buffList->mBuffers[0].mData = NULL;
            }
        }
        free(self->buffList);
        self->buffList = nil;
    }
    
    if (self->convertBuffer) {
        free(self->convertBuffer);
        self->convertBuffer = nil;
    }
    
    self->audioPacketFormat = malloc(sizeof(AudioStreamPacketDescription) * (CONST_BUFFER_SIZE / maximuFramePerPacket + 1));
    
    self->buffList = [[self class] allocAudioBufferListWithMDataByteSize:CONST_BUFFER_SIZE mNumberChannels:1 mNumberBuffers:1];
    
    self->convertBuffer = malloc(CONST_BUFFER_SIZE);
}


- (void)configAudioUnit:(BOOL)isEnableRecord {
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    if (isEnableRecord) {
        desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO; //录音专用
    } else {
        desc.componentSubType = kAudioUnitSubType_HALOutput;
    }
    
    /*
     #ifdef MAC_PLAT
     desc.componentSubType = kAudioUnitSubType_HALOutput; //mac专用
     #else
     desc.componentSubType = kAudioUnitSubType_RemoteIO; //ios 专用
     #endif
     */
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlagsMask = 0;
    desc.componentFlags = 0;
    
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &desc);
    OSStatus status = AudioComponentInstanceNew(outputComponent, &unit);
    CheckError(status, "AudioComponentInstanceNew failed");
    
    //设置输入流格式
    audioOutputFormat = [self buildAudioStreamBasicDesc:32 sampleRate:44100 channelsPerFrame:1 framesPerPacket:1];
    
    if (isEnableRecord) {
        //启动录制
        UInt32 flagIn = 1;
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &flagIn, sizeof(flagIn));
      
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, &audioOutputFormat, sizeof(audioOutputFormat));
        CheckError(status, "kAudioUnitProperty_StreamFormat failed");
        
        //设置声音录制回调
        AURenderCallbackStruct recordCallback;
        recordCallback.inputProc = RecordCallback;
        recordCallback.inputProcRefCon = (__bridge void *)self;
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, kInputBus, &recordCallback, sizeof(recordCallback));
        CheckError(status, "kAudioOutputUnitProperty_SetInputCallback failed");
    } else {
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &audioOutputFormat, sizeof(audioOutputFormat));
        CheckError(status, "kAudioUnitProperty_StreamFormat failed");
        
        //设置声音输入回掉
        AURenderCallbackStruct renderCallback;
        renderCallback.inputProc = inputCallbackFun;
        renderCallback.inputProcRefCon = (__bridge void *)self;
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, kOutputBus, &renderCallback, sizeof(renderCallback));
        CheckError(status, "kAudioUnitProperty_SetRenderCallback failed");
    }
}

- (AudioStreamBasicDescription)buildAudioStreamBasicDesc:(UInt32)mBitsPerChannel sampleRate:(UInt32)sampleRate channelsPerFrame:(UInt32)channelsPerFrame framesPerPacket:(UInt32)framesPerPacket {
    AudioStreamBasicDescription asbdInfo;
    asbdInfo.mSampleRate = sampleRate;
    asbdInfo.mFormatID = kAudioFormatLinearPCM;
    asbdInfo.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsNonInterleaved;
    asbdInfo.mFramesPerPacket = framesPerPacket;
    asbdInfo.mChannelsPerFrame = channelsPerFrame;
    asbdInfo.mBitsPerChannel = mBitsPerChannel;
    asbdInfo.mBytesPerFrame = asbdInfo.mBitsPerChannel / 8 * asbdInfo.mChannelsPerFrame;
    asbdInfo.mBytesPerPacket = asbdInfo.mBytesPerFrame * asbdInfo.mFramesPerPacket;
    
    return asbdInfo;
}

- (void)writePCMData:(Byte *)buffer size:(int)size {
    static FILE *file = NULL;
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    path = [path stringByAppendingString:@"/record.pcm"];
    if(![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        BOOL res = [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        if (!res) {
            NSLog(@"创建文件失败：path=%@", path);
        }
    }
    
    if (!file) {
        file = fopen(path.UTF8String, "w");
    }
    
    fwrite(buffer, size, 1, file);
}

#pragma mark- Statistic Method
static void CheckError(OSStatus error, const char *operation)
{
#if MAC
    CheckStatus(error, [NSString stringWithCString:operation encoding:NSUTF8StringEncoding], NO);
#else
    if (error == noErr) return;
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    }
    
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
#endif
}

//check func
static void CheckStatus(OSStatus status, NSString *message, BOOL fatal) {
    if (status != noErr) {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        if (isprint(fourCC[0]) && isprint(fourCC[1]) &&
            isprint(fourCC[2]) && isprint(fourCC[4])) {
            NSLog(@"%@:%s",message, fourCC);
        } else {
            NSLog(@"%@:%d",message, (int)status);
        }
        
        if (fatal) {
            exit(-1);
        }
    }
}

#pragma mark- Callback Method
static OSStatus RecordCallback(    void *                            inRefCon,
                                  AudioUnitRenderActionFlags *    ioActionFlags,
                                  const AudioTimeStamp *            inTimeStamp,
                                  UInt32                            inBusNumber,
                                  UInt32                            inNumberFrames,
                                  AudioBufferList * __nullable    ioData) {
    AudioPlayer *strongSelf = (__bridge AudioPlayer *)inRefCon;
    OSStatus status = AudioUnitRender(strongSelf->unit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, strongSelf->buffList);
    
    CheckError(status, "outputCallbackFun failed");
    
    NSLog(@"Record Size = %d", strongSelf->buffList->mBuffers[0].mDataByteSize);
    [strongSelf writePCMData:strongSelf->buffList->mBuffers[0].mData size:strongSelf->buffList->mBuffers[0].mDataByteSize];
    
    return status;
}

static OSStatus inputCallbackFun(    void *                            inRefCon,
                                 AudioUnitRenderActionFlags *    ioActionFlags,
                                 const AudioTimeStamp *            inTimeStamp,
                                 UInt32                            inBusNumber,
                                 UInt32                            inNumberFrames,
                                 AudioBufferList * __nullable    ioData) {
    memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
    
    
    AudioPlayer *strongSelf = (__bridge AudioPlayer *)inRefCon;
    if (strongSelf.isPlaying) {
        strongSelf->buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE;
        
        OSStatus status = AudioConverterFillComplexBuffer(strongSelf->audioConverter, lyInInputDataProc, (__bridge void * _Nullable)(strongSelf), &inNumberFrames, strongSelf->buffList, NULL);
        if (status) {
            CheckError(status, "inputCallbackFun failed");
            return status;
        }
        
        memcpy(ioData->mBuffers[0].mData, strongSelf->buffList->mBuffers[0].mData, strongSelf->buffList->mBuffers[0].mDataByteSize);
        ioData->mBuffers[0].mDataByteSize = strongSelf->buffList->mBuffers[0].mDataByteSize;
    } else {
        if (strongSelf->buffList->mBuffers[0].mDataByteSize > 1000) {
            memcpy(ioData->mBuffers[0].mData, strongSelf->buffList->mBuffers[0].mData, strongSelf->buffList->mBuffers[0].mDataByteSize);
            ioData->mBuffers[0].mDataByteSize = strongSelf->buffList->mBuffers[0].mDataByteSize;
        }
    }
    
    return noErr;
}

OSStatus lyInInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AudioPlayer *player = (__bridge AudioPlayer *)(inUserData);
    
    UInt32 byteSize = CONST_BUFFER_SIZE;
    OSStatus status = AudioFileReadPacketData(player->audioFileID, NO, &byteSize, player->audioPacketFormat, player.readedPacket, ioNumberDataPackets, player->convertBuffer);
    
    if (outDataPacketDescription) { // 这里要设置好packetFormat，否则会转码失败
        *outDataPacketDescription = player->audioPacketFormat;
    }
    CheckError(status, "读取文件失败");
    
    if (!status && ioNumberDataPackets > 0) {
        ioData->mBuffers[0].mDataByteSize = byteSize;
        ioData->mBuffers[0].mData = player->convertBuffer;
        player.readedPacket += *ioNumberDataPackets;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (player.playProgress) {
                player.playProgress(player.readedPacket, (player.readedPacket * 1.0f / player->_packetNums) * 100);
            }
        });
        return noErr;
    }
    else {
        player.readedPacket = 0;
        return NO_MORE_DATA;
    }
    
}

#pragma mark- Static Util Method
+ (NSString *)audioStreamBasicDescription:(AudioStreamBasicDescription)asbd {
    char formatID[5];
    UInt32 mFormatID = CFSwapInt32HostToBig(asbd.mFormatID);
    bcopy (&mFormatID, formatID, 4);
    formatID[4] = '\0';
    
    printf("Sample Rate:         %10.0f\n",  asbd.mSampleRate);
    printf("Format ID:           %10s\n",    formatID);
    printf("Format Flags:        %10X\n",    (unsigned int)asbd.mFormatFlags);
    printf("Bytes per Packet:    %10d\n",    (unsigned int)asbd.mBytesPerPacket);
    printf("Frames per Packet:   %10d\n",    (unsigned int)asbd.mFramesPerPacket);
    printf("Bytes per Frame:     %10d\n",    (unsigned int)asbd.mBytesPerFrame);
    printf("Channels per Frame:  %10d\n",    (unsigned int)asbd.mChannelsPerFrame);
    printf("Bits per Channel:    %10d\n",    (unsigned int)asbd.mBitsPerChannel);
    printf("\n");
    
    return [NSString stringWithFormat:@"Sample Rate:         %10.0f,\n\
                     Format ID（音频格式）:           %10s \n\
                     Format Flags（音频标签）:        %10X \n\
                     Bytes per Packet（单位数据包的字节数）:    %10d \n\
                     Frames per Packet（单位数据包的帧数）:   %10d \n\
                     Bytes per Frame（单位帧的字节）:     %10d  \n\
                     Channels per Frame（单位帧的声道-声道数）:  %10d  \n\
                     Bits per Channel（单位道的字节，位数）:    %10d",
                     asbd.mSampleRate,
                     formatID,
                     (unsigned int)asbd.mFormatFlags,
                     (unsigned int)asbd.mBytesPerPacket,
                     (unsigned int)asbd.mFramesPerPacket,
                     (unsigned int)asbd.mBytesPerFrame,
                     (unsigned int)asbd.mChannelsPerFrame,
                     (unsigned int)asbd.mBitsPerChannel];
}

/**
 创建AudioBufferList
 mDataByteSize ：AudioBuffer.mData （是一个Byte *数组） 数组长度
 mNumberChannels ：声道数
 mNumberBuffers ：AudioBuffer（mBuffers[1]） 数组的元素个数
 */
+ (AudioBufferList *)allocAudioBufferListWithMDataByteSize:(UInt32)mDataByteSize mNumberChannels:(UInt32)mNumberChannels mNumberBuffers:(UInt32)mNumberBuffers
{
    AudioBufferList *_bufferList;
    _bufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    _bufferList->mNumberBuffers = 1;
    _bufferList->mBuffers[0].mData = malloc(mDataByteSize);
    _bufferList->mBuffers[0].mDataByteSize = mDataByteSize;
    _bufferList->mBuffers[0].mNumberChannels = 1;
    return _bufferList;
}

@end
