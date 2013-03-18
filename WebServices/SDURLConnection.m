//
//  SDURLConnection
//  ServiceTest
//
//  Created by Brandon Sneed on 11/3/11.
//  Copyright (c) 2011 SetDirection. All rights reserved.
//

#import "SDURLConnection.h"
#import "NSString+SDExtensions.h"
#import "NSCachedURLResponse+LeakFix.h"

#import <libkern/OSAtomic.h>

#pragma mark - SDURLResponseCompletionDelegate

#ifndef SDURLCONNECTION_MAX_CONCURRENT_CONNECTIONS
#define SDURLCONNECTION_MAX_CONCURRENT_CONNECTIONS 20
#endif

@interface SDURLConnectionAsyncDelegate : NSObject
{
@public
    SDURLConnectionResponseBlock responseHandler;
@private
	NSMutableData *responseData;
	NSHTTPURLResponse *httpResponse;
    BOOL shouldCache;
    BOOL isRunning;
}

@property (atomic, assign) BOOL isRunning;

- (id)initWithResponseHandler:(SDURLConnectionResponseBlock)newHandler shouldCache:(BOOL)cache;
- (void)forceError:(SDURLConnection *)connection;

@end

@implementation SDURLConnectionAsyncDelegate

@synthesize isRunning;

- (id)initWithResponseHandler:(SDURLConnectionResponseBlock)newHandler shouldCache:(BOOL)cache
{
    if (self = [super init])
	{
        responseHandler = [newHandler copy];
        shouldCache = cache;
		responseData = [NSMutableData dataWithCapacity:0];
        self.isRunning = YES;
    }
	
    return self;
}

- (void)dealloc
{
    responseHandler = nil;
    responseData = nil;
}

- (void)forceError:(SDURLConnection *)connection
{
    if (responseHandler)
        responseHandler(connection, nil, nil, [NSError errorWithDomain:@"SDURLConnectionDomain" code:NSURLErrorCancelled userInfo:nil]);
}

#pragma mark NSURLConnection delegate

- (void)connection:(SDURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	httpResponse = (NSHTTPURLResponse *)response;
	[responseData setLength:0];
}

- (void)connection:(SDURLConnection *)connection didFailWithError:(NSError *)error
{
    if (isRunning)
        responseHandler(connection, nil, responseData, error);
    responseHandler = nil;
    self.isRunning = NO;
}

- (void)connection:(SDURLConnection *)connection didReceiveData:(NSData *)data
{
    if (isRunning)
        [responseData appendData:data];
}

- (void)connectionDidFinishLoading:(SDURLConnection *)connection
{
    if (isRunning)
        responseHandler(connection, httpResponse, responseData, nil);
    responseHandler = nil;
    self.isRunning = NO;
}

- (NSCachedURLResponse *)connection:(SDURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    NSCachedURLResponse *realCache = [[NSCachedURLResponse alloc] initWithResponse:cachedResponse.response data:cachedResponse.responseData userInfo:nil storagePolicy:NSURLCacheStorageAllowed];
    return shouldCache ? realCache : nil;
}

@end

#pragma mark - SDURLConnection

@interface SDURLConnection()

@property (nonatomic, strong) SDURLConnectionAsyncDelegate *asyncDelegate;

@end

@implementation SDURLConnection

static NSOperationQueue *networkOperationQueue = nil;

+ (void)initialize
{
    networkOperationQueue = [[NSOperationQueue alloc] init];
    networkOperationQueue.maxConcurrentOperationCount = SDURLCONNECTION_MAX_CONCURRENT_CONNECTIONS;
    networkOperationQueue.name = @"com.setdirection.sdurlconnectionqueue";
}

+ (NSInteger)maxConcurrentAsyncConnections
{
    return networkOperationQueue.maxConcurrentOperationCount;
}

+ (void)setMaxConcurrentAsyncConnections:(NSInteger)maxCount
{
    networkOperationQueue.maxConcurrentOperationCount = maxCount;
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately
{
    self = [super initWithRequest:request delegate:delegate startImmediately:startImmediately];
    if ([delegate isKindOfClass:[SDURLConnectionAsyncDelegate class]])
        self.asyncDelegate = delegate;
    return self;
}

- (void)cancel
{
    @synchronized(self)
    {
        if (self.asyncDelegate.isRunning)
        {
            self.asyncDelegate.isRunning = NO;
            [super cancel];
            [self.asyncDelegate forceError:self];
        }
    }
}

+ (SDURLConnection *)sendAsynchronousRequest:(NSURLRequest *)request shouldCache:(BOOL)cache withResponseHandler:(SDURLConnectionResponseBlock)handler
{
    if (!handler)
        @throw @"sendAsynchronousRequest must be given a handler!";
    
    SDURLConnectionAsyncDelegate *delegate = [[SDURLConnectionAsyncDelegate alloc] initWithResponseHandler:handler shouldCache:cache];
    SDURLConnection *connection = [[SDURLConnection alloc] initWithRequest:request delegate:delegate startImmediately:NO];
    
    if (!connection)
        SDLog(@"Unable to create a connection!");

    [connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    // the sole purpose of this is to enforce a maximum active connection count.
    // eventually, these max connection numbers will change based on reachability data.
    [networkOperationQueue addOperationWithBlock:^{
        [connection performSelectorOnMainThread:@selector(start) withObject:nil waitUntilDone:YES];
        while (delegate.isRunning)
            sleep(1);
    }];
    
    return connection;
}

@end