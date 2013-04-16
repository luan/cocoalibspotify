/*
 Copyright (c) 2011, Spotify AB
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of Spotify AB nor the names of its contributors may 
 be used to endorse or promote products derived from this software 
 without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL SPOTIFY AB BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT 
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, 
 OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "AppDelegate.h"
#import "SPPlaylistItem+SPPlaylistItemOfflineExtensions.h"

#error Please get an appkey.c file from developer.spotify.com and remove this error before building.
#include "appkey.c"

@implementation AppDelegate

@synthesize window = _window;

@synthesize playbackProgressSlider;
@synthesize userNameField;
@synthesize passwordField;
@synthesize loginSheet;
@synthesize trackTable;
@synthesize playbackManager;

-(void)applicationWillFinishLaunching:(NSNotification *)notification {

	[self willChangeValueForKey:@"session"];
	NSError *error = nil;
	[SPSession initializeSharedSessionWithApplicationKey:[NSData dataWithBytes:&g_appkey length:g_appkey_size]
											   userAgent:@"com.spotify.OfflinePlaylists"
										   loadingPolicy:SPAsyncLoadingImmediate
												   error:&error];
	if (error != nil) {
		NSLog(@"CocoaLibSpotify init failed: %@", error);
		abort();
	}

	[[SPSession sharedSession] setDelegate:self];
	self.playbackManager = [[SPPlaybackManager alloc] initWithPlaybackSession:[SPSession sharedSession]];

	[self didChangeValueForKey:@"session"];
	[self.window center];
	[self.window orderFront:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	// Insert code here to initialize your application

	[self addObserver:self
		   forKeyPath:@"playbackManager.trackPosition"
			  options:0
			  context:nil];

	[self addObserver:self
		   forKeyPath:@"selectedPlaylist"
			  options:0
			  context:nil];
	
	[self.trackTable setTarget:self];
	[self.trackTable setDoubleAction:@selector(tableViewWasDoubleClicked:)];
	
	[self performSelector:@selector(showLoginSheet) withObject:nil afterDelay:0.0];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	if ([SPSession sharedSession].connectionState == SP_CONNECTION_STATE_LOGGED_OUT ||
		[SPSession sharedSession].connectionState == SP_CONNECTION_STATE_UNDEFINED) 
		return NSTerminateNow;
	
	[[SPSession sharedSession] logout:^{
		[[NSApplication sharedApplication] replyToApplicationShouldTerminate:YES];
	}];
	return NSTerminateLater;
}

-(void)showLoginSheet {
	[NSApp beginSheet:self.loginSheet
	   modalForWindow:self.window
		modalDelegate:nil
	   didEndSelector:nil 
		  contextInfo:nil];
}

-(SPSession *)session {
	// For bindings
	return [SPSession sharedSession];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	
	// Invoked when the current playback position changed (see below). This is a bit of a workaround
	// to make sure we don't update the position slider while the user is dragging it around. If the position
	// slider was read-only, we could just bind its value to playbackManager.trackPosition.
	
    if ([keyPath isEqualToString:@"playbackManager.trackPosition"]) {
        if (![[self.playbackProgressSlider cell] isHighlighted]) {
			[self.playbackProgressSlider setDoubleValue:self.playbackManager.trackPosition];
		}

	} else if ([keyPath isEqualToString:@"selectedPlaylist"]) {
		self.sparseArray = [[SPSparseList alloc] initWithDataSource:self.selectedPlaylist];
		[self.trackTable reloadData];
	} else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (IBAction)quitFromLoginSheet:(id)sender {
	
	// Invoked by clicking the "Quit" button in the UI.
	
	[NSApp endSheet:self.loginSheet];
	[NSApp terminate:self];
}

- (IBAction)login:(id)sender {
	
	// Invoked by clicking the "Login" button in the UI.
	
	if ([[userNameField stringValue] length] > 0 && 
		[[passwordField stringValue] length] > 0) {
		
		[[SPSession sharedSession] attemptLoginWithUserName:[userNameField stringValue]
												   password:[passwordField stringValue]];
	} else {
		NSBeep();
	}
}

#pragma mark -
#pragma mark SPSessionDelegate Methods

-(void)sessionDidLoginSuccessfully:(SPSession *)aSession; {
	
	// Invoked by SPSession after a successful login.
	
	[self.loginSheet orderOut:self];
	[NSApp endSheet:self.loginSheet];
}

-(void)session:(SPSession *)aSession didFailToLoginWithError:(NSError *)error; {
    
	// Invoked by SPSession after a failed login.
	
    [NSApp presentError:error
         modalForWindow:self.loginSheet
               delegate:nil
     didPresentSelector:nil
            contextInfo:nil];
}

-(void)sessionDidLogOut:(SPSession *)aSession; {}
-(void)session:(SPSession *)aSession didEncounterNetworkError:(NSError *)error; {}
-(void)session:(SPSession *)aSession didLogMessage:(NSString *)aMessage; {}
-(void)sessionDidChangeMetadata:(SPSession *)aSession; {}

-(void)session:(SPSession *)aSession recievedMessageForUser:(NSString *)aMessage; {
	
	[[NSAlert alertWithMessageText:aMessage
					 defaultButton:@"OK"
				   alternateButton:@""
					   otherButton:@""
		 informativeTextWithFormat:@"This message was sent to you from the Spotify service."] runModal];
}

#pragma mark - TableView

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return self.sparseArray.count;
}

-(id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {

	SPPlaylistItem *item = self.sparseArray[row];

	if (item == nil) {
		[self.sparseArray loadObjectsInRange:NSMakeRange(row, 1) callback:^{
			[tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
								 columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
			return;
		}];
	}

	if ([tableColumn.identifier isEqualToString:@"name"]) {
		return [item.item name];
	} else {
		return [item offlineTrackStatus];
	}

}

#pragma mark -
#pragma mark Playback

- (void)tableViewWasDoubleClicked:(id)sender {
	
	// Invoked by clicking the "Play" button in the UI.
	
	NSInteger row = [self.trackTable clickedRow];
	if (row < 0) return;
	
	SPPlaylistItem *playlistItem = [self.sparseArray objectAtIndex:row];
	if (playlistItem.itemClass != [SPTrack class]) return;
	
	SPTrack *track = playlistItem.item;
	
	if (track != nil) {

		[SPAsyncLoading waitUntilLoaded:track timeout:kSPAsyncLoadingDefaultTimeout then:^(NSArray *loadedItems, NSArray *notLoadedItems) {

			if (!track.isLoaded) {
				[NSAlert alertWithMessageText:@"Track not loaded"
								defaultButton:@"OK"
							  alternateButton:nil
								  otherButton:nil
					informativeTextWithFormat:@"Track could not be played because it didn't load in time."];
				return;
			}

			[self.playbackManager playTrack:track callback:^(NSError *error) {
				if (error) [self.window presentError:error];
			}];
		}];
	}
}

-(IBAction)seekToPosition:(id)sender {
	
	// Invoked by dragging the position slider in the UI.
	if (self.playbackManager.currentTrack != nil && self.playbackManager.isPlaying) {
		[self.playbackManager seekToTrackPosition:[sender doubleValue]];
	}
}

- (IBAction)togglePlayPause:(id)sender {
	self.playbackManager.isPlaying = !self.playbackManager.isPlaying;
}

@end
