//
//  ViewController.m
//  AudioPlayer
//
//  Created by Sun,Jinglin on 2020/6/28.
//  Copyright © 2020 Sun,Jinglin. All rights reserved.
//

#import "ViewController.h"
#import "AudioPlayer.h"
#import "DecrpytFile.h"

@interface ViewController () <NSTableViewDelegate, NSTableViewDataSource>
@property (weak) IBOutlet NSTextField *inputDesc;
@property (weak) IBOutlet NSTextField *outputDesc;

@property (weak) IBOutlet NSButton *playBtn;
@property (weak) IBOutlet NSButton *pauseBtn;
@property (weak) IBOutlet NSSlider *slier;
@property (weak) IBOutlet NSTextField *progress;
@property (weak) IBOutlet NSButton *recordBtn;

@property (strong) NSMutableArray *filePathList;
@property (weak) IBOutlet NSTableView *fileListTableview;

//音频输出参数
@property (weak) IBOutlet NSTextField *sampleRate;
@property (weak) IBOutlet NSTextField *bitDepth;
@property (weak) IBOutlet NSTextField *channelCount;

@property (assign) BOOL isChangingProgress;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.filePathList = [NSMutableArray arrayWithCapacity:1];
    self.fileListTableview.delegate = self;
    self.fileListTableview.dataSource = self;
    
    [AudioPlayer sharedInstance].playProgress = ^(long long readPacker, float progress) {
        self.progress.stringValue = [NSString stringWithFormat:@"进度：%0.1f", progress];
        if (!self.isChangingProgress) {
            self.slier.floatValue = progress;
        }
    };
    [self resetSelectedFiles];
    [self.fileListTableview reloadData];
}

- (void)resetSelectedFiles {
    [self.filePathList removeAllObjects];

    //AudioFile
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"music_48k-01" ofType:@"wav"];
    NSString *filePath2 = [[NSBundle mainBundle] pathForResource:@"周杰伦 - 晴天" ofType:@"mp3"];
    NSString *filePath3 = [[NSBundle mainBundle] pathForResource:@"output" ofType:@"pcm"];

    [self.filePathList addObjectsFromArray:@[filePath, filePath2, filePath3]];
}

#pragma mark-IBAction
- (IBAction)playClicked:(id)sender {
    if (self.fileListTableview.selectedRow >= 0) {
        NSString *path = [self.filePathList objectAtIndex:self.fileListTableview.selectedRow];
        if ([[AudioPlayer sharedInstance] isFilePCMType:path]) {
            [self resetDefaultOutputParamets:path];
        }
        [[AudioPlayer sharedInstance] setFilePath:path];
        [[AudioPlayer sharedInstance] play];
        self.inputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForInput];
        self.outputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForOutput];
    }
}

- (void)resetDefaultOutputParamets:(NSString *)path {
    NSString *sampleRate = [self sampleRateFromFileName:path.lastPathComponent];
    if (sampleRate.length) {
        self.sampleRate.stringValue = sampleRate;
        self.channelCount.stringValue = @"1";
        self.bitDepth.stringValue = @"16";
    } else {
        self.sampleRate.stringValue = @"44100";
        self.channelCount.stringValue = @"1";
        self.bitDepth.stringValue = @"32";
    }
    
    [AudioPlayer sharedInstance].sampleRate = self.sampleRate.stringValue.intValue;
    [AudioPlayer sharedInstance].channelCount = self.channelCount.stringValue.intValue;
    [AudioPlayer sharedInstance].bitDepth = self.bitDepth.stringValue.intValue;
}

- (NSString *)sampleRateFromFileName:(NSString *)inputFileName {
    NSArray *nameArray = [inputFileName componentsSeparatedByString:@"_"];
    if (nameArray.count < 8) {
        return @"";
    }
    NSString *sample = [nameArray objectAtIndex:5];
    return sample;
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
    [self resetSelectedFiles];
    
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            for( NSURL* url in panel.URLs ){
                NSString * filePath = url.path;
                if (filePath == nil ) {
                    return;
                }
                
                if ([filePath.lastPathComponent.pathExtension isEqualToString:@"dat"]) {
                    NSError *err;
                    NSString *tempPath = [DecrpytFile decode:filePath error:&err];
                    if (err) {
                        self.inputDesc.stringValue = err.localizedDescription;
                        continue;
                    }
                    
                    filePath = tempPath;
                }
                
                [self.filePathList insertObject:filePath atIndex:0];
            }
            
            [self.fileListTableview reloadData];
            [self.fileListTableview selectRowIndexes:[[NSIndexSet alloc] initWithIndex:0] byExtendingSelection:NO];
        }
    }];
}

#pragma mark - table data souutce delegate
- (NSInteger) numberOfRowsInTableView:(NSTableView *)tableView {
    return self.filePathList.count;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    return 20;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    NSString *path = [self.filePathList objectAtIndex:row];
    if ([[AudioPlayer sharedInstance] isFilePCMType:path]) {
        [self.sampleRate setEnabled:YES];
        [self.channelCount setEnabled:YES];
        [self.bitDepth setEnabled:YES];
    } else {
        [self.sampleRate setEnabled:NO];
        [self.channelCount setEnabled:NO];
        [self.bitDepth setEnabled:NO];
    }
    return YES;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (self.filePathList.count > row) {
        NSTableCellView *cellView = [self.fileListTableview makeViewWithIdentifier:@"fileCell" owner:self];
        cellView.textField.stringValue = [[self.filePathList objectAtIndex:row] lastPathComponent];
        return cellView;
    }
    
    return nil;
}
@end
