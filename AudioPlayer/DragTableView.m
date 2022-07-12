//
//  DragTableView.m
//  AudioPlayer
//
//  Created by sunjinglin on 2021/9/24.
//  Copyright © 2021 Sun,Jinglin. All rights reserved.
//

#import "DragTableView.h"

@implementation DragDropTableView
- (void)awakeFromNib {
    // Register to accept filename drag/drop
    [self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType, nil]];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender{
     if ([self dragFilesBlock] == nil) {
        return NSDragOperationNone;
    }
    
    if ([[[sender draggingPasteboard] types] containsObject:NSFilenamesPboardType]) {
        return NSDragOperationCopy;
    }
    
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    return [self draggingEntered:sender];
}

-(BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    NSPasteboard *pboard;
    pboard = [sender draggingPasteboard];
    if ([[pboard types] containsObject:NSFilenamesPboardType]) {
         NSArray *filenames = [pboard propertyListForType:NSFilenamesPboardType];
        if (self.dragFilesBlock != nil) {
            self.dragFilesBlock(filenames);
        }
        return YES;
    }
    return NO;
}

@end
