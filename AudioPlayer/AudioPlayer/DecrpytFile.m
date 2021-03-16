//
//  DecrpytFile.m
//  AudioPlayer
//
//  Created by jinglin sun on 2021/3/16.
//  Copyright © 2021 Sun,Jinglin. All rights reserved.
//

#import "DecrpytFile.h"

@implementation DecrpytFile

+ (NSString *)decode:(NSString *)filePath error:(NSError **)error {
    NSString *crypt_tool = [[NSBundle mainBundle] pathForResource:@"crypt_tool" ofType:nil];
    
    NSString *inputFilePath = [filePath stringByDeletingLastPathComponent];
    NSString *inputFileName = [[filePath lastPathComponent] stringByDeletingPathExtension];
    
    //截取信息
    NSArray *nameArray = [inputFileName componentsSeparatedByString:@"_"];
    if (nameArray.count < 8) {
        NSError *err = [NSError errorWithDomain:@"fileName is illeagea, expect 8 components" code:-1 userInfo:@{@"fileName": inputFileName ?: @"", @"info" :@"fileName is illeagea, expect 8 components"}];
        *error = err;
        return @"fileName is illeagea, expect 8 components";
    }
    NSString *sample = [nameArray objectAtIndex:5];
    NSString *key = [nameArray lastObject];
    
    NSString *outputFileName = [inputFileName stringByAppendingString:@".pcm"];
    NSString *outputFilepath = [inputFilePath stringByAppendingPathComponent:outputFileName];
    
    NSString *script = [NSString stringWithFormat:@"%@ -input=%@ -output=%@ -sample=%@ -key=%@",
                        crypt_tool,
                        filePath,
                        outputFilepath,
                        sample,
                        key];
    NSLog(@"开始揭秘: \r\n cmd=%@", script);
    NSString *output = [[self class] runShellScript:script];
    if ([output containsString:@"error"]) {
        *error = [NSError errorWithDomain:output code:-2 userInfo:@{@"info": output ?: @""}];
    }
    NSLog(@"结束揭秘: \r\n output=%@", output);
    return outputFilepath;;
}

/**
 *运行shell脚本
 */
+ (NSString *)runShellScript:(NSString *)cmd
{
    NSTask *task;
    task = [[NSTask alloc] init];
    task.launchPath = @"/bin/sh";
    task.arguments =  @[@"-c",
                        [NSString stringWithFormat:@"%@", cmd]];
    
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSFileHandle *file = pipe.fileHandleForReading;
    
    [task launch];
    
    NSData *data = [file readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return output;
}

@end
