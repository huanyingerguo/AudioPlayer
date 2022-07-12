//
//  DragTableView.h
//  AudioPlayer
//
//  Created by sunjinglin on 2021/9/24.
//  Copyright © 2021 Sun,Jinglin. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface DragDropTableView : NSTableView
@property (copy, nonatomic) void (^dragFilesBlock)(NSArray * fileList);

@end

NS_ASSUME_NONNULL_END
