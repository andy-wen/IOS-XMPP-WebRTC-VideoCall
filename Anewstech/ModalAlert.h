#import <UIKit/UIKit.h> 


@interface ModalAlert : NSObject

+ (BOOL) ask: (NSString *) question;  
+ (BOOL) confirm:(NSString *) statement;  

@end  