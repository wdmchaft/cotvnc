//
//  ServerFromPrefs.h
//  Chicken of the VNC
//
//  Created by Jared McIntyre on Sun May 1 2004.
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//


#import <Cocoa/Cocoa.h>

@protocol IServerData;
@protocol ConnectionDelegate;

@interface ServerDataViewController : NSWindowController
{
    IBOutlet NSTextField *display;
    IBOutlet NSTextField *hostName;
    IBOutlet NSTextField *password;
    IBOutlet NSPopUpButton *profilePopup;
    IBOutlet NSButton *rememberPwd;
    IBOutlet NSButton *shared;
	IBOutlet NSBox *box;
	IBOutlet NSButton *connectBtn;
	
	IBOutlet NSProgressIndicator *connectIndicator;
	IBOutlet NSTextField *connectIndicatorText;
	
	id<IServerData> mServer;
	id<ConnectionDelegate> mDelegate;
}

- (void)setServer:(id<IServerData>)server;
- (id<IServerData>)server;

- (void)setConnectionDelegate:(id<ConnectionDelegate>)delegate;

- (IBAction)hostChanged:(id)sender;
- (IBAction)passwordChanged:(id)sender;
- (IBAction)rememberPwdChanged:(id)sender;
- (IBAction)displayChanged:(id)sender;
- (IBAction)profileSelectionChanged:(id)sender;
- (IBAction)sharedChanged:(id)sender;
- (IBAction)connectToServer:(id)sender;

- (NSBox*)box;

- (void)controlTextDidEndEditing:(NSNotification*)notification;
- (void)updateView:(id)notification;

@end

@protocol ConnectionDelegate

- (void)connect:(id<IServerData>)server;

@end