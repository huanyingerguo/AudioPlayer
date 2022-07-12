//
//  AudioPlayer.m
//  AudioPlayer
//
//  Created by sunjinglin on 2020/7/6.
//  Copyright © 2020 Sun,Jinglin. All rights reserved.
//

#import "AudioPlayer.h"
#include <CoreAudio/AudioHardware.h>
#import <AudioUnit/AudioUnit.h>
#import <AudioToolbox/AudioFile.h>
#import <AudioToolbox/AudioConverter.h>

#define kOutputBus 0
#define kInputBus 1
#define CONST_BUFFER_SIZE 0x10000
#define NO_MORE_DATA (-12306)

#define MAC_PLAT 1
#define E_NABLE_RECORD_CONVERT 0

#define BIT_DEPTH 16
#define SAMPLE_RATE 44100
#define CHANNEL_COUNT 1

// See:
// https://trac.webkit.org/browser/webkit/trunk/Source/WebCore/PAL/pal/spi/cf/CoreAudioSPI.h?rev=228264
OSStatus AudioDeviceDuck(AudioDeviceID inDevice,
                         Float32 inDuckedLevel,
                         const AudioTimeStamp* __nullable inStartTime,
                         Float32 inRampDuration) __attribute__((weak_import));

void UndoDucking(AudioDeviceID output_device_id) {
    if (AudioDeviceDuck != 0) {
        // Ramp the volume back up over half a second.
        AudioDeviceDuck(output_device_id, 1.0, NULL, 0.5);
    }
}

@interface AudioPlayer ()
{
    AudioUnit unit;
    UInt32 maximuFramePerPacket;
    AudioFileID audioFileID;
    AudioStreamBasicDescription sourceFileFormat;
    AudioStreamBasicDescription expectOutputFormat;
    AudioStreamBasicDescription sourceHADInputFormat;
    
    AudioStreamPacketDescription *audioFilePacketFormat;
    
    AudioBufferList *buffList;
    AudioBufferList *inOriginBufferList;
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
        self.bitDepth = BIT_DEPTH;
        self.channelCount = CHANNEL_COUNT;
        self.sampleRate = SAMPLE_RATE;
    }
    
    return self;
}

- (void)setBitDepth:(int)bitDepth {
    if (bitDepth > 0) {
        _bitDepth = bitDepth;
    } else {
        _bitDepth = BIT_DEPTH;
    }
}

- (void)setChannelCount:(int)channelCount {
    if (channelCount > 0) {
        _channelCount = channelCount;
    } else {
        _channelCount = CHANNEL_COUNT;
    }
}

- (void)setSampleRate:(int)sampleRate {
    if (sampleRate > 0) {
        _sampleRate = sampleRate;
    } else {
        _sampleRate = SAMPLE_RATE;
    }
}

- (void)prepareForPlayWork {
    [self prepareFileInfo];
    if (![self isFilePCMType:self.filePath]) {
        [self prepareAudioConverter];
        [self presetOutputFormatParameters];
    } else {
        [self prepareReadPCMFile];
    }
}


#pragma mark- Logic
- (void)setFilePath:(NSString *)filePath {
    if (![filePath isEqualToString:_filePath]) {
        _filePath = filePath;
        self.readedPacket = 0;
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
    
    UndoDucking(0);
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
    
    [self prepareForRecord];
    [self configAudioUnit:YES];
    
    OSStatus status;
    status = AudioUnitInitialize(unit);
    CheckError(status, "AudioUnit初始化失败");
    
    status = AudioOutputUnitStart(unit);
    CheckError(status, "audioUnit开始失败");
    self.isRecording = YES;
}

- (NSString *)getAudioStreamBasicDescriptionForInput {
    return [AudioPlayer audioStreamBasicDescription:sourceFileFormat];
}

- (NSString *)getAudioStreamBasicDescriptionForOutput {
    return [AudioPlayer audioStreamBasicDescription:expectOutputFormat];
}

#pragma mark- Private Method
- (void) prepareReadPCMFile {
    NSDictionary *fileInfo = [[NSFileManager defaultManager] attributesOfItemAtPath:self.filePath error:nil];
    self.packetNums = [fileInfo fileSize];
    
    self.readedPacket = 0;
}

- (void)prepareFileInfo {
    NSURL *fileURL = [NSURL fileURLWithPath:self.filePath];
    AudioFileOpenURL((__bridge CFURLRef)fileURL, kAudioFileReadPermission, 0, &audioFileID);
    
    uint32_t size = sizeof(AudioStreamBasicDescription);
    AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &sourceFileFormat);
    
    UInt32 packetCountSize = sizeof(_packetNums);
    AudioFileGetProperty(audioFileID, kAudioFilePropertyAudioDataPacketCount, &packetCountSize, &_packetNums);
    
    UInt32 framesize = sizeof(maximuFramePerPacket);
    AudioFileGetProperty(audioFileID, kAudioFilePropertyMaximumPacketSize, &framesize, &maximuFramePerPacket);
}

- (void)prepareAudioConverter {
    if (audioConverter) {
        AudioConverterDispose(audioConverter);
    }
    
    //对于转PCM的场景：位深 采样率 通道数固定。
    AudioStreamBasicDescription outputFormat = [self buildAudioStreamBasicDesc:16 sampleRate:48000 channelsPerFrame:1 framesPerPacket:1];
    OSStatus status = AudioConverterNew(&sourceFileFormat, &outputFormat, &audioConverter);
    CheckError(status, "AudioConverterNew failed");
    
    [self prepareBufferList];
    [self prepareConverBuffer];
    [self prepareFilePacketFormat];
}

- (void)presetOutputFormatParameters {
    self.bitDepth = BIT_DEPTH;
    self.channelCount = CHANNEL_COUNT;
    self.sampleRate = SAMPLE_RATE;
}

- (void)prepareForRecord {
#if E_NABLE_RECORD_CONVERT
    [self prepareAudioConverter];
#else
    [self prepareBufferList];
#endif
}

- (void)prepareBufferList {
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
    
    self->buffList = [[self class] allocAudioBufferListWithMDataByteSize:CONST_BUFFER_SIZE mNumberChannels:1 mNumberBuffers:1];
    
    if (self->inOriginBufferList) {
        for (int i = 0; i < self->buffList->mNumberBuffers; i++) {
            if (self->inOriginBufferList->mBuffers[0].mData) {
                free(self->inOriginBufferList->mBuffers[0].mData);
                self->inOriginBufferList->mBuffers[0].mData = NULL;
            }
        }
        free(self->inOriginBufferList);
        self->inOriginBufferList = nil;
    }
    
    self->inOriginBufferList = [[self class] allocAudioBufferListWithMDataByteSize:CONST_BUFFER_SIZE mNumberChannels:1 mNumberBuffers:1];
}

- (void)prepareConverBuffer {
    if (self->convertBuffer) {
        free(self->convertBuffer);
        self->convertBuffer = nil;
    }
    
    self->convertBuffer = malloc(CONST_BUFFER_SIZE);
}

- (void)prepareFilePacketFormat {
    if (self->audioFilePacketFormat) {
        free(self->audioFilePacketFormat);
        self->audioFilePacketFormat = nil;
    }
    
    self->audioFilePacketFormat = malloc(sizeof(AudioStreamPacketDescription) * (CONST_BUFFER_SIZE / maximuFramePerPacket + 1));
}

- (void)configAudioUnit:(BOOL)isEnableRecord {
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    if (isEnableRecord) {
        desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO; //录音专用
    } else {
        desc.componentSubType = kAudioUnitSubType_HALOutput; //普通无录音功能
    }
    
    /*
     #ifdef MAC_PLAT
     desc.componentSubType = kAudioUnitSubType_HALOutput; //mac 普通无录音功能
     #else
     desc.componentSubType = kAudioUnitSubType_RemoteIO; //ios 专用(录音)
     #endif
     */
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlagsMask = 0;
    desc.componentFlags = 0;
    
    AudioComponent outputComponent = AudioComponentFindNext(NULL, &desc);
    OSStatus status = AudioComponentInstanceNew(outputComponent, &unit);
    CheckError(status, "AudioComponentInstanceNew failed");
    
    if (isEnableRecord) {
        // get hardware device format
        UInt32 property_size = sizeof(AudioStreamBasicDescription);;
        status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input, kInputBus, &sourceHADInputFormat, &property_size);
        
        NSLog(@"打印输出：原始设备的输入流信息:*********");
        [[self class] audioStreamBasicDescription:sourceHADInputFormat];

        sourceHADInputFormat.mChannelsPerFrame = 1;
        sourceHADInputFormat.mSampleRate = 44100; // 参数不对的话，会导致命中： client-side input and output formats do not match (err=-10875)
        sourceHADInputFormat.mFormatID = kAudioFormatLinearPCM;
        sourceHADInputFormat.mFormatFlags =
            kAudioFormatFlagsNativeFloatPacked | kLinearPCMFormatFlagIsNonInterleaved;
        sourceHADInputFormat.mBitsPerChannel = sizeof(Float32) * 8;
        sourceHADInputFormat.mBytesPerFrame = sourceHADInputFormat.mBitsPerChannel * sourceHADInputFormat.mChannelsPerFrame / 8;
        sourceHADInputFormat.mFramesPerPacket = 1;
        sourceHADInputFormat.mBytesPerPacket = sourceHADInputFormat.mBytesPerFrame;
        
        NSLog(@"打印输出：修改之后的输入流信息:*********");
        [[self class] audioStreamBasicDescription:sourceHADInputFormat];

        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, &sourceHADInputFormat, sizeof(sourceHADInputFormat));
        CheckError(status, "kAudioUnitProperty_StreamFormat failed");
        
        //启动录制
        UInt32 flagIn = 1;
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &flagIn, sizeof(flagIn));
        CheckError(status, "kAudioOutputUnitProperty_EnableIO failed");
#if 1
        const UInt32 one = 1;
        const UInt32 zero = 0;

        status = AudioUnitSetProperty(unit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, kInputBus, &one, sizeof(zero));
        CheckError(status, "kAUVoiceIOProperty_BypassVoiceProcessing failed");
        
        status = AudioUnitSetProperty(unit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, kInputBus, &one, sizeof(zero));
        CheckError(status, "kAUVoiceIOProperty_VoiceProcessingEnableAGC failed");

//        status = AudioUnitSetProperty(unit, kAUVoiceIOProperty_MuteOutput, kAudioUnitScope_Global, kInputBus, &zero, sizeof(zero));
//        CheckError(status, "kAUVoiceIOProperty_MuteOutput failed");
#endif

        //设置声音录制回调
        AURenderCallbackStruct recordCallback;
        recordCallback.inputProc = RecordCallback;
        recordCallback.inputProcRefCon = (__bridge void *)self;
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, kInputBus, &recordCallback, sizeof(recordCallback));
        CheckError(status, "kAudioOutputUnitProperty_SetInputCallback failed");
    } else {
        //设置输入流格式
        expectOutputFormat = [self buildAudioStreamBasicDesc:self.bitDepth sampleRate:self.sampleRate channelsPerFrame:self.channelCount framesPerPacket:1];
        
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &expectOutputFormat, sizeof(expectOutputFormat));
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

- (BOOL)isFilePCMType:(NSString *)filePath {
    NSString *type = [[filePath lastPathComponent] pathExtension];
    if ([type isEqualToString:@"pcm"]) {
        return YES;
    }
    
    return NO;
}

#pragma mark- Statistic Method
static void CheckError(OSStatus error, const char *operation)
{
#if MAC
    CheckStatus(error, [NSString stringWithCString:operation encoding:NSUTF8StringEncoding], YES);
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
    AudioPlayer *player = (__bridge AudioPlayer *)inRefCon;
    player->inOriginBufferList->mBuffers[0].mDataByteSize = inNumberFrames * sizeof(Float32);
    
    UInt32 frames = player->sourceHADInputFormat.mSampleRate / 1000.0;

    OSStatus status = AudioUnitRender(player->unit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, player->inOriginBufferList);
    
    CheckError(status, "RecordCallback failed");
    if (status != noErr) {
        return status;
    }
    

    //必须进行格式转化：默认输入float32.我们的设置输出则是16Integer
    Float32  *srcPtr = (Float32  *)player->inOriginBufferList->mBuffers[0].mData;
    int16_t  *destPtr = (int16_t  *)player->buffList->mBuffers[0].mData;
    for (int i = 0; i < inNumberFrames; i++) {
        if(srcPtr[i] > 1.0 || srcPtr[i] < -1.0) {
            srcPtr[i] = srcPtr[i] > 0 ? 1.0 : -1.0;
        }
        destPtr[i]= (int16_t)(srcPtr[i] * 32767);
    }

    NSLog(@"Record Size = %d", player->buffList->mBuffers[0].mDataByteSize);
    [player writePCMData:player->buffList->mBuffers[0].mData size:inNumberFrames * sizeof(int16_t)];
    
    return status;
}

static OSStatus inputCallbackFun(    void *                            inRefCon,
                                 AudioUnitRenderActionFlags *    ioActionFlags,
                                 const AudioTimeStamp *            inTimeStamp,
                                 UInt32                            inBusNumber,
                                 UInt32                            inNumberFrames,
                                 AudioBufferList * __nullable    ioData) {
    memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
    AudioPlayer *player = (__bridge AudioPlayer *)inRefCon;
    if ([player isFilePCMType:player.filePath]) {
        if (player.readedPacket < player.packetNums) {
            NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:player.filePath];
            NSInteger bytes = CONST_BUFFER_SIZE < ioData->mBuffers[0].mDataByteSize ? CONST_BUFFER_SIZE : ioData->mBuffers[0].mDataByteSize;
            [handle seekToFileOffset:player.readedPacket];
            NSData *data = [handle readDataOfLength:bytes];
            bytes = [data length];
            memcpy(ioData->mBuffers[0].mData, [data bytes], ioData->mBuffers[0].mDataByteSize);
            
            player.readedPacket += bytes;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (player.playProgress) {
                    player.playProgress(player.readedPacket, (player.readedPacket * 1.0f / player.packetNums) * 100);
                }
            });
            return noErr;
        } else { //延迟防止过早关闭，导致crash
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                NSLog(@"文件读取结束：filePath=%@", player.filePath);
                [player pause];
            });
            return -1;
        }
        
        return 0;
    }
    
    if (!player->buffList) {
        return -1;
    }
    
    if (player.isPlaying) {
        player->buffList->mBuffers[0].mDataByteSize = CONST_BUFFER_SIZE;
        
        OSStatus status = AudioConverterFillComplexBuffer(player->audioConverter, lyInInputDataProc, (__bridge void * _Nullable)(player), &inNumberFrames, player->buffList, NULL);
        if (status) {
            CheckError(status, "inputCallbackFun failed");
            return status;
        }
        
        memcpy(ioData->mBuffers[0].mData, player->buffList->mBuffers[0].mData, player->buffList->mBuffers[0].mDataByteSize);
        ioData->mBuffers[0].mDataByteSize = player->buffList->mBuffers[0].mDataByteSize;
    } else {
        if (player->buffList->mBuffers[0].mDataByteSize > 1000) {
            memcpy(ioData->mBuffers[0].mData, player->buffList->mBuffers[0].mData, player->buffList->mBuffers[0].mDataByteSize);
            ioData->mBuffers[0].mDataByteSize = player->buffList->mBuffers[0].mDataByteSize;
        }
    }
    
    return noErr;
}

OSStatus lyInInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AudioPlayer *player = (__bridge AudioPlayer *)(inUserData);
    
    UInt32 byteSize = CONST_BUFFER_SIZE;
    OSStatus status = AudioFileReadPacketData(player->audioFileID, NO, &byteSize, player->audioFilePacketFormat, player.readedPacket, ioNumberDataPackets, player->convertBuffer);
    
    if (outDataPacketDescription) { // 这里要设置好packetFormat，否则会转码失败
        *outDataPacketDescription = player->audioFilePacketFormat;
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
