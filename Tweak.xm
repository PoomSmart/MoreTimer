#import <substrate.h>
#import "../PS.h"

CFStringRef const PreferencesNotification = CFSTR("com.PS.MoreTimer.prefs");
NSString *const PREF_PATH = @"/var/mobile/Library/Preferences/com.PS.MoreTimer.plist";

static NSInteger thirdDuration;
static NSInteger fourthDuration;
static NSInteger fifthDuration;
static NSInteger doubleBlinkDuration;
static NSInteger blinkStyle;
/* blinkStyle
0 - default
1 - blink all
2 - double blink all
3 - blink every 2 seconds
4 - double blink every 2 seconds
*/
static BOOL shouldUseTorch;
static BOOL shouldUseBurst;
static BOOL enabledAddition;

static NSUInteger effectiveTimerCount;

%hook CAMTimerButton

- (NSInteger)numberOfMenuItems
{
	if (!IPAD && effectiveTimerCount == 3)
		return 5;
	return effectiveTimerCount + 1;
}

- (void)_commonCAMTimerButtonInitialization
{
	%orig;
	for (NSUInteger index = 3; index < (NSUInteger)[self numberOfMenuItems]; index++) {
		[self setHighlighted:YES forIndex:index];
	}
}

- (void)reloadData
{
	%orig;
	if (!IPAD && effectiveTimerCount == 3) {
		CAMButtonLabel *zeroLabel = [[self _menuItems] lastObject];
		zeroLabel.hidden = YES;
		zeroLabel.userInteractionEnabled = NO;
	}
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
	return shouldUseBurst;
}

- (void)_indicateDelayedCaptureProgressUsingTorch
{
	if (!shouldUseTorch)
		return;
	CAMCaptureController *controller = MSHookIvar<CAMCaptureController *>(self, "_cameraController");
	if (controller.cameraDevice != 0)
		return;
	CAMTorchPatternController *torch = MSHookIvar<CAMTorchPatternController *>(self, "__torchPatternController");
	NSInteger totalDuration = [self _currentTimerDuration];
	NSInteger remainingTicks = [self _remainingDelayedCaptureTicks];
	if (blinkStyle == 0) {
		BOOL doubleBlinkDurationForLastSeconds = (doubleBlinkDuration > 0 && (doubleBlinkDuration >= remainingTicks));
		doubleBlinkDurationForLastSeconds ? [torch doubleBlink] : [torch blink];
	}
	else if (blinkStyle == 1)
		[torch blink];
	else if (blinkStyle == 2)
		[torch doubleBlink];
	else if (blinkStyle == 3 || blinkStyle == 4) {
		BOOL everyTwoSecs = (((totalDuration - remainingTicks) % 2) == 0);
		if (everyTwoSecs)
			blinkStyle == 3 ? [torch blink] : [torch doubleBlink];
	}
}

%end

static void reloadSettings()
{
	NSDictionary *prefs = nil;
	CFPreferencesAppSynchronize(CFSTR("com.PS.MoreTimer"));
	prefs = [NSDictionary dictionaryWithContentsOfFile:PREF_PATH];
	id val =  prefs[@"thirdDuration"];
	thirdDuration = val ? [val intValue] : 15;
	val = prefs[@"fourthDuration"];
	fourthDuration = [val intValue];
	val = prefs[@"fifthDuration"];
	fifthDuration = [val intValue];
	val = prefs[@"blinkStyle"];
	blinkStyle = [val intValue];
	val = prefs[@"doubleBlinkDuration"];
	doubleBlinkDuration = val ? [val intValue] : 3;
	val = prefs[@"shouldUseBurst"];
	shouldUseBurst = val ? [val boolValue] : YES;
	val = prefs[@"shouldUseTorch"];
	shouldUseTorch = val ? [val boolValue] : YES;
	val = prefs[@"enabledAddition"];
	enabledAddition = [val boolValue];
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