#import "andy_base64.h"
#import "XMPPJingle.h"
#import "ARDAppClient.h"

static NSString *_Initiator_sid = @"8695602648761356005";
static NSString *IsInitiator_id  = @"69RTS-7";


@implementation XMPPJingle

@synthesize delegate = _delegate;
@synthesize webrtc_delegate;

- (instancetype)initWithDelegate:(id <XMPPJingleDelegate>)delegate XMPPStream:(XMPPStream *)xmppStream;
{
    if (self = [super init])
    {
        _jingle_state = XMPPJINGLE_IDLE;
        _session_init_id = nil;
        _session_init_user = nil;
    }
    _delegate = delegate;
    
    NSString *domain = [xmppStream.myJID domain];
    NSString *myself = [xmppStream.myJID user];
    myself_id = [NSString stringWithFormat:@"%@@%@/Beem",myself,domain];
    
    _HasTerminateSignaling  = NO;
    _HasResultSignaling     = NO;
    _IsICECandidateCompleted    = NO;
    _session_resp_user=nil;
    _session_init_user=nil;
    
    
    return self;
}

 -(void)OutgoingCallSessionInit:(XMPPStream *)xmppStream InitUser:(NSString *)user_JID
{

    _session_resp_user = [NSString stringWithFormat:@"%@/Beem",user_JID];
    XMPPJID *toJID = [XMPPJID jidWithString:_session_resp_user];
    XMPPJID *from_JID = [XMPPJID jidWithString:myself_id];


    NSXMLElement *payload_type = [NSXMLElement elementWithName:@"payload-type"];
    
    [payload_type  addAttributeWithName:@"id" stringValue:@"8"];
    [payload_type  addAttributeWithName:@"name" stringValue:@"PCMA"];
    [payload_type  addAttributeWithName:@"channels" stringValue:@"1"];
    [payload_type  addAttributeWithName:@"clockrate" stringValue:@"8000"];
    
    NSXMLElement *description = [NSXMLElement elementWithName:@"description" xmlns:@"urn:xmpp:jingle:apps:rtp:1"];
    [description addChild:payload_type];
    
    NSXMLElement *transport = [NSXMLElement elementWithName:@"transport" xmlns:@"urn:xmpp:jingle:transports:ice-udp:2"];
    
    NSXMLElement *content = [NSXMLElement elementWithName:@"content"];
    [content addAttributeWithName:@"creator" stringValue:@"initiator"];
    [content addAttributeWithName:@"name" stringValue:@"Video"];
    [content addChild:description];
    [content addChild:transport];
    
    
    NSXMLElement *jingle = [NSXMLElement elementWithName:@"jingle" xmlns:@"urn:xmpp:jingle:1"];
    [jingle addAttributeWithName:@"initiator" stringValue:myself_id];
    [jingle addAttributeWithName:@"responder" stringValue:_session_resp_user];
    [jingle addAttributeWithName:@"action" stringValue:@"session-initiate"];
    [jingle addAttributeWithName:@"sid" stringValue:_Initiator_sid];
    
    [jingle addChild:content];
    
    XMPPIQ *iqResponse = [XMPPIQ iqWithType:@"set" to:toJID from:from_JID elementID:IsInitiator_id child:jingle];
    
    [xmppStream sendElement:iqResponse];
    
    _IsInitiator = YES;
    _jingle_state = XMPPJINGLE_OUTGOING_SESSION_INIT;
}

- (void)SendResultSignaling:(XMPPStream *)xmppStream InitUser:(NSString *)user
{
    XMPPJID *toJID;
    if(_IsInitiator)
        toJID = [XMPPJID jidWithString:_session_resp_user];
    else
        toJID = [XMPPJID jidWithString:_session_init_user];
    
    XMPPJID *fromJID = [XMPPJID jidWithString:myself_id];
    XMPPIQ *iqResponse = [XMPPIQ iqWithType:@"result" to:toJID from:fromJID elementID:_session_init_id child:nil];
    [xmppStream sendElement:iqResponse];

}
- (void)SendTerminateSignaling:(XMPPStream *)xmppStream InitUser:(NSString *)user
{
    NSXMLElement *jingle = [NSXMLElement elementWithName:@"jingle" xmlns:@"urn:xmpp:jingle:1"];
    
    XMPPJID *toJID;
    XMPPIQ *iqResponse;
    XMPPJID *fromJID = [XMPPJID jidWithString:myself_id];
    
    if(_IsInitiator)
    {
        toJID = [XMPPJID jidWithString:_session_resp_user];
        [jingle addAttributeWithName:@"initiator" stringValue:myself_id];                        //this is incoming call user.
        [jingle addAttributeWithName:@"responder" stringValue:_session_resp_user];
        
        [jingle addAttributeWithName:@"action" stringValue:@"session-terminate"];
        [jingle addAttributeWithName:@"sid" stringValue:_Initiator_sid];
        iqResponse = [XMPPIQ iqWithType:@"set" to:toJID from:fromJID elementID:IsInitiator_id child:jingle];
    }
    else
    {
        toJID = [XMPPJID jidWithString:_session_init_user];
        [jingle addAttributeWithName:@"initiator" stringValue:_session_init_user];                        //this is incoming call user.
        [jingle addAttributeWithName:@"responder" stringValue:myself_id];
        
        [jingle addAttributeWithName:@"action" stringValue:@"session-terminate"];
        [jingle addAttributeWithName:@"sid" stringValue:_session_init_sid];
        iqResponse = [XMPPIQ iqWithType:@"set" to:toJID from:fromJID elementID:_session_init_id child:jingle];
    }
    
    //[xmppStream sendElement:iqResponse];
    [_delegate SendXMPPJinleSignaling:iqResponse];
}

- (void)IncomingCallSessionAccept:(XMPPStream *)xmppStream InitUser:(NSString *)user
{
    if(_jingle_state == XMPPJINGLE_INCOMING_SESSION_INIT)
    {
        [self SendResultSignaling:xmppStream InitUser:user];
        _jingle_state = XMPPJINGLE_INCOMING_SESSION_ACCEPT;
    }
    else
    {
        NSLog(@"IncomingCallSessionAccept wrong logic %d",_jingle_state);
    }
}
- (void) IncomingCallSessionReject:(XMPPStream *)xmppStream InitUser:(NSString *)user
{
    //call this function if user reject a incomming call
    if(_jingle_state == XMPPJINGLE_INCOMING_SESSION_INIT)
    {
        [self SendTerminateSignaling:xmppStream InitUser:user];
        _jingle_state = XMPPJINGLE_INCOMING_SESSION_REJECT;
    }
    else
    {
        NSLog(@"IncomingCallSessionReject wrong logic %d",_jingle_state);
    }
}

- (void) TerminateCurrentCall:(XMPPStream *)xmppStream InitUser:(NSString *)user
{
    [self SendTerminateSignaling:xmppStream InitUser:user];
    _jingle_state = XMPPJINGLE_TERMINATING;
    _HasTerminateSignaling  = NO;
    _HasResultSignaling =NO;
}


-(void)ParsePeerTransportInfo:(NSArray *)content
{
    if([content count])
    {
        NSXMLElement *element = [content objectAtIndex:0];
        NSArray *transport = [element elementsForName:@"transport"];
        NSUInteger i=[transport count];
        if(i)
        {
            NSXMLElement *transport_l = [transport lastObject];
            
            NSArray *candidate = [transport_l elementsForName:@"candidate"];
            if([candidate count])
            {
                NSXMLElement *ele = [candidate objectAtIndex:0];
                NSString *_sdp_tmp= [ele attributeStringValueForName:@"sdp"];
                NSString *_candidate= [ele attributeStringValueForName:@"candidate"];
                
                NSString *webrtc_sdp = __TEXT(_sdp_tmp);                     //base64 decode
                
                [webrtc_delegate SetRemoteSDP:webrtc_sdp];
                NSArray *_candidate_split = [_candidate componentsSeparatedByString:@":"];
                
                for (NSUInteger i = 0; i < [_candidate_split count];  i++)
                {
                    NSString *cc =[_candidate_split objectAtIndex:i];
                    NSArray *cc_e = [cc componentsSeparatedByString:@"%"];
                    if([cc_e count] == 3)
                    {
                        NSString *tbdecode = [cc_e lastObject];
                        NSString *_candidate_Str = __TEXT(tbdecode);     //base64 decode
                        
                        [webrtc_delegate SetRemoteCandinate:[cc_e objectAtIndex:0] id:[cc_e objectAtIndex:1] candidate:_candidate_Str];
                        
                    }
                }
            }
        }
    }
}


-(BOOL)ProcessJingleSignaling:(XMPPIQ *)iq XMPPStream:(XMPPStream *)xmppStream
{
	if([iq isSetIQ])
    {
    	NSXMLElement *iqChild = [iq childElement];
        if (iqChild)
        {
            NSString *action = [iqChild attributeStringValueForName:@"action"];
            if ([action isEqualToString:@"session-initiate"])
            {
                NSLog(@"---------------------------------------------------------------------------session-initiate %d",_jingle_state);
            	if(_jingle_state == XMPPJINGLE_IDLE || _jingle_state == XMPPJINGLE_TERMINATING)
            	{
            		//action
	            		
                    _session_init_user  = [iq attributeStringValueForName:@"from"];
                    _session_init_id      = [iq attributeStringValueForName:@"id"];
                    _session_init_sid    = [iqChild attributeStringValueForName:@"sid"];
                    
                    _jingle_state = XMPPJINGLE_INCOMING_SESSION_INIT;
	            	_IsInitiator = NO;
                    
                    //1. send message to top UI,
                    
                    [_delegate IncomingCallSignalingCallBack:_session_init_user];
                     
	            	return YES;
	            }
	            else
	            {
	            	//send terminate to peer side and skip the peer side result and terminate signaling
	            	
	            	return NO;
	            }
            }
            else if ([action isEqualToString:@"session-terminate"])
            {
                NSLog(@"---------------------------------------------------------------------------session-terminate %d",_jingle_state);
                
                NSString *init_user  = [iq attributeStringValueForName:@"from"];

            	if (_jingle_state == XMPPJINGLE_INCOMING_SESSION_REJECT)
            	{
            		//This is a terminate confirm evnet.
            		//send result signaling.
                    
                    [self SendResultSignaling:xmppStream InitUser:init_user];
                    _jingle_state = XMPPJINGLE_IDLE;
                }
                else if(XMPPJINGLE_TERMINATING == _jingle_state)
                {
                    //in this case, we terminate actively the Call by local User.
                    //and we got terminate signaling from peer side.
                    //send result signaling.
                    [self SendResultSignaling:xmppStream InitUser:_session_init_user];
                    _jingle_state = XMPPJINGLE_IDLE;
                    
                }
                else if(_jingle_state == XMPPJINGLE_OUTGOING_SESSION_INIT || _jingle_state == XMPPJINGLE_OUTGOING_SESSION_INIT)
                {
                    //the peer side reject this outgoing video call.
                    //inform UI to stop webrtc and UI.
                    [_delegate OutgoingCallRejectSignalingCallBack:init_user];
                    
                    //send result signaling to peer side.
                    [self SendResultSignaling:xmppStream InitUser:init_user];
                    _jingle_state = XMPPJINGLE_IDLE;
                }
            	else if(_jingle_state != XMPPJINGLE_TERMINATING)
                {
                    
                    //this case means, the peer side actively hangup the call.
                    //1. hangup local call
                    //send terminate signaling
                    //send result signaling
                    [_delegate TerminateCallSignalingCallBack:init_user];
                    
                    [self SendTerminateSignaling: xmppStream InitUser:init_user];
                    [self SendResultSignaling:xmppStream InitUser:init_user];
                    _jingle_state = XMPPJINGLE_IDLE;
                }
            	return YES;
            }
            else if([action isEqualToString:@"transport-info"])
            {
                NSLog(@"---------------------------------------------------------------------------transport-info %d",_jingle_state);
            	if(_jingle_state == XMPPJINGLE_INCOMING_SESSION_ACCEPT)
            	{
                    //in this case, we got the peer side transport info.
                    //now we need set it to Webrtc SDP;
                    NSArray *content = [iqChild elementsForName:@"content"];
                    [self ParsePeerTransportInfo:content];
                    
                    _jingle_state = XMPPJINGLE_INCOMING_TRANSPORT_INFO;
            	}
                else if(_jingle_state == XMPPJINGLE_OUTGOING_SESSION_ACCEPT)
                {
                    NSArray *content = [iqChild elementsForName:@"content"];
                    [self ParsePeerTransportInfo:content];
                    _jingle_state = XMPPJINGLE_OUTGOING_TRANSPORT_INFO;
                }
                return YES;
            }
        }
    }
    else if([iq isResultIQ])
    {
        NSLog(@"---------------------------------------------------------------------------ResultIQ %d",_jingle_state);

        if(_jingle_state == XMPPJINGLE_OUTGOING_SESSION_INIT)
		{
		    //enable SDP send or send SDP directly.
			_jingle_state = XMPPJINGLE_OUTGOING_SESSION_ACCEPT;
            [self SendTransportInfoSignaling];
            

	    }
        else if(_jingle_state == XMPPJINGLE_INCOMING_SESSION_REJECT )
        {
            //we 
            _jingle_state = XMPPJINGLE_IDLE;
        }
	    else  if(XMPPJINGLE_TERMINATING != _jingle_state && _jingle_state != XMPPJINGLE_IDLE)
	    {
	    	//Just return Yes, no any action needed.
            NSLog(@"---------------------------------------------------------------------------Wrong logic");
            
        }
        return YES;
	}
    return NO;
}

-(void)SendTransportInfoSignaling
{
    if(_IsInitiator == YES)
    {
        if((_jingle_state != XMPPJINGLE_OUTGOING_SESSION_ACCEPT) && (_jingle_state != XMPPJINGLE_OUTGOING_TRANSPORT_INFO))
            return;
    }
   if([_sdp length] && _IsICECandidateCompleted == YES)
    {
    	XMPPJID *toJID;
	    XMPPJID *fromJID = [XMPPJID jidWithString:myself_id];
	    
	    NSXMLElement *jingle = [NSXMLElement elementWithName:@"jingle" xmlns:@"urn:xmpp:jingle:1"];
	    
	    if(_IsInitiator == YES)
	    {
            toJID= [XMPPJID jidWithString:_session_resp_user];
	        [jingle addAttributeWithName:@"initiator" stringValue:myself_id];
	        [jingle addAttributeWithName:@"responder" stringValue:_session_resp_user];
	        [jingle addAttributeWithName:@"action" stringValue:@"transport-info"];
	        [jingle addAttributeWithName:@"sid" stringValue:_Initiator_sid];
	    }
	    else
	    {
            toJID = [XMPPJID jidWithString:_session_init_user];
	        [jingle addAttributeWithName:@"initiator" stringValue:_session_init_user];
	        [jingle addAttributeWithName:@"responder" stringValue:myself_id];
	        [jingle addAttributeWithName:@"action" stringValue:@"transport-info"];
	        [jingle addAttributeWithName:@"sid" stringValue:_session_init_sid];
	    }
	    NSXMLElement *payload_type = [NSXMLElement elementWithName:@"payload-type"];
	    
	    [payload_type  addAttributeWithName:@"id" stringValue:@"8"];
	    [payload_type  addAttributeWithName:@"name" stringValue:@"PCMA"];
	    [payload_type  addAttributeWithName:@"channels" stringValue:@"1"];
	    [payload_type  addAttributeWithName:@"clockrate" stringValue:@"8000"];
	    
	    NSXMLElement *description = [NSXMLElement elementWithName:@"description" xmlns:@"urn:xmpp:jingle:apps:rtp:1"];
	    [description addChild:payload_type];
	    
	    NSXMLElement *transport = [NSXMLElement elementWithName:@"transport" xmlns:@"urn:xmpp:jingle:transports:ice-udp:2"];
	    
	    NSXMLElement *candidate = [NSXMLElement elementWithName:@"candidate" ];
	    [candidate addAttributeWithName:@"generation" stringValue:@"0"];
	    [candidate addAttributeWithName:@"ip" stringValue:@"null"];
	    [candidate addAttributeWithName:@"port" stringValue:@"0"];
	    [candidate addAttributeWithName:@"network" stringValue:@"0"];
	    [candidate addAttributeWithName:@"username" stringValue:@"null"];
	    [candidate addAttributeWithName:@"password" stringValue:@"null"];
	    [candidate addAttributeWithName:@"preference" stringValue:@"0"];
	    [candidate addAttributeWithName:@"type" stringValue:@"host"];
	    [candidate addAttributeWithName:@"sdp" stringValue:_sdp];
	    [candidate addAttributeWithName:@"candidate" stringValue:_ICECandidate];
	    
	    NSXMLElement *content = [NSXMLElement elementWithName:@"content"];
	    [content addAttributeWithName:@"creator" stringValue:@"initiator"];
	    [content addAttributeWithName:@"name" stringValue:@"Video"];
	    [content addChild:description];
	    [transport addChild:candidate];
	    [content addChild:transport];
	    
	    [jingle addChild:content];
	    
	    XMPPIQ *iqResponse = [XMPPIQ iqWithType:@"set" to:toJID from:fromJID elementID:@"f4xqn-6" child:jingle];
	    
	    [_delegate SendXMPPJinleSignaling:iqResponse];
	    
	    _IsICECandidateCompleted = NO;
	    _sdp=nil;
	    _ICECandidate = nil;
	}
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark XMPPJingleSingalingDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

-(void)GatheringLocaICECandidateCompleted
{
    _IsICECandidateCompleted = YES;
     [self SendTransportInfoSignaling];
}

-(void)SaveLocalSDP:(NSString *)sdp
{
    _sdp = __BASE64( sdp );
    [self SendTransportInfoSignaling];
}
-(void)GatheringLocaICECandidate:(NSString *)id candidate:(NSString *)candidate label:(NSString *)label
{
    //save all local candidate and send to peer side when condition ready.
    NSString *_base64_candidate = __BASE64( candidate );
    if(0 == [_ICECandidate length])
    {
        _ICECandidate = [NSString stringWithFormat:@"%@%%%@%%%@:",id,label,_base64_candidate];
    }
    else
    {
        NSString *_temp = [NSString stringWithFormat:@"%@%%%@%%%@:",id,label,_base64_candidate];
        _ICECandidate = [_ICECandidate stringByAppendingString:_temp];
    }
}

//when User actively terminate the call, by this API to inform peer side, we are terminating it.
-(void)SendXMPPTerminateSignaling
{
     if(XMPPJINGLE_TERMINATING != _jingle_state && _jingle_state != XMPPJINGLE_IDLE)
         [self TerminateCurrentCall:nil InitUser:nil];
}
@end
