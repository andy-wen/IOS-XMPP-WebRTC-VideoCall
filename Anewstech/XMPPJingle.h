#import "XMPPFramework.h"


typedef enum {
  XMPPJINGLE_IDLE,
  XMPPJINGLE_INCOMING_SESSION_INIT,
  XMPPJINGLE_INCOMING_SESSION_ACCEPT,         //in this state, we are waiting the transport-info and to create answer.
  XMPPJINGLE_INCOMING_SESSION_REJECT,
  
  XMPPJINGLE_INCOMING_TRANSPORT_INFO,		//we have received remote transport-info.
  XMPPJINGLE_INCOMING_CONNECTED,			        //ICE connected and videocall ongoing
  XMPPJINGLE_INCOMING_DISCONNECTED,			//ICE disconnected or session_terminate or disconnect by user
   
  XMPPJINGLE_OUTGOING_SESSION_INIT,			//in this state, we are waiting the SESSION_RESULT by remote side.
  XMPPJINGLE_OUTGOING_SESSION_ACCEPT,		//when enter into this state, that means the remote side has accepted the call.
  XMPPJINGLE_OUTGOING_TRANSPORT_INFO,		//we have sent transport infto to remote side

  XMPPJINGLE_TERMINATING,

  XMPPJINGLE_NULLa
} XMPPJINGLE_STATE;

@protocol XMPPJingleSingalingDelegate;

@protocol XMPPJingleDelegate <NSObject>

-(void)IncomingCallSignalingCallBack:(NSString *) session_init_user;
-(void)TerminateCallSignalingCallBack:(NSString *) user;
-(void)OutgoingCallRejectSignalingCallBack:(NSString *) user;

-(void)SendXMPPJinleSignaling:(XMPPIQ *)iqResponse;
@end

//added by andy.wen
@protocol XMPPJingleWebRTCDelegate <NSObject>
@optional
- (BOOL)SetRemoteSDP:(NSString *)sdp;
- (BOOL)SetRemoteCandinate:(NSString *)type id:(NSString *)i candidate:(NSString *)c;

@end

@interface XMPPJingle : NSObject <XMPPJingleSingalingDelegate>
{
    BOOL _IsInitiator;
    BOOL _HasTerminateSignaling;
    BOOL _HasResultSignaling;
    BOOL _IsICECandidateCompleted;
    
    
    NSString *_session_resp_user;     //save the remote user when we create a video call.
    NSString *_session_init_id;
    NSString *_session_init_sid;
    NSString *_session_init_user;
    
    NSString *myself_id;
    
    NSString *_ICECandidate;
    NSString *_sdp;
    XMPPJINGLE_STATE _jingle_state;
    
     __weak id<XMPPJingleWebRTCDelegate> webrtc_delegate;
    
}
@property(nonatomic, weak) id<XMPPJingleDelegate> delegate;
@property (nonatomic, weak) id<XMPPJingleWebRTCDelegate> webrtc_delegate;

- (instancetype)initWithDelegate: (id <XMPPJingleDelegate>)delegate XMPPStream:(XMPPStream *)xmppStream;

- (void)IncomingCallSessionAccept:(XMPPStream *)xmppStream InitUser:(NSString *)user;
- (void)IncomingCallSessionReject:(XMPPStream *)xmppStream InitUser:(NSString *)user;

-(void)OutgoingCallSessionInit:(XMPPStream *)xmppStream InitUser:(NSString *)user_JID;

-(BOOL)ProcessJingleSignaling:(XMPPIQ *)iq XMPPStream:(XMPPStream *)xmppStream;

-(void)SendTransportInfoSignaling;

@end 

