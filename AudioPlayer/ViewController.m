//
//  ViewController.m
//  AudioPlayer
//
//  Created by Sun,Jinglin on 2020/6/28.
//  Copyright © 2020 Sun,Jinglin. All rights reserved.
//

#import "ViewController.h"
#import "AudioPlayer.h"

@interface ViewController ()
@property (weak) IBOutlet NSTextField *inputDesc;
@property (weak) IBOutlet NSTextField *outputDesc;

@property (weak) IBOutlet NSButton *playBtn;
@property (weak) IBOutlet NSButton *pauseBtn;
@property (weak) IBOutlet NSSlider *slier;
@property (weak) IBOutlet NSTextField *progress;
@property (weak) IBOutlet NSButton *recordBtn;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self selectFile];
    
    [AudioPlayer sharedInstance].playProgress = ^(int readPacker, float progress) {
        self.progress.stringValue = @(progress).stringValue;
    };
}

- (void)selectFile {
    //AudioFile
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"music_48k-01" ofType:@"wav"];
    filePath = [[NSBundle mainBundle] pathForResource:@"周杰伦 - 晴天" ofType:@"mp3"];
    
    [[AudioPlayer sharedInstance] setFilePath:filePath];
}

#pragma mark-IBAction
- (IBAction)playClicked:(id)sender {
    [[AudioPlayer sharedInstance] play];
    self.inputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForInput];
    self.outputDesc.stringValue = [[AudioPlayer sharedInstance] getAudioStreamBasicDescriptionForOutput];
}

- (IBAction)pauseClicked:(id)sender {
     [[AudioPlayer sharedInstance] pause];
}

- (IBAction)recordClicked:(id)sender {
     [[AudioPlayer sharedInstance] record];
}

- (IBAction)sliderAction:(id)sender {
    NSSlider *slider = (NSSlider *)sender;
    [AudioPlayer sharedInstance].readedPacket = slider.floatValue / 100 * [AudioPlayer sharedInstance].packetNums;
    self.progress.stringValue = [NSString stringWithFormat:@"进度：%0.1f", slider.floatValue];
}

#pragma mark- Private Mehod


@end
