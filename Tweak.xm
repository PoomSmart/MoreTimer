#import <substrate.h>
#import "../PS.h"

CFStringRef const PreferencesNotification = CFSTR("com.PS.MoreTimer.prefs");
NSString *const PREF_PATH = @"/var/mobile/Library/Preferences/com.PS.MoreTimer.plist";

@interface CAMExpandableMenuButton : UIControl
@property NSUInteger selectedIndex;
@end

@interface CAMTimerButton : CAMExpandableMenuButton
@property NSInteger duration;
- (NSString *)titleForMenuItemAtIndex:(NSUInteger)index;
@end

@interface CAMTorchPattern : NSObject
- (id)initWithType:(NSInteger)type;
@end

@interface CAMTorchPatternController : NSObject
- (void)blink; // ?
- (void)doubleBlink; // type 3
@end

@interface CAMCaptureController : NSObject
@property int cameraDevice;
@end

@interface CAMCameraView
- (CAMTorchPatternController *)_torchPatternController;
- (CAMTimerButton *)_timerButton;
- (NSInteger)_currentTimerDuration;
- (NSInteger)_remainingDelayedCaptureTicks;
- (BOOL)_shouldUseAvalancheForDelayedCapture;
- (void)_startDelayedCapture;
@end

NSInteger thirdDuration;
NSInteger fourthDuration;
NSInteger fifthDuration;
NSInteger doubleBlinkDuration;
NSInteger blinkStyle; // 0 - default, 1 - blink all, 2 - double blink all, 3 - blink every 2 seconds, 4 - double blink every 2 seconds
BOOL shouldUseTorch;
BOOL shouldUseBurst;
BOOL enabledAddition;

NSUInteger effectiveTimerCount;

%hook CAMTimerButton

- (NSInteger)numberOfMenuItems
{
	if (!IPAD && effectiveTimerCount == 3)
		return 5;
	return effectiveTimerCount + 1;
}

%end

%hook CAMCameraView

- (NSInteger)_numberOfTicksForTimerDuration:(NSInteger)duration
{
	if (duration > 2) {
		switch (duration) {
			case 3:
				return thirdDuration;
			case 4:
				return fourthDuration;
			case 5:
				return fifthDuration;
		}
	}
	return %orig;
}

- (BOOL)_shouldUseAvalancheForDelayedCapture
{
	return !shouldUseBurst ? NO : %orig;
}

- (void)_indicateDelayedCaptureProgressUsingTorch
{
	if (!shouldUseTorch)
		return;
	// CAMTimerButton index == 2 && remaining ticks <= 3  =  doubleBlink
	// CAMTimerButton index != 2 || remaining ticks >  3  =  blink

	/*NSInteger remainingTicks = MSHookIvar<NSInteger>(self, "__remainingDelayedCaptureTicks");
	NSUInteger index = [self _timerButton].selectedIndex;
	wantDoubleBlink = doubleBlinkDurationForLastSeconds || doubleBlinkFromStyle;
	wantBlink = blinkStyle == 1;
	%orig;
	wantDoubleBlink = NO;
	wantBlink = NO;*/
	
	CAMCaptureController *controller = MSHookIvar<CAMCaptureController *>(self, "_cameraController");
	if (controller.cameraDevice != 0)
		return;
	//CAMTimerButton *timerButton = MSHookIvar<CAMTimerButton *>(self, "__timerButton");
	CAMTorchPatternController *torch = MSHookIvar<CAMTorchPatternController *>(self, "__torchPatternController");
	//NSInteger duration = timerButton.duration;
	NSInteger totalDuration = [self _currentTimerDuration];
	NSInteger remainingTicks = [self _remainingDelayedCaptureTicks];
	if (blinkStyle == 0) {
		BOOL doubleBlinkDurationForLastSeconds = doubleBlinkDuration > 0 && doubleBlinkDuration >= remainingTicks;
		if (doubleBlinkDurationForLastSeconds)
			[torch doubleBlink];
		else
			[torch blink];
	}
	else if (blinkStyle == 1)
		[torch blink];
	else if (blinkStyle == 2)
		[torch doubleBlink];
	else if (blinkStyle == 3 || blinkStyle == 4) {
		BOOL everyTwoSecs = ((totalDuration - remainingTicks) % 2) == 0;
		if (everyTwoSecs) {
			blinkStyle == 3 ? [torch blink] : [torch doubleBlink];
		}
	}
}

%end

static void reloadSettings()
{
	NSDictionary *prefs = nil;
	CFPreferencesAppSynchronize(CFSTR("com.PS.MoreTimer"));
	prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
	thirdDuration = prefs[@"thirdDuration"] ? [prefs[@"thirdDuration"] intValue] : 15;
	fourthDuration = [prefs[@"fourthDuration"] intValue];
	fifthDuration = [prefs[@"fifthDuration"] intValue];
	blinkStyle = [prefs[@"blinkStyle"] intValue];
	doubleBlinkDuration = prefs[@"doubleBlinkDuration"] ? [prefs[@"doubleBlinkDuration"] intValue] : 3;
	shouldUseBurst = prefs[@"shouldUseBurst"] ? [prefs[@"shouldUseBurst"] boolValue] : YES;
	shouldUseTorch = prefs[@"shouldUseTorch"] ? [prefs[@"shouldUseTorch"] boolValue] : YES;
	enabledAddition = [prefs[@"enabledAddition"] boolValue];
	effectiveTimerCount = 2;
	if (enabledAddition) {
		if (thirdDuration != 0) {
			effectiveTimerCount++;
			if (fourthDuration != 0) {
				effectiveTimerCount++;
				if (fifthDuration != 0)
					effectiveTimerCount++;
			}
		}
	}
}

static void post(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	BOOL killCamera = [[NSDictionary dictionaryWithContentsOfFile:PREF_PATH][@"killCam"] boolValue];
	if (killCamera)
		system("killall Camera");
	reloadSettings();
}

%ctor
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, &post, PreferencesNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
	reloadSettings();
	%init;
  	[pool drain];
}