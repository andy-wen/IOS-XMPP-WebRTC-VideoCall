//  

#import <Foundation/Foundation.h>  
  
#define __BASE64( text )          [AndyBase64 base64StringFromText:text]
#define __TEXT( base64 )        [AndyBase64 textFromBase64String:base64]
  
@interface AndyBase64 : NSObject
  
/*
 NSString -> base64 string
*/
+ (NSString *)base64StringFromText:(NSString *)text;
  
/*
 base64 string -> NSString
 */
+ (NSString *)textFromBase64String:(NSString *)base64;  
  
@end 