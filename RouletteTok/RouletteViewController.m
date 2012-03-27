//
//  RouletteViewController.m
//  RouletteTok
//
//  Created by mumm on 2/16/12.
//  Copyright (c) 2012 TokBox. All rights reserved.
//

#import "RouletteViewController.h"

@implementation RouletteViewController {
    SRWebSocket *_webSocket;                                // Socket that connects to socket.io
    
    OTSession *_mySession;                                  // Session that belongs to this user
    OTPublisher *_publisher;                                // Publisher that belongs to this user
    
    OTSubscriber *_subscriber;                              // Subscriber of the user chatting to
    OTSession *_partnerSession;                             // Session that the user chatting to
}

@synthesize statusField = _statusField;

static int topOffset = 38;
static double widgetHeight = 216;                           // Height of stream
static double widgetWidth = 288;                            // Width of stream
static NSString* const apiKey = @"413302";                 // OpenTok API key
static NSString* const serverUrl = @"roulettetok.com";      // Location of socket.io server

/**
 * Initializes an HTTP call to handshake with socket.io
 */
- (void)initHandshake
{
    [RKClient clientWithBaseURL:[NSString stringWithFormat:@"http://%@", serverUrl]];
    NSTimeInterval time = [[NSDate date] timeIntervalSince1970];
    time = time * 1000;
    [[RKClient sharedClient] get:[NSString stringWithFormat:@"/socket.io/1?t=%.0f", time] delegate:self];
}

/**
 * Initializes connection to socket.io
 *
 * @param token Required token to connect to socket.io
 */
- (void)socketConnect:(NSString*)token
{
    _webSocket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"ws://%@/socket.io/1/websocket/%@", serverUrl, token]]]];
    _webSocket.delegate = self;
    
    [_webSocket open];
}

/**
 * Sends a message to the socket to request a new user to talk to
 */
- (void)socketSendNextEvent {
    NSString *message = [NSString stringWithFormat:@"5:::{\"name\":\"next\",\"args\":[{\"sessionId\":\"%@\"}]}", _mySession.sessionId];
    
    [_webSocket send:message];    
}

/**
 * Sends a message to the socket to force both partners to disconnect
 */
- (void)socketSendDisconnectPartnersEvent {
    NSString *message = @"5:::{\"name\":\"disconnectPartners\"}";
    
    [_webSocket send:message];    
}

/**
 * Sent when the HTTP request comes back.
 *
 * Parses handshake HTTP response and initializes socket.io connection
 *
 * @param request
 * @param response
 */
- (void)request:(RKRequest*)request didLoadResponse:(RKResponse*)response {
    NSString* handshakeToken = [[[response bodyAsString] componentsSeparatedByString:@":"] objectAtIndex:0];
    [self socketConnect:handshakeToken];
}

/**
 * Sent when a session connects.
 *
 * @param session
 */
- (void)sessionDidConnect:(OTSession*)session
{
    // Starts publishing if the connected session is the users own session
    if ([session.sessionId isEqualToString:_mySession.sessionId]) {
        _publisher = [[OTPublisher alloc] initWithDelegate:self];        
        [_publisher setName:[[UIDevice currentDevice] name]];
        [_mySession publish:_publisher];
        [self.view addSubview:_publisher.view];
        [_publisher.view setFrame:CGRectMake(0, topOffset+widgetHeight, widgetWidth, widgetHeight)];
    }
}

/**
 * Sent when a session fails to connect.
 *
 * @param session
 * @param error
 */
- (void)session:(OTSession*)session didFailWithError:(NSError*)error {
    self.statusField.text = @"Error connecting to session.";
}

/**
 * Sent when a session disconnects.
 *
 * @param session
 */
- (void)sessionDidDisconnect:(OTSession*)session
{
    [self socketSendNextEvent];
}

/**
 * Sent when a session receives a new stream.
 *
 * Tries to subscribe to any new stream that does not belong to this user.
 *
 * @param session
 * @param stream
 */
- (void)session:(OTSession*)session didReceiveStream:(OTStream*)stream
{
    if (stream.connection.connectionId != _mySession.connection.connectionId) {
        _subscriber = [[OTSubscriber alloc] initWithStream:stream delegate:self];
    }
}

/**
 * Sent when a session drops a stream.
 *
 * @param session
 * @param stream
 */
- (void)session:(OTSession*)session didDropStream:(OTStream*)stream
{
    NSLog(@"Stream dropped from session");
}

/**
 * Sent when a stream connects to a subscriber.
 *
 * Adds the subscribet to the view.
 *
 * @param subscriber
 */
- (void)subscriberDidConnectToStream:(OTSubscriber*)subscriber
{
    [self.view addSubview:subscriber.view];
    [subscriber.view setFrame:CGRectMake(0, topOffset, widgetWidth, widgetHeight)];
}

/**
 * Sent when a stream fails to subscribe.
 *
 * @param subscriber
 * @param error
 */
- (void)subscriber:(OTSubscriber*)subscriber didFailWithError:(NSError*)error;
{
    NSLog(@"Error connecting to stream.");
}

/**
 * Sent when the next button is pressed/
 */
- (IBAction)nextButton
{
    if (_partnerSession.sessionConnectionStatus == OTSessionConnectionStatusConnected) {
        [self socketSendDisconnectPartnersEvent];
    } else {
        [self socketSendNextEvent];
    }
}

/**
 * Sent when the publisher starts streaming.
 *
 * Asks to talk to a new user.
 *
 * @param publisher
 */
- (void)publisherDidStartStreaming:(OTPublisher*)publisher
{
    [self socketSendNextEvent];
}

/**
 * Sent when there is an error when publishing.
 *
 * @param error
 */
- (void)publisher:(OTPublisher*)publisher didFailWithError:(NSError*) error
{
    NSLog(@"Error publishing stream.");
}

/**
 * Called when an "initial" socket event comes in.
 *
 * Connects to this user's session for the first time.
 *
 * @param args JSON object containing the sessionId and token for the sessoin belonging to this user.
 */
- (void)didReceiveInitialEvent:(NSDictionary *)args {
    _mySession = [[OTSession alloc] initWithSessionId:[args objectForKey:@"sessionId"] delegate:self];    
    [_mySession connectWithApiKey:apiKey token:[args objectForKey:@"token"]];
}

/**
 * Called when a "subscribe" socket event comes in.
 *
 * Connects to the session of the user to subscribe to.
 *
 * @param args JSON object containing sessionId and token for session the other user is in.
 */
- (void)didReceiveSubscribeEvent:(NSDictionary *)args {
    _partnerSession = [[OTSession alloc] initWithSessionId:[args objectForKey:@"sessionId"] delegate:self];    
    [_partnerSession connectWithApiKey:apiKey token:[args objectForKey:@"token"]];
    
    self.statusField.text = @"Have fun!";
}

/**
 * Called when an "empty" socket event comes in.
 */
- (void)didReceiveEmptyEvent {
    self.statusField.text = @"Nobody to talk to. Waiting...";
}

/**
 * Called when a "disconnectPartner" socket event comes in.
 */
- (void)didReceiveDisconnectPartnerEvent {
    [_partnerSession disconnect];
}

/**
 * Sent when a new socket message comes in.
 *
 * Parses the message as JSON then calls a method depending on the event parameter.
 *
 * @param websocket
 * @param message
 */
- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(NSString *)message {
    NSError *jsonError;
    NSData *data = [[[message componentsSeparatedByString:@":::"] lastObject]dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];

    NSString *event = [json objectForKey:@"name"];
    NSDictionary *args = [[json objectForKey:@"args"] objectAtIndex:0];
    
    if ([event isEqualToString:@"initial"]) {
        [self didReceiveInitialEvent:args];
    } else if ([event isEqualToString:@"subscribe"]) {
        [self didReceiveSubscribeEvent:args];
    } else if ([event isEqualToString:@"empty"]) {
        [self didReceiveEmptyEvent];
    } else if ([event isEqualToString:@"disconnectPartner"]) {
        [self didReceiveDisconnectPartnerEvent];
    }
}

/**
 * Sent when the view loads.
 *
 * Initializes socket.io HTTP handshake.
 */
- (void)viewDidLoad
{
    [super viewDidLoad];    
    [self initHandshake];
}

/**
 * Sent when the view unloads.
 */
- (void)viewDidUnload {
    [self setStatusField:nil];
    [super viewDidUnload];
}

@end
