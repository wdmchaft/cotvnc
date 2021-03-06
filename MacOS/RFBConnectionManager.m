/* Copyright (C) 1998-2000  Helmut Maierhofer <helmut.maierhofer@chello.at>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

#import "KeyChain.h"
#import "RFBConnectionManager.h"
#import "RFBConnection.h"
#import "PrefController.h"
#import "ProfileManager.h"
#import "Profile.h"
#import "rfbproto.h"
#import "vncauth.h"
#import "ServerDataViewController.h"
#import "ServerFromPrefs.h"
#import "ServerStandAlone.h"
#import "ServerDataManager.h"

@implementation RFBConnectionManager

+ (id)sharedManager
{ 
	static id sInstance = nil;
	if ( ! sInstance )
	{
		sInstance = [[self alloc] initWithWindowNibName: @"ConnectionDialog"];
		NSParameterAssert( sInstance != nil );
		
		[sInstance wakeup];
		
		[[NSNotificationCenter defaultCenter] addObserver:sInstance
												 selector:@selector(applicationWillTerminate:)
													 name:NSApplicationWillTerminateNotification object:NSApp];
	}
	return sInstance;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	[self release];
}

- (void)reloadServerArray
{
    NSEnumerator *serverEnumerator = [[ServerDataManager sharedInstance] getServerEnumerator];
	id<IServerData> server;
	
	[mOrderedServerNames removeAllObjects];
	while ( server = [serverEnumerator nextObject] )
	{
		[mOrderedServerNames addObject:[server name]];
	}
	
	[mOrderedServerNames sortUsingSelector:@selector(caseInsensitiveCompare:)];
}

- (void)wakeup
{
	// make sure our window is loaded
	[self window];
	[self setWindowFrameAutosaveName: @"login"];
	
	mDisplayGroups = NO;
	mLaunchedByURL = NO;
	
	mOrderedServerNames = [[NSMutableArray alloc] init];
	[self reloadServerArray];
	
	mServerCtrler = [[ServerDataViewController alloc] init];
	[mServerCtrler setConnectionDelegate:self];

    sigblock(sigmask(SIGPIPE));
    connections = [[NSMutableArray alloc] init];
    [[ProfileManager sharedManager] wakeup];
    
	NSBox *serverCtrlerBox = [mServerCtrler box];
	[serverCtrlerBox retain];
	[serverCtrlerBox removeFromSuperview];
	
    // figure out whether the size has changed in order to ease localization
    NSSize originalSize = [serverDataBoxLocal frame].size;
    NSSize newSize = [serverCtrlerBox frame].size;
    NSSize deltaSize = NSMakeSize( newSize.width - originalSize.width, newSize.height - originalSize.height );
    
	// I'm hardcoding the border so that I can use a real border at design time so it can be seen easily
	[serverDataBoxLocal setBorderType:NSNoBorder];
    [serverDataBoxLocal setFrameSize: newSize];
	[serverDataBoxLocal setContentView:serverCtrlerBox];
	[serverCtrlerBox release];
	
    // resize our window if necessary
    NSWindow *window = [serverDataBoxLocal window];
    NSRect oldFrame = [window frame];
    NSSize newFrameSize = {oldFrame.size.width + deltaSize.width, oldFrame.size.height + deltaSize.height };
    NSRect newFrame = { oldFrame.origin, newFrameSize };
    NSView *contentView = [window contentView];
    BOOL didAutoresize = [contentView autoresizesSubviews];
    [contentView setAutoresizesSubviews: NO];
    [window setFrame: newFrame display: NO];
    [contentView setAutoresizesSubviews: didAutoresize];

    [serverListBox retain];
	[serverListBox removeFromSuperview];
	[serverListBox setBorderType:NSNoBorder];
	[splitView addSubview:serverListBox];
	// we now own serverListBox and are responsible for releasing it
	
	[serverGroupBox retain];
	[serverGroupBox removeFromSuperview];
	[serverGroupBox setBorderType:NSNoBorder];
	// we now own serverGroupBox and are responsible for releasing it
	
	[splitView adjustSubviews];
	[self useRendezvous: [[PrefController sharedController] usesRendezvous]];
}

- (BOOL)runFromCommandLine
{
    NSProcessInfo *procInfo = [NSProcessInfo processInfo];
    NSArray *args = [procInfo arguments];
    int i, argCount = [args count];
    NSString *arg;
	
	ServerFromPrefs* cmdlineServer = [[[ServerFromPrefs alloc] init] autorelease];
	Profile* profile = nil;
	ProfileManager *profileManager = [ProfileManager sharedManager];
	
	// Check our arguments.  Args start at 0, which is the application name
	// so we start at 1.  arg count is the number of arguments, including
	// the 0th argument.
    for (i = 1; i < argCount; i++)
	{
		arg = [args objectAtIndex:i];
		
		if ([arg hasPrefix:@"-psn"])
		{
			// Called from the finder.  Do nothing.
			continue;
		} 
		else if ([arg hasPrefix:@"--PasswordFile"])
		{
			if (i + 1 >= argCount) [self cmdlineUsage];
			NSString *passwordFile = [args objectAtIndex:++i];
			char *decrypted_password = vncDecryptPasswdFromFile((char*)[passwordFile cString]);
			if (decrypted_password == NULL)
			{
				NSLog(@"Cannot read password from file.");
				exit(1);
			} 
			else
			{
				[cmdlineServer setPassword: [NSString stringWithCString:decrypted_password]];
				free(decrypted_password);
			}
		}
		else if ([arg hasPrefix:@"--FullScreen"])
			[cmdlineServer setFullscreen: YES];
		else if ([arg hasPrefix:@"--ViewOnly"])
			[cmdlineServer setViewOnly: YES];
		else if ([arg hasPrefix:@"--Display"])
		{
			if (i + 1 >= argCount) [self cmdlineUsage];
			int display = [[args objectAtIndex:++i] intValue];
			[cmdlineServer setDisplay: display];
		}
		else if ([arg hasPrefix:@"--Profile"])
		{
			if (i + 1 >= argCount) [self cmdlineUsage];
			NSString *profileName = [args objectAtIndex:++i];
			if ( ! [profileManager profileWithNameExists: profileName] )
			{
				NSLog(@"Cannot find a profile with the given name: \"%@\".", profileName);
				exit(1);
			}
			profile = [profileManager profileNamed: profileName];
		}
		else if ([arg hasPrefix:@"-"])
			[self cmdlineUsage];
		else if ([arg hasPrefix:@"-?"] || [arg hasPrefix:@"-help"] || [arg hasPrefix:@"--help"])
			[self cmdlineUsage];
		else
		{
			[cmdlineServer setHostAndPort: arg];
			
			mRunningFromCommandLine = YES;
		} 
    }
	
	if ( mRunningFromCommandLine )
	{
		if ( nil == profile )
			profile = [profileManager defaultProfile];	
		[self createConnectionWithServer:cmdlineServer profile:profile owner:self];
		return YES;
	}
	return NO;
}

- (void)runNormally
{
    NSString* lastHostName = [[PrefController sharedController] lastHostName];

	if( nil != lastHostName )
	    [serverList setStringValue: lastHostName];
	[self selectedHostChanged];
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver: self 
		   selector: @selector(updateProfileList:) 
			   name: ProfileAddDeleteNotification 
			 object: nil];
	[nc addObserver: self 
		   selector: @selector(serverListDidChange:) 
			   name: ServerListChangeMsg 
			 object: nil];
	
	// So we can tell when the serverList finished changing
	[nc addObserver:self 
		   selector: @selector(cellTextDidEndEditing:) 
			   name: NSControlTextDidEndEditingNotification 
			 object: serverList];
	[nc addObserver:self 
		   selector: @selector(cellTextDidBeginEditing:) 
			   name: NSControlTextDidBeginEditingNotification 
			 object: serverList];

	[self showConnectionDialog: nil];
}

- (void)cmdlineUsage
{
    fprintf(stderr, "\nUsage: Chicken of the VNC [options] [host:port]\n\n");
    fprintf(stderr, "options:\n\n");
    fprintf(stderr, "--PasswordFile <password-file>\n");
    fprintf(stderr, "--Profile <profile-name>\n");
    fprintf(stderr, "--Display <display-number>\n");
    fprintf(stderr, "--FullScreen\n");
	fprintf(stderr, "--ViewOnly\n");
    exit(1);
}

- (void)showNewConnectionDialog:(id)sender
{
	ServerDataViewController* viewCtrlr = [[ServerDataViewController alloc] initWithReleaseOnCloseOrConnect];
	[viewCtrlr setConnectionDelegate:[RFBConnectionManager sharedManager]];
	
	ServerStandAlone* server = [[[ServerStandAlone alloc] init] autorelease];
	
	[viewCtrlr setServer:server];
	[[viewCtrlr window] makeKeyAndOrderFront:self];
}

- (void)showConnectionDialog: (id)sender
{
	[[self window] makeFirstResponder: serverListBox];
	[[self window] makeKeyAndOrderFront:self];
}

- (void)dealloc
{
	[[NSUserDefaults standardUserDefaults] synchronize];
    [connections release];
	[mServerCtrler release];
	[mOrderedServerNames release];
	[serverListBox release];
	[serverGroupBox release];
    [super dealloc];
}

- (id<IServerData>)selectedServer
{
	return [[ServerDataManager sharedInstance] getServerWithName:[mOrderedServerNames objectAtIndex:[serverList selectedRow]]];
}

- (void)selectedHostChanged
{	
	NSParameterAssert( mServerCtrler != nil );

	id<IServerData> selectedServer = [self selectedServer];
	[mServerCtrler setServer:selectedServer];
	
	
	[serverDeleteBtn setEnabled: [selectedServer doYouSupport:DELETE]];
}

- (NSString*)translateDisplayName:(NSString*)aName forHost:(NSString*)aHost
{
	/* change */
    NSDictionary* hostDictionaryList = [[PrefController sharedController] hostInfo];
    NSDictionary* hostDictionary = [hostDictionaryList objectForKey:aHost];
    NSDictionary* names = [hostDictionary objectForKey:@"NameTranslations"];
    NSString* news;
	
    if((news = [names objectForKey:aName]) == nil) {
        news = aName;
    }
    return news;
}

- (void)setDisplayNameTranslation:(NSString*)translation forName:(NSString*)aName forHost:(NSString*)aHost
{
    PrefController* prefController = [PrefController sharedController];
    NSMutableDictionary* hostDictionaryList, *hostDictionary, *names;

    hostDictionaryList = [[[prefController hostInfo] mutableCopy] autorelease];
    if(hostDictionaryList == nil) {
        hostDictionaryList = [NSMutableDictionary dictionary];
    }
    hostDictionary = [[[hostDictionaryList objectForKey:aHost] mutableCopy] autorelease];
    if(hostDictionary == nil) {
        hostDictionary = [NSMutableDictionary dictionary];
    }
    names = [[[hostDictionary objectForKey:@"NameTranslations"] mutableCopy] autorelease];
    if(names == nil) {
        names = [NSMutableDictionary dictionary];
    }
    [names setObject:translation forKey:aName];
    [hostDictionary setObject:names forKey:@"NameTranslations"];
    [hostDictionaryList setObject:hostDictionary forKey:aHost];
    [prefController setHostInfo:hostDictionaryList];
}

- (void)removeConnection:(id)aConnection
{
    [aConnection retain];
    [connections removeObject:aConnection];
    [aConnection autorelease];
    if ( mRunningFromCommandLine ) 
		[NSApp terminate:self];
	else if ( 0 == [connections count] )
		[self showConnectionDialog:nil];
}

- (bool)connect:(id<IServerData>)server;
{
    Profile* profile = [[ProfileManager sharedManager] profileNamed:[server lastProfile]];
    
    // Only close the open dialog of the connection was successful
	bool bRetVal = [self createConnectionWithServer:server profile:profile owner:self];
    if( YES == bRetVal && server == [self selectedServer])
	{
        [[self window] orderOut:self];
    }
	
	return bRetVal;
}

/* Do the work of creating a new connection and add it to the list of connections. */
- (BOOL)createConnectionWithServer:(id<IServerData>) server profile:(Profile *) someProfile owner:(id) someOwner
{
	/* change */
    RFBConnection* theConnection;
    bool returnVal = YES;

    theConnection = [[[RFBConnection alloc] initWithServer:server profile:someProfile owner:someOwner] autorelease];
    if(theConnection) {
        [theConnection setManager:self];
        [connections addObject:theConnection];
    }
    else {
        returnVal = NO;
    }
    
    return returnVal;
}

- (BOOL)createConnectionWithFileHandle:(NSFileHandle*)file server:(id<IServerData>) server profile:(Profile *) someProfile owner:(id) someOwner
{
	/* change */
    RFBConnection* theConnection;
    bool returnVal = YES;

    theConnection = [[[RFBConnection alloc] initWithFileHandle:file server:server profile:someProfile owner:someOwner] autorelease];
    if(theConnection) {
        [theConnection setManager:self];
        [connections addObject:theConnection];
    }
    else {
        returnVal = NO;
    }
    
    return returnVal;
}


- (IBAction)addServer:(id)sender
{
	ServerDataManager *serverDataManager = [ServerDataManager sharedInstance];
	id<IServerData> newServer = [serverDataManager createServerByName:NSLocalizedString(@"RFBDefaultServerName", nil)];
	NSString *newName = [newServer name];
	NSParameterAssert( newName != nil );
	
	NSEnumerator *serverEnumerator = [mOrderedServerNames objectEnumerator];
	[self reloadServerArray];
	
	int index = 0;
	NSString *name;
	while ( name = [serverEnumerator nextObject] )
	{
		if ( name && [name isEqualToString: newName] )
		{
			[serverList selectRow: index byExtendingSelection: NO];
			[serverList editColumn: 0 row: index withEvent: nil select: YES];
			break;
		}
		index++;
	}
}

- (IBAction)deleteSelectedServer:(id)sender
{
	[[ServerDataManager sharedInstance] removeServer:[self selectedServer]];
	
	[self reloadServerArray];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
//jshprefs    [self savePrefs];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
    // Don't bother caching - this won't happen often enough to matter.
    // If you  want to cache this, make a class so we can refactor it from everywhere else
    BOOL gIsJaguar = [NSString instancesRespondToSelector: @selector(decomposedStringWithCanonicalMapping)];

    // [[NSApp windows] count] is the best option, but it don't work pre-jaguar
    if ((gIsJaguar && ([[NSApp windows] count] == 0)) || ((!gIsJaguar) && (![self haveAnyConnections]))) {
        [[self window] makeKeyAndOrderFront:self];
    }
}

- (void)cellTextDidEndEditing:(NSNotification *)notif {
    [self selectedHostChanged];
}

- (void)cellTextDidBeginEditing:(NSNotification *)notif {
    [self selectedHostChanged];
}

// Jason added the following for full-screen windows
- (void)makeAllConnectionsWindowed {
	NSEnumerator *connectionEnumerator = [connections objectEnumerator];
	RFBConnection *thisConnection;

	while (thisConnection = [connectionEnumerator nextObject]) {
		if ([thisConnection connectionIsFullscreen])
			[thisConnection makeConnectionWindowed: self];
	}
}

- (BOOL)haveMultipleConnections {
    return [connections count] > 1;
}

- (BOOL)haveAnyConnections {
    return [connections count] > 0;
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if( serverList == aTableView )
	{
		return [mOrderedServerNames count];
	}
	else if( groupList == aTableView )
	{
		return [[ServerDataManager sharedInstance] groupCount];
	}
	
	return 0;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if( serverList == aTableView )
	{
		return [mOrderedServerNames objectAtIndex:rowIndex];
	}
	else if( groupList == aTableView )
	{
		// note - this isn't very efficient - jason
		return [[[[ServerDataManager sharedInstance] getGroupNameEnumerator] allObjects] objectAtIndex:rowIndex];
	}
	
	return NULL;	
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(int)row
{
	if( serverList == aTableView )
	{
		id<IServerData> server = [[ServerDataManager sharedInstance] getServerWithName:[mOrderedServerNames objectAtIndex:row]];
		
		return [server doYouSupport:EDIT_NAME];
	}
	else if( groupList == aTableView )
	{
		return NO;
	}
	
	return NO;	
}

- (void)afterSort:(id<IServerData>)server
{
	[[self window] makeFirstResponder:[self window]];
	
	[self reloadServerArray];
	NSEnumerator *serverEnumerator = [mOrderedServerNames objectEnumerator];
	
	int index = 0;
	NSString *name;
	while ( name = [serverEnumerator nextObject] )
	{
		if ( name && [name isEqualToString: [server name]] )
		{
			[serverList selectRow: index byExtendingSelection: NO];
			break;
		}
		index++;
	}
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(int)row
{
	if( serverList == aTableView )
	{
		NSString* serverName = object;
		id<IServerData> server = [[ServerDataManager sharedInstance] getServerWithName:[mOrderedServerNames objectAtIndex:row]];
		
		if( NO == [serverName isEqualToString:[server name]] )
		{
			[[self window] makeFirstResponder:[self window]];
			[server setName:serverName];
			
			// This insanity overrides the default select next behavior in the table
			[self performSelector:@selector(afterSort:) withObject:server afterDelay:0.0];
		}
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	NSTableView *view = [aNotification object];
	if( serverList == view )
	{
		[self selectedHostChanged];
	}
	else if( groupList == view )
	{
		[serverList reloadData];
	}
}

- (void)updateProfileList:(NSNotification*)notification
{
	[mServerCtrler updateView: notification];
}

- (void)serverListDidChange:(NSNotification*)notification
{
	[self reloadServerArray];
	[serverList reloadData];
	[self selectedHostChanged];
}

- (void)useRendezvous:(BOOL)useRendezvous
{
	[[ServerDataManager sharedInstance] useRendezvous: useRendezvous];
	
	NSParameterAssert( [[ServerDataManager sharedInstance] getUseRendezvous] == useRendezvous );
}

- (void)displayGroups:(bool)display
{
	if( display != mDisplayGroups )
	{
		mDisplayGroups = display;
		
		if( display )
		{
			[splitView addSubview:serverGroupBox positioned:NSWindowBelow relativeTo:serverListBox];
		}
		else
		{	
			[serverGroupBox removeFromSuperview];
		}
		
		[splitView adjustSubviews];
	}
}

- (void)setFrontWindowUpdateInterval: (NSTimeInterval)interval
{
	NSEnumerator *connectionEnumerator = [connections objectEnumerator];
	RFBConnection *thisConnection;
	NSWindow *keyWindow = [NSApp keyWindow];
	
	while (thisConnection = [connectionEnumerator nextObject]) {
		if ([thisConnection window] == keyWindow) {
			[thisConnection setFrameBufferUpdateSeconds: interval];
			break;
		}
	}
}

- (void)setOtherWindowUpdateInterval: (NSTimeInterval)interval
{
	NSEnumerator *connectionEnumerator = [connections objectEnumerator];
	RFBConnection *thisConnection;
	NSWindow *keyWindow = [NSApp keyWindow];
	
	while (thisConnection = [connectionEnumerator nextObject]) {
		if ([thisConnection window] != keyWindow) {
			[thisConnection setFrameBufferUpdateSeconds: interval];
		}
	}
}

- (BOOL)launchedByURL
{
	return mLaunchedByURL;
}

- (void)setLaunchedByURL:(bool)launchedByURL
{
	mLaunchedByURL = launchedByURL;
}

@end
