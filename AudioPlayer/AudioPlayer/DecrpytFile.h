//
//  DecrpytFile.h
//  AudioPlayer
//  基于命令行工具，揭秘DAT文件为原始PCM
//  Created by jinglin sun on 2021/3/16.
//  Copyright © 2021 Sun,Jinglin. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DecrpytFile : NSObject

+ (NSString *)decode:(NSString *)filePath error:(NSError **)error;
+ (NSString *)mapInputFileToDestinationFile:(NSString *)filePath byExtention:(NSString *)extention;
@end

NS_ASSUME_NONNULL_END
