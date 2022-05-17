//
//  AudioPlayer.h
//  AudioPlayer
//
//  Created by sunjinglin on 2020/7/6.
//  Copyright © 2020 Sun,Jinglin. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// readPacker: 读取的包数目
// progress:杜去的进度（如50%）
typedef void (^PlayProgress)(long long readPacker, float progress);

@interface AudioPlayer : NSObject
+ (instancetype)sharedInstance;
@property (copy) PlayProgress playProgress; //播放进度
@property (copy, nonatomic) NSString *filePath;
@property (copy, nonatomic) NSString *recordPath;
@property (assign) SInt64 readedPacket; // 已读的packet数量
@property (assign) SInt64 packetNums; // 全部packet数量
@property (assign) BOOL isRecording;
@property (assign) BOOL isPlaying;

@property (nonatomic, assign) int sampleRate;
@property (nonatomic, assign) int bitDepth;
@property (nonatomic, assign) int channelCount;

- (NSString *)getAudioStreamBasicDescriptionForInput;
- (NSString *)getAudioStreamBasicDescriptionForOutput;
- (void)play:(NSString *)filePath;
- (void)record:(NSString *)filePath;
- (void)pause;

- (BOOL)isFilePCMType:(NSString *)filePath;
@end

NS_ASSUME_NONNULL_END
