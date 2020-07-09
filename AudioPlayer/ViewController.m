//
//  ViewController.m
//  AudioPlayer
//
//  Created by Sun,Jinglin on 2020/6/28.
//  Copyright © 2020 Sun,Jinglin. All rights reserved.
//

#import "ViewController.h"
#import "AudioPlayer.h"

@interface ViewController () <NSTableViewDelegate, NSTableViewDataSource>
@property (weak) IBOutlet NSTextField *inputDesc;
@property (weak) IBOutlet NSTextField *outputDesc;

@property (weak) IBOutlet NSButton *playBtn;
@property (weak) IBOutlet NSButton *pauseBtn;
@property (weak) IBOutlet NSSlider *slier;
@property (weak) IBOutlet NSTextField *progress;
@property (weak) IBOutlet NSButton *recordBtn;

@property (strong) NSMutableArray *fileList;
@property (strong) NSMutableArray *filePathList;
@property (weak) IBOutlet NSTableView *fileListTableview;

@property (assign) BOOL isChangingProgress;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.fileList = [NSMutableArray arrayWithCapacity:1];
    self.filePathList = [NSMutableArray arrayWithCapacity:1];
    self.fileListTableview.delegate = self;
    self.fileListTableview.dataSource = self;
    
    [AudioPlayer sharedInstance].playProgress = ^(long long readPacker, float progress) {
        self.progress.stringValue = [NSString stringWithFormat:@"进度：%0.1f", progress];
        if (!self.isChangingProgress) {
            self.slier.floatValue = progress;
        }
    };
    [self selectFile];
    [self.fileListTableview reloadData];
}

- (void)selectFile {
    [self.fileList removeAllObjects];
    [self.filePathList removeAllObjects];

    //AudioFile
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"music_48k-01" ofType:@"wav"];
    NSString *filePath2 = [[NSBundle mainBundle] pathForResource:@"周杰伦 - 晴天" ofType:@"mp3"];
    NSString *filePath3 = [[NSBundle mainBundle] pathForResource:@"output" ofType:@"pcm"];

    [self.fileList addObject:filePath.lastPathComponent];
    [self.fileList addObject:filePath2.lastPathComponent];
    [self.fileList addObject:filePath3.lastPathComponent];

    [self.filePathList addObject:filePath];
    [self.filePathList addObject:filePath2];
    [self.filePathList addObject:filePath3];
}

#pragma mark-IBAction
- (IBAction)playClicked:(id)sender {
    if (self.fileListTableview.selectedRow >= 0) {
        NSString *path = [self.filePathList objectAtIndex:self.fileListTableview.selectedRow];
        [[AudioPlayer sharedInstance] setFilePath:path];
        [[AudioPlayer sharedInstance] play];
        self.inputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForInput];
        self.outputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForOutput];
    }
}

- (IBAction)pauseClicked:(id)sender {
     [[AudioPlayer sharedInstance] pause];
}

- (IBAction)recordClicked:(id)sender {
     [[AudioPlayer sharedInstance] record];
}

- (IBAction)sliderAction:(id)sender {
    self.isChangingProgress = YES;
    NSSlider *slider = (NSSlider *)sender;
    [AudioPlayer sharedInstance].readedPacket = slider.floatValue / 100 * [AudioPlayer sharedInstance].packetNums;
    self.progress.stringValue = [NSString stringWithFormat:@"进度：%0.1f", slider.floatValue];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isChangingProgress = NO;
    });
}

#pragma mark- File Action
- (IBAction)clickLoadFileBtn:(NSButton *)sender {
    [self selectFile];
    
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            for( NSURL* url in panel.URLs ){
                __block  NSString * filePath = url.path;
                if (filePath == nil ) {
                    return;
                }
                
                if (!self.fileList) {
                    self.fileList = [NSMutableArray array];
                }
                [self.fileList addObject:filePath.lastPathComponent];
                [self.filePathList addObject:filePath];
            }
            
            [self.fileListTableview reloadData];
            [self.fileListTableview selectRowIndexes:[[NSIndexSet alloc] initWithIndex:0] byExtendingSelection:NO];
        }
    }];
}

#pragma mark - table data souutce delegate
- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView {
    return self.fileList.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 20;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    return YES;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (self.fileList.count > row) {
        NSTableCellView *cellView = [self.fileListTableview makeViewWithIdentifier:@"fileCell" owner:self];
        cellView.textField.stringValue = [self.fileList objectAtIndex:row];
        return cellView;
    }
    
    return nil;
}
@end
