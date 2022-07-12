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
#import "AudioFileConvert.h"
#import "DragTableView.h"

#define RECORD_PATH [[NSSearchPathForDirectoriesInDomains(NSDownloadsDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingString:@"/record***.pcm"]

@interface ViewController () <NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate>
@property (weak) IBOutlet NSTextField *inputDesc;
@property (weak) IBOutlet NSTextField *outputDesc;

@property (weak) IBOutlet NSButton *playBtn;
@property (weak) IBOutlet NSButton *pauseBtn;
@property (weak) IBOutlet NSSlider *slier;
@property (weak) IBOutlet NSTextField *progress;
@property (weak) IBOutlet NSButton *recordBtn;

@property (strong) NSMutableArray *filePathList;
@property (weak) IBOutlet DragDropTableView *fileListTableview;

//音频输出参数
@property (weak) IBOutlet NSTextField *sampleRate;
@property (weak) IBOutlet NSTextField *bitDepth;
@property (weak) IBOutlet NSTextField *channelCount;
@property (weak) IBOutlet NSButton *clearOld;

@property (assign) BOOL isChangingProgress;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.filePathList = [NSMutableArray arrayWithCapacity:1];
    self.fileListTableview.delegate = self;
    self.fileListTableview.dataSource = self;
    self.fileListTableview.allowsMultipleSelection = YES;
    
    __weak typeof(self) weakSelf = self;
    self.fileListTableview.dragFilesBlock = ^(NSArray * _Nonnull fileList) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf addNewFiles:fileList];
    };
    
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
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        [self.filePathList addObject:filePath];
    }
    
    NSString *filePath2 = [[NSBundle mainBundle] pathForResource:@"周杰伦 - 晴天" ofType:@"mp3"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath2]) {
        [self.filePathList addObject:filePath2];
    }
    
    NSString *filePath3 = [[NSBundle mainBundle] pathForResource:@"output" ofType:@"pcm"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath3]) {
        [self.filePathList addObject:filePath3];
    }
}

#pragma mark-IBAction
- (IBAction)playClicked:(id)sender {
    if (self.fileListTableview.selectedRow >= 0) {
        NSString *path = [self.filePathList objectAtIndex:self.fileListTableview.selectedRow];
        if ([[AudioPlayer sharedInstance] isFilePCMType:path]) {
            [self resetDefaultOutputParamets:path];
        }
        [[AudioPlayer sharedInstance] play:path];
        self.inputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForInput];
        self.outputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForOutput];
    }
}

- (void)resetDefaultOutputParamets:(NSString *)path {
    NSString *sampleRate = [self sampleRateFromFileName:path.lastPathComponent];
    if (sampleRate.length) {
        self.sampleRate.stringValue = sampleRate;
        self.channelCount.stringValue = @"1";
        self.bitDepth.stringValue = @"32";
    } else {
//        self.sampleRate.stringValue = @"44100";
//        self.channelCount.stringValue = @"1";
//        self.bitDepth.stringValue = @"16";
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
    if ([[AudioPlayer sharedInstance] isRecording]) {
        NSControlStateValue last = self.clearOld.state;
        [self addNewFiles:@[RECORD_PATH]];
        [self.clearOld setState:last];
    }
    [[AudioPlayer sharedInstance] pause];
}

- (IBAction)recordClicked:(id)sender {
    if ([self.filePathList containsObject:RECORD_PATH]) {
        [self.filePathList removeObject:RECORD_PATH];
        [self.fileListTableview reloadData];
    }
    
    [[AudioPlayer sharedInstance] record:RECORD_PATH];
}

- (IBAction)onDeleteClicked:(id)sender {
    if (self.filePathList.count <= 0) {
        [self showAlert:@"列表为空" completionHandler:nil];
        return;
    }
    
    if (self.fileListTableview.selectedRowIndexes.count > 0) {
        [self.fileListTableview.selectedRowIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
            [self.filePathList removeObjectAtIndex:idx];
        }];
        [self.fileListTableview reloadData];
        return;
    }
    
    NSAlert *alert = [NSAlert alertWithMessageText:@"清空提醒" defaultButton:@"Continue" alternateButton:@"Cancle"
                                       otherButton:nil informativeTextWithFormat:@"未选择任何文件，默认清空[支持手动多选]"];
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (NSOKButton == returnCode) {
            [self.filePathList removeAllObjects];
            [self.fileListTableview reloadData];
        }
    }];
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

- (IBAction)toWaveClicked:(id)sender {
    if (self.filePathList.count <= 0) {
        [self showAlert:@"列表为空" completionHandler:nil];
        return;
    }
    
    NSString *filePath = [self.filePathList objectAtIndex:self.fileListTableview.selectedRow];
    if ([[AudioPlayer sharedInstance] isFilePCMType:filePath]) {
        NSString *destination = [DecrpytFile mapInputFileToDestinationFile:filePath byExtention:@".wav"];
        const char *pcm_file = [filePath cStringUsingEncoding:NSUTF8StringEncoding];
        const char *wav_file = [destination cStringUsingEncoding:NSUTF8StringEncoding];
        
        audioFMT fmt;
        NSString *sampleRate = [self sampleRateFromFileName:filePath.lastPathComponent];
        if (sampleRate.length) {
            fmt.nSampleRate = [sampleRate integerValue];
            fmt.nChannleNumber = 1;
            fmt.nBitsPerSample = 16;
        } else {
            fmt.nSampleRate = 44100;
            fmt.nChannleNumber = 1;
            fmt.nBitsPerSample = 32;
        }
        
        int res = a_law_pcm_to_wav2(pcm_file, wav_file, fmt);
        if (res) {
            [self showAlert:@"转换失败" completionHandler:nil];
        } else {
            [self showAlert:@"转换成功" completionHandler:nil];
            [self openFilePath:destination];
        }
        NSLog(@"转换结果:res=%d", res);
    }
}

- (IBAction)localPathClicked:(id)sender {
    if (self.fileListTableview.selectedRow >= 0) {
        NSString *filePath = [self.filePathList objectAtIndex:self.fileListTableview.selectedRow];
        [self openFilePath:filePath];
    }
}

- (void)openFilePath:(NSString *)filePath {
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[fileURL]];
}

- (void)showAlert:(NSString *)contents completionHandler:(void (^ _Nullable)(NSModalResponse returnCode))handler {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = contents;
    [alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
        if (handler) {
            handler(returnCode);
        }
    }];
}

#pragma mark- File Action
- (IBAction)clickLoadFileBtn:(NSButton *)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSMutableArray *files = [NSMutableArray array];
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
                
                [files addObject:filePath];
            }
            
            [self addNewFiles:files];
        }
    }];
}

- (void)addNewFiles:(NSArray *)files {
    if (self.clearOld.state == NSControlStateValueOn) {
        [self resetSelectedFiles];
    }
    
    for (NSString *file in files) {
        NSString *filePath = file;
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
