// Copyright (c) 2026 Kevnnard
// This file is licensed under the SmartWindow Public Non-Commercial License v1.1.
//
// Read-only Now Playing session reader. Loaded into /usr/bin/perl by
// media-sessions.pl (mediaremoted answers Now Playing reads only for
// Apple-signed clients), it prints one JSON line whenever the list of
// MediaRemote sessions changes. It never sends a MediaRemote command.

#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <errno.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <signal.h>
#import <stdio.h>
#import <unistd.h>

#define MS_TICK_SECONDS 1
#define MS_TIMEOUT_MILLIS 2000

static NSString *const kMRPath = @"/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote";

typedef void (*MSGetClientsFn)(dispatch_queue_t queue, void (^completion)(CFArrayRef clients));

// objc_msgSend casts. Object results are declared as void * and bridged
// explicitly so ARC ownership matches each selector's convention.
typedef void *(*MSSendRaw)(id, SEL);
typedef void *(*MSInitPath)(void *, SEL, void *, void *, void *);
typedef void *(*MSInitRequest)(void *, SEL, void *);
typedef void (*MSRequest)(id, SEL, id, id);
typedef int (*MSSendInt)(id, SEL);

static pid_t gParentPID = 0;
static dispatch_queue_t gQueue;
static MSGetClientsFn gGetClients = NULL;

static void exitIfOrphaned(void) {
    pid_t parent = getppid();
    if (parent == 1 || parent != gParentPID) {
        _exit(0);
    }
    if (kill(gParentPID, 0) != 0 && errno == ESRCH) {
        _exit(0);
    }
}

static dispatch_time_t timeoutFromNow(void) {
    return dispatch_time(DISPATCH_TIME_NOW, (int64_t)MS_TIMEOUT_MILLIS * NSEC_PER_MSEC);
}

static id stringOrNil(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static id finiteNumberOrNil(id value) {
    if (![value isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    double number = [(NSNumber *)value doubleValue];
    return isfinite(number) ? value : nil;
}

static id jsonValue(id value) {
    return value ?: [NSNull null];
}

// Calls a zero-argument selector returning an object at +0; nil when the
// receiver does not implement it.
static id objectFrom(id receiver, NSString *selectorName) {
    if (receiver == nil) {
        return nil;
    }
    SEL selector = sel_registerName(selectorName.UTF8String);
    if (![receiver respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature *signature = [receiver methodSignatureForSelector:selector];
    if (signature == nil || signature.methodReturnType[0] != '@') {
        return nil;
    }
    return (__bridge id)((MSSendRaw)objc_msgSend)(receiver, selector);
}

static NSNumber *processIdentifierOf(id client) {
    SEL selector = sel_registerName("processIdentifier");
    if (client == nil || ![client respondsToSelector:selector]) {
        return nil;
    }
    NSMethodSignature *signature = [client methodSignatureForSelector:selector];
    if (signature == nil || signature.methodReturnType[0] != 'i') {
        return nil;
    }
    return @(((MSSendInt)objc_msgSend)(client, selector));
}

static NSArray *nowPlayingClients(void) {
    NSMutableArray *result = [NSMutableArray array];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    gGetClients(gQueue, ^(CFArrayRef clients) {
      if (clients != NULL && CFGetTypeID(clients) == CFArrayGetTypeID()) {
          [result addObjectsFromArray:(__bridge NSArray *)clients];
      }
      dispatch_semaphore_signal(done);
    });
    if (dispatch_semaphore_wait(done, timeoutFromNow()) != 0) {
        return @[];
    }
    __block NSArray *copy;
    dispatch_sync(gQueue, ^{
      copy = [result copy];
    });
    return copy;
}

static id requestForClient(id client) {
    Class pathClass = objc_getClass("MRPlayerPath");
    Class originClass = objc_getClass("MROrigin");
    Class requestClass = objc_getClass("MRNowPlayingRequest");
    SEL localOrigin = sel_registerName("localOrigin");
    SEL initPath = sel_registerName("initWithOrigin:client:player:");
    SEL initRequest = sel_registerName("initWithPlayerPath:");
    if (pathClass == Nil || originClass == Nil || requestClass == Nil ||
        ![originClass respondsToSelector:localOrigin] ||
        ![pathClass instancesRespondToSelector:initPath] ||
        ![requestClass instancesRespondToSelector:initRequest]) {
        return nil;
    }
    id origin = (__bridge id)((MSSendRaw)objc_msgSend)((id)originClass, localOrigin);
    if (origin == nil) {
        return nil;
    }
    SEL alloc = sel_registerName("alloc");
    // alloc returns +1, init consumes it and returns +1.
    void *rawPath = ((MSSendRaw)objc_msgSend)((id)pathClass, alloc);
    rawPath = ((MSInitPath)objc_msgSend)(rawPath, initPath, (__bridge void *)origin,
                                         (__bridge void *)client, NULL);
    id path = (__bridge_transfer id)rawPath;
    if (path == nil) {
        return nil;
    }
    void *rawRequest = ((MSSendRaw)objc_msgSend)((id)requestClass, alloc);
    rawRequest = ((MSInitRequest)objc_msgSend)(rawRequest, initRequest, (__bridge void *)path);
    return (__bridge_transfer id)rawRequest;
}

static NSString *currentBundleIdentifier(void) {
    Class requestClass = objc_getClass("MRNowPlayingRequest");
    SEL selector = sel_registerName("localNowPlayingPlayerPath");
    if (requestClass == Nil || ![requestClass respondsToSelector:selector]) {
        return nil;
    }
    id path = (__bridge id)((MSSendRaw)objc_msgSend)((id)requestClass, selector);
    id client = objectFrom(path, @"client");
    return stringOrNil(objectFrom(client, @"bundleIdentifier"));
}

// Reads info and playing state for every client concurrently, waiting at
// most MS_TIMEOUT_MILLIS for the answers. Returns one entry per client with
// optional "request", "info" (NSDictionary) and "playing" (NSNumber) values.
static NSArray<NSDictionary *> *readSessions(NSArray *clients) {
    SEL infoSelector = sel_registerName("requestNowPlayingInfoOnQueue:completion:");
    SEL playingSelector = sel_registerName("requestIsPlayingOnQueue:completion:");
    NSMutableArray<NSMutableDictionary *> *entries = [NSMutableArray array];
    NSMutableArray<dispatch_semaphore_t> *waits = [NSMutableArray array];

    for (id client in clients) {
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"client"] = client;
        [entries addObject:entry];
        id request = requestForClient(client);
        if (request == nil) {
            continue;
        }
        if ([request respondsToSelector:infoSelector]) {
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            [waits addObject:done];
            ((MSRequest)objc_msgSend)(request, infoSelector, gQueue, ^(id info, id error) {
              if ([info isKindOfClass:[NSDictionary class]]) {
                  entry[@"info"] = [info copy];
              }
              dispatch_semaphore_signal(done);
            });
        }
        entry[@"request"] = request;
        if ([request respondsToSelector:playingSelector]) {
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            [waits addObject:done];
            ((MSRequest)objc_msgSend)(request, playingSelector, gQueue, ^(BOOL playing, id error) {
              entry[@"playing"] = playing ? @YES : @NO;
              dispatch_semaphore_signal(done);
            });
        }
    }

    dispatch_time_t deadline = timeoutFromNow();
    for (dispatch_semaphore_t done in waits) {
        dispatch_semaphore_wait(done, deadline);
    }
    // Late completions mutate the entries on gQueue; snapshot them there.
    __block NSMutableArray<NSDictionary *> *snapshot = [NSMutableArray array];
    dispatch_sync(gQueue, ^{
      for (NSMutableDictionary *entry in entries) {
          [snapshot addObject:[entry copy]];
      }
    });
    return snapshot;
}

static NSString *sessionKey(id client) {
    return [NSString stringWithFormat:@"%@|%@", objectFrom(client, @"bundleIdentifier"),
                                      processIdentifierOf(client)];
}

// Identifies the artwork a session currently shows, so its bytes are only
// requested again when it changes.
static NSString *artworkToken(NSDictionary *info) {
    NSString *identifier = stringOrNil(info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"]);
    if (identifier.length > 0) {
        return identifier;
    }
    return [NSString stringWithFormat:@"%@|%@|%@", info[@"kMRMediaRemoteNowPlayingInfoTitle"],
                                      info[@"kMRMediaRemoteNowPlayingInfoArtist"],
                                      info[@"kMRMediaRemoteNowPlayingInfoAlbum"]];
}

// Returns the artwork bytes (NSData, or NSNull when there is none) for every
// session key. The info dictionary rarely carries ArtworkData, so missing
// bytes are requested per session with -requestNowPlayingItemArtworkOnQueue:
// and cached by artwork token. A timed-out request keeps the previous bytes
// and is retried next tick.
static NSDictionary<NSString *, id> *resolveArtwork(NSArray<NSDictionary *> *entries,
                                                    NSMutableDictionary<NSString *, NSDictionary *> *cache) {
    SEL artworkSelector = sel_registerName("requestNowPlayingItemArtworkOnQueue:completion:");
    NSMutableDictionary<NSString *, id> *result = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *nextCache = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *pending = [NSMutableDictionary dictionary];
    NSMutableArray<dispatch_semaphore_t> *waits = [NSMutableArray array];

    for (NSDictionary *entry in entries) {
        NSString *key = sessionKey(entry[@"client"]);
        NSDictionary *info = entry[@"info"];
        NSDictionary *cached = cache[key];
        if (info == nil) {
            result[key] = cached[@"data"] ?: [NSNull null];
            if (cached != nil) {
                nextCache[key] = cached;
            }
            continue;
        }
        NSString *token = artworkToken(info);
        id inlineData = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if ([inlineData isKindOfClass:[NSData class]] && [(NSData *)inlineData length] > 0) {
            nextCache[key] = @{@"token" : token, @"data" : inlineData};
            result[key] = inlineData;
            continue;
        }
        if ([cached[@"token"] isEqual:token]) {
            nextCache[key] = cached;
            result[key] = cached[@"data"];
            continue;
        }
        result[key] = cached[@"data"] ?: [NSNull null];
        if (cached != nil) {
            nextCache[key] = cached;
        }
        id request = entry[@"request"];
        if (![request respondsToSelector:artworkSelector]) {
            continue;
        }
        NSMutableDictionary *answer = [NSMutableDictionary dictionaryWithObject:token forKey:@"token"];
        pending[key] = answer;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        [waits addObject:done];
        ((MSRequest)objc_msgSend)(request, artworkSelector, gQueue, ^(id artwork, id error) {
          id data = objectFrom(artwork, @"imageData");
          answer[@"data"] = ([data isKindOfClass:[NSData class]] && [(NSData *)data length] > 0)
                                ? data
                                : [NSNull null];
          dispatch_semaphore_signal(done);
        });
    }

    dispatch_time_t deadline = timeoutFromNow();
    for (dispatch_semaphore_t done in waits) {
        dispatch_semaphore_wait(done, deadline);
    }
    dispatch_sync(gQueue, ^{
      [pending enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSMutableDictionary *answer, BOOL *stop) {
        if (answer[@"data"] != nil) {
            nextCache[key] = [answer copy];
            result[key] = answer[@"data"];
        }
      }];
    });
    [cache setDictionary:nextCache];
    return result;
}

static NSString *isoTimestamp(id value) {
    static NSISO8601DateFormatter *formatter;
    if (formatter == nil) {
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                                  NSISO8601DateFormatWithFractionalSeconds;
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    }
    return [value isKindOfClass:[NSDate class]] ? [formatter stringFromDate:value] : nil;
}

// Session fields without artwork; artwork is tracked separately so changes
// can be detected without re-encoding it every tick.
static NSMutableDictionary *sessionFields(NSDictionary *entry) {
    id client = entry[@"client"];
    NSDictionary *info = entry[@"info"];
    NSMutableDictionary *session = [NSMutableDictionary dictionary];
    session[@"bundleIdentifier"] = jsonValue(stringOrNil(objectFrom(client, @"bundleIdentifier")));
    session[@"displayName"] = jsonValue(stringOrNil(objectFrom(client, @"displayName")));
    session[@"processIdentifier"] = jsonValue(processIdentifierOf(client));
    session[@"parentApplicationBundleIdentifier"] =
        jsonValue(stringOrNil(objectFrom(client, @"parentApplicationBundleIdentifier")));
    session[@"title"] = jsonValue(stringOrNil(info[@"kMRMediaRemoteNowPlayingInfoTitle"]));
    session[@"artist"] = jsonValue(stringOrNil(info[@"kMRMediaRemoteNowPlayingInfoArtist"]));
    session[@"album"] = jsonValue(stringOrNil(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]));
    session[@"duration"] = jsonValue(finiteNumberOrNil(info[@"kMRMediaRemoteNowPlayingInfoDuration"]));
    session[@"elapsedTime"] = jsonValue(finiteNumberOrNil(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]));
    session[@"timestamp"] = jsonValue(isoTimestamp(info[@"kMRMediaRemoteNowPlayingInfoTimestamp"]));
    session[@"playbackRate"] = jsonValue(finiteNumberOrNil(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]));
    id playing = entry[@"playing"];
    session[@"playing"] = [playing isKindOfClass:[NSNumber class]] ? playing : [NSNull null];
    session[@"artworkMimeType"] = jsonValue(stringOrNil(info[@"kMRMediaRemoteNowPlayingInfoArtworkMIMEType"]));
    return session;
}

static void writeLine(NSData *json) {
    if (fwrite(json.bytes, 1, json.length, stdout) != json.length || fputc('\n', stdout) == EOF ||
        fflush(stdout) != 0) {
        // stdout is gone (EPIPE or closed): nobody reads us any more.
        _exit(0);
    }
}

__attribute__((visibility("default"))) void MediaSessionsHelperRun(void) {
    signal(SIGPIPE, SIG_DFL);
    gParentPID = getppid();
    exitIfOrphaned();

    void *handle = dlopen(kMRPath.fileSystemRepresentation, RTLD_LAZY);
    gGetClients = handle ? (MSGetClientsFn)dlsym(handle, "MRMediaRemoteGetNowPlayingClients") : NULL;
    if (gGetClients == NULL) {
        fprintf(stderr, "media-sessions: MediaRemote is unavailable\n");
        exit(1);
    }
    gQueue = dispatch_queue_create("smartwindow.media-sessions", DISPATCH_QUEUE_SERIAL);

    NSDictionary *lastState = nil;
    NSMutableDictionary<NSString *, id> *emittedArtwork = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSDictionary *> *artworkCache = [NSMutableDictionary dictionary];

    for (;;) {
        @autoreleasepool {
            exitIfOrphaned();
            NSArray *clients = nowPlayingClients();
            exitIfOrphaned();
            NSArray<NSDictionary *> *entries = readSessions(clients);
            exitIfOrphaned();
            NSDictionary<NSString *, id> *artwork = resolveArtwork(entries, artworkCache);
            exitIfOrphaned();

            NSMutableArray<NSMutableDictionary *> *sessions = [NSMutableArray array];
            NSMutableArray<NSString *> *keys = [NSMutableArray array];
            for (NSDictionary *entry in entries) {
                [sessions addObject:sessionFields(entry)];
                [keys addObject:sessionKey(entry[@"client"])];
            }
            NSString *current = currentBundleIdentifier();
            NSDictionary *state = @{
                @"current" : jsonValue(current),
                @"sessions" : sessions,
                @"artwork" : artwork,
            };

            if (![state isEqual:lastState]) {
                NSMutableArray *lineSessions = [NSMutableArray array];
                [sessions enumerateObjectsUsingBlock:^(NSMutableDictionary *session, NSUInteger index, BOOL *stop) {
                    NSMutableDictionary *line = [session mutableCopy];
                    NSString *key = keys[index];
                    id bytes = artwork[key] ?: [NSNull null];
                    if ([bytes isEqual:emittedArtwork[key] ?: [NSNull null]]) {
                        line[@"artworkUnchanged"] = @YES;
                    } else {
                        // null means the session no longer has artwork.
                        line[@"artworkData"] = [bytes isKindOfClass:[NSData class]]
                                                   ? [(NSData *)bytes base64EncodedStringWithOptions:0]
                                                   : [NSNull null];
                    }
                    [lineSessions addObject:line];
                }];
                NSDictionary *payload = @{@"current" : jsonValue(current), @"sessions" : lineSessions};
                NSData *json = [NSJSONSerialization isValidJSONObject:payload]
                                   ? [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]
                                   : nil;
                if (json != nil) {
                    writeLine(json);
                    lastState = state;
                    [emittedArtwork setDictionary:artwork];
                }
            }
        }
        sleep(MS_TICK_SECONDS);
    }
}
