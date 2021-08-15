	//
	//  ViewController.m
	//  FaceDetect
	//
	//  Created by Gikki Ares on 2021/6/14.
	//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<
AVCaptureMetadataOutputObjectsDelegate
>
{
		//Reader
	AVAsset * mavAsset;
	AVAssetReader * mavAssetReader;
	int mi_videoWidth,mi_videoHeight;
	AVAssetReaderTrackOutput * mavAssetReaderTrackOutput_video;
	AVAssetReaderTrackOutput * mavAssetReaderTrackOutput_audio;
		//	AVAssetReaderAudioMixOutput
		//Writer
	AVAssetWriter * mavAssetWriter;
	AVAssetWriterInput * mavAssetWriterInput_video;
	AVAssetWriterInput * mavAssetWriterInput_audio;
	AVAssetWriterInputPixelBufferAdaptor * mavAssetWriterInputPixelBufferAdaptor;
	
	CFAbsoluteTime time_startConvert;
	CFAbsoluteTime time_endConvert;
	
	CMTime cmtime_processing;
	
		//statics
	int mi_videoFrameCount,mi_audioFrameCount;
	
	CMSampleBufferRef mcmSampleBufferRef_video;
	CMTime mcmTime_video;
	CMSampleBufferRef mcmSampleBufferRef_audio;
	CMTime mcmTime_audio;
	
	//
	BOOL mb_isTranscoding;
}

@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
}

- (void)initReader {
	NSString * filePath = [[NSBundle mainBundle] pathForResource:@"Butterfly_h264_ac3.mp4" ofType:nil];
	NSURL * fileUrl = [NSURL fileURLWithPath:filePath];
	
		//TODO:这个选项是什么意思??
	NSDictionary *inputOptions = @{
		AVURLAssetPreferPreciseDurationAndTimingKey:@(YES)
	};
	mavAsset = [AVURLAsset URLAssetWithURL:fileUrl options:inputOptions];
		//创建AVAssetReader
	NSError *error = nil;
	mavAssetReader = [AVAssetReader assetReaderWithAsset:mavAsset error:&error];
	
		//设置Reader输出的内容的格式.
	NSDictionary * dic_videoOutputSetting = @{
		(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)
	};
	
	/*
	 获取资源的一个视频轨道
	 添加资源的第一个视频轨道
	 */
	AVAssetTrack *track = [[mavAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
		//这个宽高,有点不准确呐??
	mi_videoHeight = track.naturalSize.height;
	mi_videoWidth = track.naturalSize.width;
	
		//创建AVAssetReaderTrackOutput
	mavAssetReaderTrackOutput_video = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:dic_videoOutputSetting];
	mavAssetReaderTrackOutput_video.alwaysCopiesSampleData = NO;
	if([mavAssetReader canAddOutput:mavAssetReaderTrackOutput_video]){
		[mavAssetReader addOutput:mavAssetReaderTrackOutput_video];
		NSLog(@"添加视频Output成功.");
	}
	else {
		NSLog(@"添加视频Output失败.");
	}
	
	NSArray *audioTracks = [mavAsset tracksWithMediaType:AVMediaTypeAudio];
		// This might need to be extended to handle movies with more than one audio track
	AVAssetTrack* audioTrack = [audioTracks objectAtIndex:0];
	
	AudioChannelLayout channelLayout;
	memset(&channelLayout, 0, sizeof(AudioChannelLayout));
		//	channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
	channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
	
	NSData * data = [[NSData alloc] initWithBytes:&channelLayout length:sizeof(AudioChannelLayout)];
	NSDictionary * dic_audioOutputSetting = @{
		AVFormatIDKey : @(kAudioFormatLinearPCM),
		AVSampleRateKey : @(44100),
		AVNumberOfChannelsKey : @(1),
		AVLinearPCMBitDepthKey : @(16),
		AVLinearPCMIsNonInterleaved:@(false),
		AVLinearPCMIsFloatKey:@(false),
		AVLinearPCMIsBigEndianKey:@(false),
		AVChannelLayoutKey:data
	};
	
	mavAssetReaderTrackOutput_audio = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audioTrack outputSettings:dic_audioOutputSetting];
	mavAssetReaderTrackOutput_audio.alwaysCopiesSampleData = NO;
	if([mavAssetReader canAddOutput:mavAssetReaderTrackOutput_audio]){
		[mavAssetReader addOutput:mavAssetReaderTrackOutput_audio];
		NSLog(@"添加音频Output成功.");
	}
	else {
		NSLog(@"添加音频Output失败.");
	}

}


-(void)initWriter{
	NSLog(@"Config writer");
	NSString * outputFilePath = @"/Users/gikkiares/Desktop/Output.mp4";
		//全局变量还是临时变量?
	NSURL * outputFileUrl = [NSURL fileURLWithPath:outputFilePath];
		//如果文件存在,则删除,一定要确保文件不存在.
	unlink([outputFilePath UTF8String]);
		//.mp4 //AVFileTypeMPEG4
		//.mov //AVFileTypeQuickTimeMovie
	mavAssetWriter = [AVAssetWriter assetWriterWithURL:outputFileUrl fileType:AVFileTypeMPEG4 error:nil];
	
	
		// Set this to make sure that a functional movie is produced, even if the recording is cut off mid-stream. Only the last second should be lost in that case.
		//好像这个属性是必须要设置的.
	mavAssetWriter.movieFragmentInterval = CMTimeMakeWithSeconds(1.0, 1000);
	
		//视频input
		//视频属性 AVVideoCodecTypeHEVC
	NSDictionary * dic_videoCompressionSettings = @{
		AVVideoCodecKey : AVVideoCodecTypeHEVC,
		AVVideoScalingModeKey : AVVideoScalingModeResizeAspectFill,
		AVVideoWidthKey : @(mi_videoWidth),
		AVVideoHeightKey : @(mi_videoHeight)
	};
		//初始化写入器，并制定了媒体格式
	mavAssetWriterInput_video = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:dic_videoCompressionSettings];
	mavAssetWriterInput_video.expectsMediaDataInRealTime = YES;
		//默认值是PI/2,导致导出的视频有一个90度的旋转.
	mavAssetWriterInput_video.transform = CGAffineTransformMakeRotation(0);
	
	
		//接受的数据帧的格式
	NSDictionary *sourcePixelBufferAttributesDictionary =@{
		(NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),
		(NSString *)kCVPixelBufferWidthKey:@(mi_videoWidth),
		(NSString *)kCVPixelBufferHeightKey:@(mi_videoHeight)
	};
	
	mavAssetWriterInputPixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:mavAssetWriterInput_video sourcePixelBufferAttributes:sourcePixelBufferAttributesDictionary];
	
	
		//添加视频input
	if([mavAssetWriter canAddInput:mavAssetWriterInput_video]) {
		[mavAssetWriter addInput:mavAssetWriterInput_video];
		NSLog(@"Wirter add video input,successed.");
	}
	else {
		NSLog(@"Wirter add video input,failed.");
	}
	
	//添加音频input
	//kAudioFormatLinearPCM
	
	AudioChannelLayout channelLayout;
	memset(&channelLayout, 0, sizeof(AudioChannelLayout));
		//	channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
	channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
	
	NSData * data = [[NSData alloc] initWithBytes:&channelLayout length:sizeof(AudioChannelLayout)];
	NSDictionary * dic_audioCompressionSettings = @{
		AVFormatIDKey : @(kAudioFormatMPEG4AAC),
		AVSampleRateKey : @(44100),
		AVNumberOfChannelsKey : @(1),
		AVChannelLayoutKey:data
	};
		//初始化写入器，并制定了媒体格式
	mavAssetWriterInput_audio = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:dic_audioCompressionSettings];
	
	if([mavAssetWriter canAddInput:mavAssetWriterInput_audio]) {
		[mavAssetWriter addInput:mavAssetWriterInput_audio];
		NSLog(@"Wirter add audio input,successed.");
	}
	else {
		NSLog(@"Wirter add audio input,failed.");
	}
	
}



/**
 开始读取和处理每一帧数据
 */
- (void)startProcessEveryFrame {
		//TODO:AssetReader开始一次之后,不能再次开始.
	if ([mavAssetReader startReading]) {
		NSLog(@"Assert reader start reading,成功.");
	}
	else {
		AVAssetReaderStatus status =	 mavAssetReader.status;
		NSError * error = mavAssetReader.error;
		NSLog(@"Assert reader start reading,失败,status is %ld,%@",(long)status,error.userInfo);
		return;
	}
	if([mavAssetWriter startWriting]) {
		NSLog(@"Assert writer start writing,成功.");
		[mavAssetWriter startSessionAtSourceTime:kCMTimeZero];
	}
	else {
		NSLog(@"Assert writer start writing,失败.");
		return;
	}
		//这个操作不能放主线程,播放不了的.
		//	dispatch_queue_t queue = dispatch_queue_create("com.writequeue", DISPATCH_QUEUE_CONCURRENT);
	dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
	dispatch_async(queue, ^{
		self->time_startConvert = CFAbsoluteTimeGetCurrent();
		while (self->mavAssetReader.status == AVAssetReaderStatusReading||self->mcmSampleBufferRef_audio||self->mcmSampleBufferRef_video) {
			if(!self->mcmSampleBufferRef_video) {
				self->mcmSampleBufferRef_video = [self->mavAssetReaderTrackOutput_video copyNextSampleBuffer];
				
			}
			if(!self->mcmSampleBufferRef_audio) {
				self->mcmSampleBufferRef_audio = [self->mavAssetReaderTrackOutput_audio copyNextSampleBuffer];
				
			}
			
			CMTime cmTime_videoTime = CMSampleBufferGetPresentationTimeStamp(self->mcmSampleBufferRef_video);
			CMTime cmTime_audioTime = CMSampleBufferGetPresentationTimeStamp(self->mcmSampleBufferRef_audio);
			if(self->mcmSampleBufferRef_video && self->mcmSampleBufferRef_audio) {
				float videoTime = CMTimeGetSeconds(cmTime_videoTime);
				float audioTime = CMTimeGetSeconds(cmTime_audioTime);
				if(videoTime<=audioTime) {
						//处理视频
					[self processSampleBuffer:self->mcmSampleBufferRef_video isVideo:YES pts:cmTime_videoTime];
				}
				else {
						//处理音频
					[self processSampleBuffer:self->mcmSampleBufferRef_audio isVideo:NO pts:cmTime_audioTime];
				}
			}
			else {
				if(self->mcmSampleBufferRef_audio) {
					[self processSampleBuffer:self->mcmSampleBufferRef_audio isVideo:NO pts:cmTime_audioTime];
				}
				else if(self->mcmSampleBufferRef_video) {
					[self processSampleBuffer:self->mcmSampleBufferRef_video isVideo:YES pts:cmTime_videoTime];
				}
				else {
						//没有音频也没有视频
					NSLog(@"copyNextSampleBuffer没有获取到数据,AssertReader应该已经读取数据完毕.");
				}
			}
		}
		
		if(self->mavAssetReader.status == AVAssetReaderStatusCompleted) {
			
			NSLog(@"AssetReader数据已经读取完毕");
			switch (self->mavAssetWriter.status) {
				case AVAssetWriterStatusWriting:{
					[self onTranscodeFinish];
					break;
				}
				case AVAssetWriterStatusCompleted:{
					NSLog(@"AssetWriter写入数据完毕");
					break;
				}
				default:{
					NSLog(@"AssetWriter状态异常");
					break;
				}
			}
			
			
		}
		else if(self->mavAssetReader.status == AVAssetReaderStatusFailed){
			NSLog(@"AVAssetReader读取失败,可能是格式设置问题.");
		}
		else {
			NSLog(@"AVAssetReader状态异常:%ld",self->mavAssetReader.status);
		}
	});
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer isVideo:(BOOL)isVideo pts:(CMTime)cmTime{
	if(isVideo) {
		CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
		while(![mavAssetWriterInput_video isReadyForMoreMediaData]) {
			sleep(0.1);
		}
		[mavAssetWriterInputPixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:cmTime];
			//释放刚刚的cgimage
		CFRelease(sampleBuffer);
		mcmSampleBufferRef_video = nil;
		self->mi_videoFrameCount ++;
		
	}
	else {
		while(![mavAssetWriterInput_audio isReadyForMoreMediaData]) {
			sleep(0.1);
		}
		[mavAssetWriterInput_audio appendSampleBuffer:sampleBuffer];
		CFRelease(sampleBuffer);
		mcmSampleBufferRef_audio = nil;
		self->mi_audioFrameCount++;
	}
}


/**
 转码完毕之后的操作
 */
- (void)onTranscodeFinish {
	[self->mavAssetWriterInput_audio markAsFinished];
	[self->mavAssetWriterInput_video markAsFinished];
		//mavAssetWriterfinish可以释放很多内存.
	[mavAssetWriter finishWritingWithCompletionHandler:^{
		[self->mavAssetReader cancelReading];
		self->time_endConvert = CFAbsoluteTimeGetCurrent();
		CFTimeInterval duration = self->time_endConvert - self->time_startConvert;
		self->mb_isTranscoding = NO;
		NSString *strInfo = [NSString stringWithFormat:@"转换完毕,一共耗时:%.2fs,there are %d audio,%d video",duration,self->mi_audioFrameCount,self->mi_videoFrameCount];
		NSLog(@"%@",strInfo);
	}];
}

- (IBAction)onClickStart:(id)sender {
	if(!mb_isTranscoding) {
		mb_isTranscoding = YES;
		[self initReader];
		[self initWriter];
		[self startProcessEveryFrame];
	}
}


@end
