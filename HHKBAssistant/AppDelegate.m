//
//  AppDelegate.m
//  HHKBAssistant
//
//  Created by 周 涵 on 2014/05/04.
//  Copyright (c) 2014年 hanks. All rights reserved.
//

#import "AppDelegate.h"
#import <ServiceManagement/ServiceManagement.h>
#import <IOKit/kext/KextManager.h>

@implementation AppDelegate

@synthesize usbManager;
@synthesize statusMenu;
@synthesize prefPaneWindowController;
@synthesize xpcManager;
@synthesize kbStatus = _kbStatus;
@synthesize prefUtil;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // use self as a notification center delegate
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

    // set up listener in background the thread
    [NSThread detachNewThreadSelector:@selector(setupListener) toTarget:usbManager withObject:nil];
    
    // register helper tool
    [self addHelper];
}

- (void)awakeFromNib {
    // add status icon to system menu bar
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    // set status item click action
    [statusItem setAction:@selector(statusItemClicked:)];
    [statusItem setTarget:self];
    
    // set status bar icon
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"icon_16x16" ofType:@"png"];
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    [statusItem setImage:icon];
    [statusItem setToolTip:APP_TOOLTIP];
    [statusItem setHighlightMode:YES];
    
    // get preference util, set property.
    self.prefUtil = [PreferenceUtil getSharedInstance];
    
    // init keyboard change menu title
    
    // we assum the build in keyboard is enabled by default
    // when this app runs with auto_disable enabled and a hhkb plugged in, we then reset kbStatus.
    self.kbStatus = BUILD_IN_KEYBOARD_ENABLE;
    [self setKbChangeMenuTitle:self.kbStatus];
    
    // init XPC manager, should before usb manager
    xpcManager = [XPCManager getSharedInstance];
    

    // init usb device manager
    usbManager = [[USBDeviceManager alloc] init];
    // update delegate
    usbManager.delegate = self.prefUtil;
    
    // init preference window controller
    // create window and init
    prefPaneWindowController = [[PreferencePaneWindowController alloc] initWithXibAndDelegate:XIBNAME delegate:self.prefUtil];
}

#pragma mark IBAction Method
- (IBAction)statusItemClicked:(id)sender {
    // if you want to set action to status item, you can not use 'statusItem.setMenu' to open menu, or else
    // action method will be disable, you should use [statusItem popUpStatusItemMenu] to do the job in action method

    // update disable menu title each time when open menu
    // but a little not effective, need to change kbStatus in use manager when auto disable happens.
    self.kbStatus = [self checkKbState];
    [self setKbChangeMenuTitle:self.kbStatus];
    
    // popup menu
    [statusItem popUpStatusItemMenu:statusMenu];
}

- (BOOL)checkKbState {
    // direct to detect keyboard kext is loaded or not
    

    // does not work...
    //BOOL result;
//    CFDictionaryRef kextRef = KextManagerCopyLoadedKextInfo((__bridge CFArrayRef)[NSArray arrayWithObject: [NSString stringWithFormat:@"%s", BUILD_IN_KEYBOARD_KEXT_ID]], NULL); // NULL means copy all info about this kext
//    
//    if (kextRef) {
//        // if existed, means loaded
//        result = BUILD_IN_KEYBOARD_ENABLE;
//    } else {
//        result = BUILD_IN_KEYBOARD_DISABLE;
//    }
    
    // release
//    CFRelease(kextRef);
    
    return self.kbStatus;
}

- (BOOL)kbStatus {
    // this is the custom getter for kbStatus, prefUtil.kbStatus can be updated by USBDeviceManager
    return prefUtil.kbStatus;
}

- (void)setKbStatus:(BOOL)kbStatus {
    // custom setter for kbStatus
    prefUtil.kbStatus = kbStatus;
}

- (void)setKbChangeMenuTitle:(BOOL)kbStatus {
    switch (kbStatus) {
        case BUILD_IN_KEYBOARD_DISABLE:
            [self.kbChangeMenu setTitle:ENABLE_AUTO_MENU_TITLE];
            break;
        case BUILD_IN_KEYBOARD_ENABLE:
            [self.kbChangeMenu setTitle:DISABLE_AUTO_MENU_TITLE];
            break;
    }
    if (prefUtil.hasExternalKB) {
        [self.kbChangeMenu setHidden:false];
    }
    else {
        [self.kbChangeMenu setHidden:true];
    }
}

- (void)changeKeyboardWith:(BOOL)kbStatus {
    switch (kbStatus) {
        case BUILD_IN_KEYBOARD_ENABLE:
            // enable build in keyboard
            [xpcManager sendRequest:ENABLE_KEYBOARD_REQUEST];
            break;
        case BUILD_IN_KEYBOARD_DISABLE:
            // disable build in keyboard
            [xpcManager sendRequest:DISABLE_KEYBOARD_REQUEST];
            break;
    }
    
    [self setKbChangeMenuTitle:kbStatus];
}

- (IBAction)openPreferencePane:(id)sender {
    // show window
    [prefPaneWindowController showWindow:prefPaneWindowController.myWindow];
    
    // set focus to new window
    NSApplication *myApp = [NSApplication sharedApplication];
    [myApp activateIgnoringOtherApps:YES];
    [prefPaneWindowController.myWindow makeKeyAndOrderFront:nil];
}

- (IBAction)changeKeyboardMode:(id)sender {
    self.kbStatus = !self.kbStatus;
    [self changeKeyboardWith:self.kbStatus];
}

- (IBAction)quit:(id)sender {
    [[NSApplication sharedApplication] terminate:nil];
}

- (IBAction)runOnStartup:(id)sender {
    [sender setState:![sender state]];
    
    if ([sender state]) {
        // if true to add app to login item lists
        [self addAppAsLoginItem];
    } else {
        // delete from login item lists
        [self deleteAppFromLoginItem];
    }
}

-(void) addAppAsLoginItem{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (CFURLRef)CFBridgingRetain([NSURL fileURLWithPath:appPath]);
    
	// Create a reference to the shared file list.
    // We are adding it to the current user only.
    // If we want to add it all users, use
    // kLSSharedFileListGlobalLoginItems instead of
    //kLSSharedFileListSessionLoginItems
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems, NULL);
	if (loginItems) {
		//Insert an item to the list.
		LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
                                                                     kLSSharedFileListItemLast, NULL, NULL,
                                                                     url, NULL, NULL);
		if (item){
			CFRelease(item);
        }
	}
    
	CFRelease(loginItems);
}

-(void) deleteAppFromLoginItem{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (CFURLRef)CFBridgingRetain([NSURL fileURLWithPath:appPath]);
    
	// Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems, NULL);
    
	if (loginItems) {
		UInt32 seedValue;
		//Retrieve the list of Login Items and cast them to
		// a NSArray so that it will be easier to iterate.
		NSArray  *loginItemsArray = (NSArray *)CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seedValue));
		for(int i = 0 ; i< [loginItemsArray count]; i++){
			LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)CFBridgingRetain([loginItemsArray
                                                                                         objectAtIndex:i]);
			//Resolve the item with URL
			if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr) {
				NSString * urlPath = [(NSURL*)CFBridgingRelease(url) path];
				if ([urlPath compare:appPath] == NSOrderedSame){
					LSSharedFileListItemRemove(loginItems,itemRef);
				}
			}
		}
	}
}

////////////////////////////////////////////
////// Disable keyboard helper util method
////////////////////////////////////////////
#pragma mark Helper Util Method
- (void)addHelper {
    // copy helper execute binary file to /Library/PrivilegedHelperTools
    // copy helper launchd settings plist file to /Library/LaunchDaemons
    NSDictionary *helperInfo = (__bridge NSDictionary*)SMJobCopyDictionary(kSMDomainSystemLaunchd,
                                                                           CFSTR(kHelperBundleID));
    if (!helperInfo)
    {
        AuthorizationItem authItem = { kSMRightBlessPrivilegedHelper, 0, NULL, 0 };
        AuthorizationRights authRights = { 1, &authItem };
        AuthorizationFlags flags = kAuthorizationFlagDefaults|
        kAuthorizationFlagInteractionAllowed|
        kAuthorizationFlagPreAuthorize|
        kAuthorizationFlagExtendRights;
        
        AuthorizationRef authRef = NULL;
        OSStatus status = AuthorizationCreate(&authRights, kAuthorizationEmptyEnvironment, flags, &authRef);
        if (status != errAuthorizationSuccess)
        {
            NSLog(@"Failed to create AuthorizationRef, return code %i", status);
        } else
        {
            CFErrorRef error = NULL;
            BOOL result = SMJobBless(kSMDomainSystemLaunchd, CFSTR(kHelperBundleID), authRef, &error);
            if (!result)
            {
                NSLog(@"SMJobBless Failed, error : %@",error);
            } else {
                NSLog(@"SMJobBless is done");
            }
        }
    } else {
        NSLog(@"helper tool is already registered!!");
    }
}

- (void)removeHelper {
    NSDictionary *helperInfo = (__bridge NSDictionary*)SMJobCopyDictionary(kSMDomainSystemLaunchd,
                                                                           CFSTR(kHelperBundleID));
    if (helperInfo)
    {
        AuthorizationItem authItem = { kSMRightBlessPrivilegedHelper, 0, NULL, 0 };
        AuthorizationRights authRights = { 1, &authItem };
        AuthorizationFlags flags = kAuthorizationFlagDefaults|
        kAuthorizationFlagInteractionAllowed|
        kAuthorizationFlagPreAuthorize|
        kAuthorizationFlagExtendRights;
        
        AuthorizationRef authRef = NULL;
        OSStatus status = AuthorizationCreate(&authRights, kAuthorizationEmptyEnvironment, flags, &authRef);
        if (status != errAuthorizationSuccess)
        {
            NSLog(@"Failed to create AuthorizationRef, return code %i", status);
        } else
        {
            CFErrorRef error = NULL;
            BOOL result = SMJobRemove(kSMDomainSystemLaunchd, CFSTR(kHelperBundleID), authRef, YES, &error);
            if (!result)
            {
                NSLog(@"SMJobBless Failed, error : %@",error);
            } else {
                NSLog(@"helper tool is removed successfully!!");
            }
        }
    }
}

#pragma mark notification
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    // open notification center feature
    return YES;
}
@end

