/*
 * libjingle
 * Copyright 2014 Google Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice,
 *     this list of conditions and the following disclaimer in the documentation
 *     and/or other materials provided with the distribution.
 *  3. The name of the author may not be used to endorse or promote products
 *     derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "ARDAppClient+Internal.h"

#if defined(WEBRTC_IOS)
#import "RTCAVFoundationVideoSource.h"
#endif
#import "RTCICEServer.h"
#import "RTCMediaConstraints.h"
#import "RTCMediaStream.h"
#import "RTCPair.h"
#import "RTCPeerConnectionInterface.h"
#import "RTCVideoCapturer.h"
#import "RTCAVFoundationVideoSource.h"

#import "ARDAppEngineClient.h"
#import "ARDCEODTURNClient.h"
#import "ARDJoinResponse.h"
#import "ARDMessageResponse.h"
#import "ARDSDPUtils.h"

#import "ARDUtilities.h"
#import "ARDWebSocketChannel.h"
#import "RTCICECandidate+JSON.h"
#import "RTCSessionDescription+JSON.h"


static NSString * const kARDDefaultSTUNServerUrl =
    @"stun:anewstech.com:3478";
// TODO(tkchin): figure out a better username for CEOD statistics.
static NSString * const kARDTurnRequestUrl =
    @"http://anewstech.com:8091"
    @"/turn.php?username=iapprtc&key=4080218913";

static NSString * const kARDAppClientErrorDomain = @"ARDAppClient";
static NSInteger const kARDAppClientErrorUnknown = -1;
static NSInteger const kARDAppClientErrorRoomFull = -2;
static NSInteger const kARDAppClientErrorCreateSDP = -3;
static NSInteger const kARDAppClientErrorSetSDP = -4;
static NSInteger const kARDAppClientErrorInvalidClient = -5;
static NSInteger const kARDAppClientErrorInvalidRoom = -6;

@implementation ARDAppClient

@synthesize delegate = _delegate;
@synthesize state = _state;
@synthesize roomServerClient = _roomServerClient;
@synthesize channel = _channel;
@synthesize turnClient = _turnClient;
@synthesize peerConnection = _peerConnection;
@synthesize factory = _factory;
@synthesize messageQueue = _messageQueue;
@synthesize messageBuffer = _messageBuffer;
@synthesize isTurnComplete = _isTurnComplete;
@synthesize hasReceivedSdp  = _hasReceivedSdp;
@synthesize roomId = _roomId;
@synthesize clientId = _clientId;
@synthesize isInitiator = _isInitiator;
@synthesize iceServers = _iceServers;
@synthesize webSocketURL = _websocketURL;
@synthesize webSocketRestURL = _websocketRestURL;
@synthesize defaultPeerConnectionConstraints =
    _defaultPeerConnectionConstraints;
@synthesize isInitDone  = _isInitDone;

#ifdef _IOS_XMPP_JINGLE
@synthesize xmppjingle_signaling_delegate;
#endif

- (instancetype)init {
  if (self = [super init]) {
    _roomServerClient = [[ARDAppEngineClient alloc] init];
    NSURL *turnRequestURL = [NSURL URLWithString:kARDTurnRequestUrl];
    _turnClient = [[ARDCEODTURNClient alloc] initWithURL:turnRequestURL];
    [self configure];
  }
  return self;
}

- (instancetype)initWithDelegate:(id<ARDAppClientDelegate>)delegate {
  if (self = [super init]) {
      buffer_sdp_flag = 0;
    _roomServerClient = [[ARDAppEngineClient alloc] init];
    _delegate = delegate;
    NSURL *turnRequestURL = [NSURL URLWithString:kARDTurnRequestUrl];
    _turnClient = [[ARDCEODTURNClient alloc] initWithURL:turnRequestURL];
    [self configure];
  }
  return self;
}

// TODO(tkchin): Provide signaling channel factory interface so we can recreate
// channel if we need to on network failure. Also, make this the default public
// constructor.
- (instancetype)initWithRoomServerClient:(id<ARDRoomServerClient>)rsClient
                        signalingChannel:(id<ARDSignalingChannel>)channel
                              turnClient:(id<ARDTURNClient>)turnClient
                                delegate:(id<ARDAppClientDelegate>)delegate {
  NSParameterAssert(rsClient);
  NSParameterAssert(channel);
  NSParameterAssert(turnClient);
  if (self = [super init]) {
    _roomServerClient = rsClient;
    _channel = channel;
    _turnClient = turnClient;
    _delegate = delegate;
    [self configure];
  }
  return self;
}

- (void)configure {
  _factory = [[RTCPeerConnectionFactory alloc] init];
  _messageQueue = [NSMutableArray array];
  _iceServers = [NSMutableArray arrayWithObject:[self defaultSTUNServer]];
}

- (void)dealloc {
  [self disconnect];
}

- (void)setState:(ARDAppClientState)state {
  if (_state == state) {
    return;
  }
  _state = state;
  [_delegate appClient:self didChangeState:_state];
}

- (void)VideoCallSessionInit:(BOOL )IsInitator
{
    _isInitiator = IsInitator;
    _isInitDone = NO;
    // Request TURN.
    __weak ARDAppClient *weakSelf = self;
    [_turnClient requestServersWithCompletionHandler:^(NSArray *turnServers,
                                                       NSError *error) {
        if (error) {
            NSLog(@"Error retrieving TURN servers: %@", error);
        }
        ARDAppClient *strongSelf = weakSelf;
        [strongSelf.iceServers addObjectsFromArray:turnServers];
        strongSelf.isTurnComplete = YES;
        
        
        [strongSelf startSignalingIfReady];
    }];
    
    ARDAppClient *strongSelf = weakSelf;
    [strongSelf startSignalingIfReady];
}
- (void)connectToRoomWithId:(NSString *)roomId
                    options:(NSDictionary *)options {
  NSParameterAssert(roomId.length);
  NSParameterAssert(_state == kARDAppClientStateDisconnected);
  self.state = kARDAppClientStateConnecting;

  // Request TURN.
  __weak ARDAppClient *weakSelf = self;
  [_turnClient requestServersWithCompletionHandler:^(NSArray *turnServers,
                                                     NSError *error) {
    if (error) {
      NSLog(@"Error retrieving TURN servers: %@", error);
    }
    ARDAppClient *strongSelf = weakSelf;
    [strongSelf.iceServers addObjectsFromArray:turnServers];
    strongSelf.isTurnComplete = YES;
    [strongSelf startSignalingIfReady];
  }];

  // Join room on room server.
  [_roomServerClient joinRoomWithRoomId:roomId
      completionHandler:^(ARDJoinResponse *response, NSError *error) {
    ARDAppClient *strongSelf = weakSelf;
    if (error) {
      [strongSelf.delegate appClient:strongSelf didError:error];
      return;
    }
    NSError *joinError =
        [[strongSelf class] errorForJoinResultType:response.result];
    if (joinError) {
      NSLog(@"Failed to join room:%@ on room server.", roomId);
      [strongSelf disconnect];
      [strongSelf.delegate appClient:strongSelf didError:joinError];
      return;
    }
    NSLog(@"Joined room:%@ on room server.", roomId);
    strongSelf.roomId = response.roomId;
    strongSelf.clientId = response.clientId;
    strongSelf.isInitiator = response.isInitiator;
    for (ARDSignalingMessage *message in response.messages) {
      if (message.type == kARDSignalingMessageTypeOffer ||
          message.type == kARDSignalingMessageTypeAnswer) {
        strongSelf.hasReceivedSdp = YES;
        NSLog(@"Andy1"); 
        [strongSelf.messageQueue insertObject:message atIndex:0];
      } else {
        NSLog(@"Andy2"); 
        [strongSelf.messageQueue addObject:message];
      }
    }
    strongSelf.webSocketURL = response.webSocketURL;
    strongSelf.webSocketRestURL = response.webSocketRestURL;
    NSLog(@"Andy3 %@ %@",strongSelf.webSocketURL,strongSelf.webSocketRestURL); 
    [strongSelf registerWithColliderIfReady];
    [strongSelf startSignalingIfReady];
  }];
}

- (void)disconnect {
  
    if (_state == kARDAppClientStateDisconnected) {
    return;
  }
  
    if (self.hasJoinedRoomServerRoom) {
    [_roomServerClient leaveRoomWithRoomId:_roomId
                                  clientId:_clientId
                         completionHandler:nil];
  }
  if (_channel) {
    if (_channel.state == kARDSignalingChannelStateRegistered) {
      // Tell the other client we're hanging up.
      ARDByeMessage *byeMessage = [[ARDByeMessage alloc] init];
      [_channel sendMessage:byeMessage];
    }
    // Disconnect from collider.
    _channel = nil;
  }
  _clientId = nil;
  _roomId = nil;
  _isInitiator = NO;
  _hasReceivedSdp = NO;
  _messageQueue = [NSMutableArray array];
  _peerConnection = nil;
  _ice_message = nil;
  _sdp_message = nil;
  self.state = kARDAppClientStateDisconnected;
    
#ifdef _IOS_XMPP_JINGLE
    [xmppjingle_signaling_delegate SendXMPPTerminateSignaling];
#endif
}

#pragma mark - ARDSignalingChannelDelegate

- (void)channel:(id<ARDSignalingChannel>)channel
    didReceiveMessage:(ARDSignalingMessage *)message {
  switch (message.type) {
    case kARDSignalingMessageTypeOffer:
    case kARDSignalingMessageTypeAnswer:
      // Offers and answers must be processed before any other message, so we
      // place them at the front of the queue.
      _hasReceivedSdp = YES;
      [_messageQueue insertObject:message atIndex:0];
      break;
    case kARDSignalingMessageTypeCandidate:
      [_messageQueue addObject:message];
      break;
    case kARDSignalingMessageTypeBye:
      // Disconnects can be processed immediately.
      [self processSignalingMessage:message];
      return;
  }
  [self drainMessageQueueIfReady];
}

- (void)channel:(id<ARDSignalingChannel>)channel
    didChangeState:(ARDSignalingChannelState)state {
  switch (state) {
    case kARDSignalingChannelStateOpen:
      break;
    case kARDSignalingChannelStateRegistered:
      break;
    case kARDSignalingChannelStateClosed:
    case kARDSignalingChannelStateError:
      // TODO(tkchin): reconnection scenarios. Right now we just disconnect
      // completely if the websocket connection fails.
      [self disconnect];
      break;
  }
}

#pragma mark - RTCPeerConnectionDelegate
// Callbacks for this delegate occur on non-main thread and need to be
// dispatched back to main queue as needed.

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    signalingStateChanged:(RTCSignalingState)stateChanged {
  NSLog(@"Signaling state changed: %d", stateChanged);
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
           addedStream:(RTCMediaStream *)stream {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSLog(@"Received %lu video tracks and %lu audio tracks",
        (unsigned long)stream.videoTracks.count,
        (unsigned long)stream.audioTracks.count);
    if (stream.videoTracks.count) {
      RTCVideoTrack *videoTrack = stream.videoTracks[0];
      [_delegate appClient:self didReceiveRemoteVideoTrack:videoTrack];
    }
  });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
        removedStream:(RTCMediaStream *)stream {
  NSLog(@"Stream was removed.");
}

- (void)peerConnectionOnRenegotiationNeeded:
    (RTCPeerConnection *)peerConnection {
  NSLog(@"WARNING: Renegotiation needed but unimplemented.");
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    iceConnectionChanged:(RTCICEConnectionState)newState {
  NSLog(@"ICE state changed: %d", newState);
  dispatch_async(dispatch_get_main_queue(), ^{
    [_delegate appClient:self didChangeConnectionState:newState];
  });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    iceGatheringChanged:(RTCICEGatheringState)newState {
  NSLog(@"ICE gathering state changed: %d", newState);
    
    if(RTCICEGatheringComplete == newState)
    {
        #ifdef _IOS_XMPP_JINGLE
        [xmppjingle_signaling_delegate GatheringLocaICECandidateCompleted];
        #endif
    }
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
       gotICECandidate:(RTCICECandidate *)candidate {
  dispatch_async(dispatch_get_main_queue(), ^{
    
#ifdef _IOS_XMPP_JINGLE
      _ice_message = [[ARDICECandidateMessage alloc] initWithCandidate:candidate];
      NSDictionary *value = [NSDictionary dictionaryWithJSONString:[_ice_message description]];
      [xmppjingle_signaling_delegate GatheringLocaICECandidate:value[@"id"] candidate:value[@"candidate"] label:value[@"label"]];
      
#else
    ARDICECandidateMessage *message =
    [[ARDICECandidateMessage alloc] initWithCandidate:candidate];
      
    [self sendSignalingMessage:message];
#endif
  });
}

- (void)peerConnection:(RTCPeerConnection*)peerConnection
    didOpenDataChannel:(RTCDataChannel*)dataChannel {
}

#pragma mark - RTCSessionDescriptionDelegate
// Callbacks for this delegate occur on non-main thread and need to be
// dispatched back to main queue as needed.

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    didCreateSessionDescription:(RTCSessionDescription *)sdp
                          error:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (error) {
      NSLog(@"Failed to create session description. Error: %@", error);
      [self disconnect];
      NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: @"Failed to create session description.",
      };
      NSError *sdpError =
          [[NSError alloc] initWithDomain:kARDAppClientErrorDomain
                                     code:kARDAppClientErrorCreateSDP
                                 userInfo:userInfo];
      [_delegate appClient:self didError:sdpError];
      return;
    }
    // Prefer H264 if available.
    RTCSessionDescription *sdpPreferringH264 =
        [ARDSDPUtils descriptionForDescription:sdp
                           preferredVideoCodec:@"H264"];
    [_peerConnection setLocalDescriptionWithDelegate:self
                                  sessionDescription:sdpPreferringH264];
#ifdef _IOS_XMPP_JINGLE
      _sdp_message = [[ARDSessionDescriptionMessage alloc] initWithDescription:sdpPreferringH264];
      
      NSDictionary *value = [NSDictionary dictionaryWithJSONString:[_sdp_message description]];
      [xmppjingle_signaling_delegate SaveLocalSDP:value[@"sdp"]];
      NSLog(@"Andy peerConnection didCreateSessionDescription");
#else
      ARDSessionDescriptionMessage *message = [[ARDSessionDescriptionMessage alloc] initWithDescription:sdpPreferringH264];
      [self sendSignalingMessage:message];
      NSLog(@"Andy peerConnection didCreateSessionDescription %@",message);
#endif
      
  });
}

- (void)peerConnection:(RTCPeerConnection *)peerConnection
    didSetSessionDescriptionWithError:(NSError *)error {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (error) {
      NSLog(@"Failed to set session description. Error: %@", error);
      [self disconnect];
      NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: @"Failed to set session description.",
      };
      NSError *sdpError =
          [[NSError alloc] initWithDomain:kARDAppClientErrorDomain
                                     code:kARDAppClientErrorSetSDP
                                 userInfo:userInfo];
      [_delegate appClient:self didError:sdpError];
      return;
    }
    // If we're answering and we've just set the remote offer we need to create
    // an answer and set the local description.
    if (!_isInitiator && !_peerConnection.localDescription) {
      RTCMediaConstraints *constraints = [self defaultAnswerConstraints];
      [_peerConnection createAnswerWithDelegate:self
                                    constraints:constraints];
    }
  });
}

#pragma mark - Private

- (BOOL)hasJoinedRoomServerRoom {
  return _clientId.length;
}

// Begins the peer connection connection process if we have both joined a room
// on the room server and tried to obtain a TURN server. Otherwise does nothing.
// A peer connection object will be created with a stream that contains local
// audio and video capture. If this client is the caller, an offer is created as
// well, otherwise the client will wait for an offer to arrive.
- (void)startSignalingIfReady {
#ifdef _IOS_XMPP_JINGLE
    if (!_isTurnComplete) {
        return;
    }
#else
  if (!_isTurnComplete || !self.hasJoinedRoomServerRoom) {
    return;
  }
#endif
    
  self.state = kARDAppClientStateConnected;

  // Create peer connection.
  RTCMediaConstraints *constraints = [self defaultPeerConnectionConstraints];
  RTCConfiguration *config = [[RTCConfiguration alloc] init];
  config.iceServers = _iceServers;
  _peerConnection = [_factory peerConnectionWithConfiguration:config
                                                  constraints:constraints
                                                     delegate:self];
  // Create AV media stream and add it to the peer connection.
  RTCMediaStream *localStream = [self createLocalMediaStream];
  [_peerConnection addStream:localStream];
  if (_isInitiator) {
    // Send offer.
    NSLog(@"Andy Create an offer");
    [_peerConnection createOfferWithDelegate:self
                                 constraints:[self defaultOfferConstraints]];
  } else {
    // Check if we've received an offer.
    NSLog(@"Andy Check incomming Offer");
      
    //RTCMediaConstraints *constraints = [self defaultAnswerConstraints];
    //[_peerConnection createAnswerWithDelegate:self constraints:constraints];
    //Failed to create session description. Error: Error Domain=RTCSDPError Code=-1 "The operation couldn’t be completed. (RTCSDPError error -1.)" UserInfo=0x15e78d70 {error=CreateAnswer can't be called before SetRemoteDescription.}
          
    [self drainMessageQueueIfReady];
  }
    
    if(buffer_sdp_flag == 0x55)
    {
        NSLog(@"--------------------------------------------------------handle the peer side buffer sdp and candinate");
        for (ARDSignalingMessage *message in _messageBuffer) {
            [self processSignalingMessage:message];
            
        }
        [_messageBuffer removeAllObjects];
        buffer_sdp_flag = 0;
    }
  _isInitDone = YES;
    
    
  
}

// Processes the messages that we've received from the room server and the
// signaling channel. The offer or answer message must be processed before other
// signaling messages, however they can arrive out of order. Hence, this method
// only processes pending messages if there is a peer connection object and
// if we have received either an offer or answer.
- (void)drainMessageQueueIfReady {
  if (!_peerConnection || !_hasReceivedSdp) {
    return;
  }
  for (ARDSignalingMessage *message in _messageQueue) {
    [self processSignalingMessage:message];
  }
  [_messageQueue removeAllObjects];
}

// Processes the given signaling message based on its type.
- (void)processSignalingMessage:(ARDSignalingMessage *)message {
  NSParameterAssert(_peerConnection ||
      message.type == kARDSignalingMessageTypeBye);
  switch (message.type) {
    case kARDSignalingMessageTypeOffer:
    case kARDSignalingMessageTypeAnswer: {
      ARDSessionDescriptionMessage *sdpMessage =
          (ARDSessionDescriptionMessage *)message;
      RTCSessionDescription *description = sdpMessage.sessionDescription;
      // Prefer H264 if available.
      RTCSessionDescription *sdpPreferringH264 =
          [ARDSDPUtils descriptionForDescription:description
                             preferredVideoCodec:@"H264"];
        
      NSLog(@"%@",sdpPreferringH264);
        
      [_peerConnection setRemoteDescriptionWithDelegate:self
                                     sessionDescription:sdpPreferringH264];
      break;
    }
    case kARDSignalingMessageTypeCandidate: {
      ARDICECandidateMessage *candidateMessage =
          (ARDICECandidateMessage *)message;
      [_peerConnection addICECandidate:candidateMessage.candidate];
      break;
    }
    case kARDSignalingMessageTypeBye:
      // Other client disconnected.
      // TODO(tkchin): support waiting in room for next client. For now just
      // disconnect.
      [self disconnect];
      break;
  }
}

// Sends a signaling message to the other client. The caller will send messages
// through the room server, whereas the callee will send messages over the
// signaling channel.
- (void)sendSignalingMessage:(ARDSignalingMessage *)message {
  if (_isInitiator) {
    __weak ARDAppClient *weakSelf = self;
    
    NSLog(@"Andy sendSignalingMessage _roomServerClient");

    [_roomServerClient sendMessage:message
                         forRoomId:_roomId
                          clientId:_clientId
                 completionHandler:^(ARDMessageResponse *response,
                                     NSError *error) {
      ARDAppClient *strongSelf = weakSelf;
      if (error) {
        [strongSelf.delegate appClient:strongSelf didError:error];
        return;
      }
      NSError *messageError =
          [[strongSelf class] errorForMessageResultType:response.result];
      if (messageError) {
        [strongSelf.delegate appClient:strongSelf didError:messageError];
        return;
      }
    }];
  } else {
    NSLog(@"Andy sendSignalingMessage _channel");
    [_channel sendMessage:message];
  }
}

- (RTCMediaStream *)createLocalMediaStream {
  RTCMediaStream* localStream = [_factory mediaStreamWithLabel:@"ARDAMS"];
  RTCVideoTrack* localVideoTrack = [self createLocalVideoTrack];
  if (localVideoTrack) {
    [localStream addVideoTrack:localVideoTrack];
    [_delegate appClient:self didReceiveLocalVideoTrack:localVideoTrack];
  }
  [localStream addAudioTrack:[_factory audioTrackWithID:@"ARDAMSa0"]];
  return localStream;
}

- (RTCVideoTrack *)createLocalVideoTrack {
  RTCVideoTrack* localVideoTrack = nil;
  // The iOS simulator doesn't provide any sort of camera capture
  // support or emulation (http://goo.gl/rHAnC1) so don't bother
  // trying to open a local stream.
  // TODO(tkchin): local video capture for OSX. See
  // https://code.google.com/p/webrtc/issues/detail?id=3417.
#if !TARGET_IPHONE_SIMULATOR && TARGET_OS_IPHONE
  RTCMediaConstraints *mediaConstraints = [self defaultMediaStreamConstraints];
  RTCAVFoundationVideoSource *source =
      [[RTCAVFoundationVideoSource alloc] initWithFactory:_factory
                                              constraints:mediaConstraints];
  localVideoTrack =
      [[RTCVideoTrack alloc] initWithFactory:_factory
                                      source:source
                                     trackId:@"ARDAMSv0"];
#endif
  return localVideoTrack;
}

#pragma mark - Collider methods

- (void)registerWithColliderIfReady {
  if (!self.hasJoinedRoomServerRoom) {
    return;
  }
  // Open WebSocket connection.
  if (!_channel) {
    _channel =
        [[ARDWebSocketChannel alloc] initWithURL:_websocketURL
                                         restURL:_websocketRestURL
                                        delegate:self];
  }
  [_channel registerForRoomId:_roomId clientId:_clientId];
}

#pragma mark - Defaults

- (RTCMediaConstraints *)defaultMediaStreamConstraints {
  RTCMediaConstraints* constraints =
      [[RTCMediaConstraints alloc]
          initWithMandatoryConstraints:nil
                   optionalConstraints:nil];
  return constraints;
}

- (RTCMediaConstraints *)defaultAnswerConstraints {
  return [self defaultOfferConstraints];
}

- (RTCMediaConstraints *)defaultOfferConstraints {
  NSArray *mandatoryConstraints = @[
      [[RTCPair alloc] initWithKey:@"OfferToReceiveAudio" value:@"true"],
      [[RTCPair alloc] initWithKey:@"OfferToReceiveVideo" value:@"true"]
            
  ];
  RTCMediaConstraints* constraints =
      [[RTCMediaConstraints alloc]
          initWithMandatoryConstraints:mandatoryConstraints
                   optionalConstraints:nil];
  return constraints;
}

- (RTCMediaConstraints *)defaultPeerConnectionConstraints {
  if (_defaultPeerConnectionConstraints) {
    return _defaultPeerConnectionConstraints;
  }
  NSArray *optionalConstraints = @[
      [[RTCPair alloc] initWithKey:@"DtlsSrtpKeyAgreement" value:@"false"]
  ];
  RTCMediaConstraints* constraints =
      [[RTCMediaConstraints alloc]
          initWithMandatoryConstraints:nil
                   optionalConstraints:optionalConstraints];
  return constraints;
}

- (RTCICEServer *)defaultSTUNServer {
  NSURL *defaultSTUNServerURL = [NSURL URLWithString:kARDDefaultSTUNServerUrl];
  return [[RTCICEServer alloc] initWithURI:defaultSTUNServerURL
                                  username:@""
                                  password:@""];
}

#pragma mark - Errors

+ (NSError *)errorForJoinResultType:(ARDJoinResultType)resultType {
  NSError *error = nil;
  switch (resultType) {
    case kARDJoinResultTypeSuccess:
      break;
    case kARDJoinResultTypeUnknown: {
      error = [[NSError alloc] initWithDomain:kARDAppClientErrorDomain
                                         code:kARDAppClientErrorUnknown
                                     userInfo:@{
        NSLocalizedDescriptionKey: @"Unknown error.",
      }];
      break;
    }
    case kARDJoinResultTypeFull: {
      error = [[NSError alloc] initWithDomain:kARDAppClientErrorDomain
                                         code:kARDAppClientErrorRoomFull
                                     userInfo:@{
        NSLocalizedDescriptionKey: @"Room is full.",
      }];
      break;
    }
  }
  return error;
}

+ (NSError *)errorForMessageResultType:(ARDMessageResultType)resultType {
  NSError *error = nil;
  switch (resultType) {
    case kARDMessageResultTypeSuccess:
      break;
    case kARDMessageResultTypeUnknown:
      error = [[NSError alloc] initWithDomain:kARDAppClientErrorDomain
                                         code:kARDAppClientErrorUnknown
                                     userInfo:@{
        NSLocalizedDescriptionKey: @"Unknown error.",
      }];
      break;
    case kARDMessageResultTypeInvalidClient:
      error = [[NSError alloc] initWithDomain:kARDAppClientErrorDomain
                                         code:kARDAppClientErrorInvalidClient
                                     userInfo:@{
        NSLocalizedDescriptionKey: @"Invalid client.",
      }];
      break;
    case kARDMessageResultTypeInvalidRoom:
      error = [[NSError alloc] initWithDomain:kARDAppClientErrorDomain
                                         code:kARDAppClientErrorInvalidRoom
                                     userInfo:@{
        NSLocalizedDescriptionKey: @"Invalid room.",
      }];
      break;
  }
  return error;
}

#pragma mark XMPPJingleWebRTCDelegate

- (BOOL)SetRemoteSDP:(NSString *)sdp
{
    NSString *_body1;
    if(_isInitiator)
    {
        _body1 = [NSString stringWithFormat:@"{\"type\":\"answer\",\"sdp\":\"%@\"}", sdp];
    }
    else
    {
        _body1 = [NSString stringWithFormat:@"{\"type\":\"offer\",\"sdp\":\"%@\"}", sdp];
    }
    
    NSString *_body = [_body1 stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\\r\\n"];
    
    
    NSLog(@"SetRemoteSDP=======================================%d %@",_isInitDone,_body);
    if(_isInitDone == YES)
    {
        ARDSignalingMessage *signalingMessage = [ARDSignalingMessage messageFromJSONString:_body];
        [self channel:nil didReceiveMessage:signalingMessage];
    }
    else
    {
        buffer_sdp_flag = 0x55;
        
        ARDSignalingMessage *signalingMessage = [ARDSignalingMessage messageFromJSONString:_body];
        _messageBuffer = [NSMutableArray array];
        [_messageBuffer insertObject:signalingMessage atIndex:0];
    }
    
    return YES;
}

- (BOOL)SetRemoteCandinate:(NSString *)dev id:(NSString *)i candidate:(NSString *)c
{
    NSString *_body = [NSString stringWithFormat:@"{\n\"type\" : \"candidate\",\n\"id\" : \"%@\",\n\"candidate\" : \"%@\",\n\"label\" : \"%@\"\n}", dev,c,i];
    
    NSLog(@"SetRemoteCandinate =======================================%d %@",_isInitDone,_body);
    
    if(buffer_sdp_flag == 0x55)
    {
        ARDSignalingMessage *signalingMessage = [ARDSignalingMessage messageFromJSONString:_body];
        [_messageBuffer addObject:signalingMessage];
        
    }
    else
    {
        ARDSignalingMessage *signalingMessage = [ARDSignalingMessage messageFromJSONString:_body];
        [self channel:nil didReceiveMessage:signalingMessage];
    }
    return YES;
}
@end
