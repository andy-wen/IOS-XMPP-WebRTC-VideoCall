#import "RootViewController.h"
#import "iPhoneXMPPAppDelegate.h"
#import "SettingsViewController.h"

#import "XMPPFramework.h"
#import "DDLog.h"
#import "ModalAlert.h"

// Log levels: off, error, warn, info, verbose
#if DEBUG
  static const int ddLogLevel = LOG_LEVEL_VERBOSE;
#else
  static const int ddLogLevel = LOG_LEVEL_INFO;
#endif

@implementation RootViewController

-(void)viewDidLoad
{
    [super viewDidLoad];
    [self appDelegate].rootview_delegate = self;
}


- (BOOL)KickOffVideoCall:(NSString *)user
{
    NSString *str1 = [user stringByReplacingOccurrencesOfString:@"@" withString:@"\0"];
    NSString *str = [NSString stringWithFormat:@"Imcoming Call: %@",str1];
    //play system auto
    
    if([ModalAlert ask:str] == YES)
    {

        videoCallViewController =  [[ARDVideoCallViewController alloc] initForJingle:user XMPPApp:[self appDelegate] IsInitiator:NO];

        videoCallViewController.modalTransitionStyle =  UIModalTransitionStyleCrossDissolve;
        [self presentViewController:videoCallViewController
                       animated:YES
                     completion:nil];
    
        NSLog(@"KickOffVideoCall");
        
        //send reply signaling
        [[self appDelegate] IncomingCallSessionAccept:user];
        
        return YES;
    }
    else
    {
        //send terminate signaling
        [[self appDelegate] IncomingCallSessionReject:user];
    }
    return NO;
}

- (void)TerminateVideoCall
{
        if(videoCallViewController != nil)
        {
            [videoCallViewController hangup];
            videoCallViewController = nil;
        }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Accessors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (iPhoneXMPPAppDelegate *)appDelegate
{
	return (iPhoneXMPPAppDelegate *)[[UIApplication sharedApplication] delegate];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark View lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
  
	UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 400, 44)];
	titleLabel.backgroundColor = [UIColor clearColor];
	titleLabel.textColor = [UIColor darkTextColor];
	titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
	titleLabel.numberOfLines = 1;
	titleLabel.adjustsFontSizeToFitWidth = YES;
	titleLabel.textAlignment = NSTextAlignmentCenter;

	if ([[self appDelegate] connect]) 
	{
		titleLabel.text = [[[[self appDelegate] xmppStream] myJID] bare];
	} else
	{
		titleLabel.text = @"No JID";
	}
	
	[titleLabel sizeToFit];

	self.navigationItem.titleView = titleLabel;
}

- (void)viewWillDisappear:(BOOL)animated
{
	//[[self appDelegate] disconnect];
	//[[[self appDelegate] xmppvCardTempModule] removeDelegate:self];
	
	[super viewWillDisappear:animated];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSFetchedResultsController
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSFetchedResultsController *)fetchedResultsController
{
	if (fetchedResultsController == nil)
	{
		NSManagedObjectContext *moc = [[self appDelegate] managedObjectContext_roster];
		
		NSEntityDescription *entity = [NSEntityDescription entityForName:@"XMPPUserCoreDataStorageObject"
		                                          inManagedObjectContext:moc];
		
		NSSortDescriptor *sd1 = [[NSSortDescriptor alloc] initWithKey:@"sectionNum" ascending:YES];
		NSSortDescriptor *sd2 = [[NSSortDescriptor alloc] initWithKey:@"displayName" ascending:YES];
		
		NSArray *sortDescriptors = @[sd1, sd2];
		
		NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
		[fetchRequest setEntity:entity];
		[fetchRequest setSortDescriptors:sortDescriptors];
		[fetchRequest setFetchBatchSize:10];
		
		fetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
		                                                               managedObjectContext:moc
		                                                                 sectionNameKeyPath:@"sectionNum"
		                                                                          cacheName:nil];
		[fetchedResultsController setDelegate:self];
		
		
		NSError *error = nil;
		if (![fetchedResultsController performFetch:&error])
		{
			DDLogError(@"Error performing fetch: %@", error);
		}
	
	}
	
	return fetchedResultsController;
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
	[[self tableView] reloadData];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableViewCell helpers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (void)configurePhotoForCell:(UITableViewCell *)cell user:(XMPPUserCoreDataStorageObject *)user
{
	// Our xmppRosterStorage will cache photos as they arrive from the xmppvCardAvatarModule.
	// We only need to ask the avatar module for a photo, if the roster doesn't have it.
	
	if (user.photo != nil)
	{
		cell.imageView.image = user.photo;
	} 
	else
	{
		NSData *photoData = [[[self appDelegate] xmppvCardAvatarModule] photoDataForJID:user.jid];

		if (photoData != nil)
			cell.imageView.image = [UIImage imageWithData:photoData];
		else
			cell.imageView.image = [UIImage imageNamed:@"defaultPerson"];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark UITableView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return [[[self fetchedResultsController] sections] count];
}

- (NSString *)tableView:(UITableView *)sender titleForHeaderInSection:(NSInteger)sectionIndex
{
	NSArray *sections = [[self fetchedResultsController] sections];
	
	if (sectionIndex < [sections count])
	{
		id <NSFetchedResultsSectionInfo> sectionInfo = sections[sectionIndex];
        
		int section = [sectionInfo.name intValue];
		switch (section)
		{
			case 0  : return @"Available";
			case 1  : return @"Away";
			default : return @"Offline";
		}
	}
	
	return @"";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
	NSArray *sections = [[self fetchedResultsController] sections];
	
	if (sectionIndex < [sections count])
	{
		id <NSFetchedResultsSectionInfo> sectionInfo = sections[sectionIndex];
		return sectionInfo.numberOfObjects;
	}
	
	return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *CellIdentifier = @"Cell";
	
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil)
	{
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
		                               reuseIdentifier:CellIdentifier];
	}
	
	XMPPUserCoreDataStorageObject *user = [[self fetchedResultsController] objectAtIndexPath:indexPath];
	
	cell.textLabel.text = user.displayName;
	[self configurePhotoForCell:cell user:user];
	
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    XMPPUserCoreDataStorageObject *user = [[self fetchedResultsController] objectAtIndexPath:indexPath];
    NSInteger state = [user.sectionNum integerValue];
    if (state == 0 || state == 1)   //Available & Away.
    {
        NSLog(@"Andy Selected %d",state);
        [self performSelectorOnMainThread:@selector(doDealWithSelectionAtIndex:) withObject:indexPath waitUntilDone:NO];
    }
    else
      NSLog(@"Andy Selected state %d",state);

}

- (void)doDealWithSelectionAtIndex:(NSIndexPath *)indexPath
{
    XMPPUserCoreDataStorageObject *user = [[self fetchedResultsController] objectAtIndexPath:indexPath];
    
    NSString *str = [NSString stringWithFormat:@"Init a VideCall with: %@",user.displayName];
    
    if([ModalAlert ask:str] == YES)
    {
        NSString *bareJID = [user.jid bare];
        NSLog(@"Andy Selected 2 %@ %@ %d",bareJID,user.displayName,3);
        //Send session init signaling to peer side.
        [[self appDelegate] VideoCallSessionInit:user.jidStr];
        // Kick off the video call.
        videoCallViewController =  [[ARDVideoCallViewController alloc] initForJingle:user.jidStr XMPPApp:[self appDelegate] IsInitiator:YES];
        videoCallViewController.modalTransitionStyle =  UIModalTransitionStyleCrossDissolve;
        [self presentViewController:videoCallViewController
                           animated:YES
                         completion:nil];
        
       // [[RTCWorker sharedInstance] startRTCTaskAsInitiator:YES withTarget:bareJID];
    }
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (IBAction)settings:(id)sender
{
	[self.navigationController presentViewController:[[self appDelegate] settingsViewController] animated:YES completion:NULL];
}


//The following code is add by Andy.Wen
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPJingleViewDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)XMPPJinle_IncomingVideoCall_SessionInit:(NSString *)user_JID
{
    [self performSelectorOnMainThread:@selector(KickOffVideoCall:) withObject:user_JID waitUntilDone:NO];
        
    return YES;
}


- (BOOL)XMPPJinle_IncomingVideoCall_SessionTerminate
{
    [self performSelectorOnMainThread:@selector(TerminateVideoCall) withObject:nil waitUntilDone:NO];
    return YES;
}

- (void)XMPPJinle_OutgoingVideoCall_SessionReject:(NSString *)user_JID
{
     [self performSelectorOnMainThread:@selector(TerminateVideoCall) withObject:nil waitUntilDone:NO];
}
@end
