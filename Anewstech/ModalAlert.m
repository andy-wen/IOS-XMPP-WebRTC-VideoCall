#import "ModalAlert.h"  
  
@interface ModalAlertDelegate : NSObject <UIAlertViewDelegate>  
{  
    CFRunLoopRef currentLoop;  
    NSUInteger index;  
}  
@property (readonly) NSUInteger index;  
@end  
  
@implementation ModalAlertDelegate  
@synthesize index;  
  
// Initialize with the supplied run loop  
-(id) initWithRunLoop: (CFRunLoopRef)runLoop   
{  
    if (self = [super init]) currentLoop = runLoop;  
    return self;  
}  
  
// User pressed button. Retrieve results  
-(void) alertView: (UIAlertView*)aView clickedButtonAtIndex: (NSInteger)anIndex   
{  
    index = anIndex;  
    CFRunLoopStop(currentLoop);  
}  
@end  
  
@implementation ModalAlert  
+(NSUInteger) queryWith: (NSString *)question button1: (NSString *)button1 button2: (NSString *)button2  
{  
    CFRunLoopRef currentLoop = CFRunLoopGetCurrent();  
      
    // Create Alert  
    ModalAlertDelegate *madelegate = [[ModalAlertDelegate alloc] initWithRunLoop:currentLoop];  
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:question message:nil delegate:madelegate cancelButtonTitle:button1 otherButtonTitles:button2, nil];  
    [alertView show];  
      
    // Wait for response  
    CFRunLoopRun();  
      
    // Retrieve answer  
    NSUInteger answer = madelegate.index;  
   
    return answer;  
}  
  
+ (BOOL) ask: (NSString *) question  
{  
    return  [ModalAlert queryWith:question button1: @"Reject" button2: @"Accept"];  
}  
  
+ (BOOL) confirm: (NSString *) statement  
{  
    return  [ModalAlert queryWith:statement button1: @"Cancel" button2: @"OK"];  
}  
@end  