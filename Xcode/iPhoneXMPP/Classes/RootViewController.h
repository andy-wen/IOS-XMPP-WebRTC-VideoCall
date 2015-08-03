#import <UIKit/UIKit.h>
#import <CoreData/CoreData.h>
#import "iPhoneXMPPAppDelegate.h"
#import "ARDVideoCallViewController.h"

@interface RootViewController : UITableViewController <NSFetchedResultsControllerDelegate,XMPPJingleViewDelegate>
{
	NSFetchedResultsController *fetchedResultsController;
    ARDVideoCallViewController *videoCallViewController;
}

- (IBAction)settings:(id)sender;
- (BOOL)KickOffVideoCall:(NSString *)user;

@end
