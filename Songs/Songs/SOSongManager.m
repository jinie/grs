//
//  SOSongManager.m
//  Songs
//
//  Created by Steven Degutis on 3/24/13.
//  Copyright (c) 2013 Steven Degutis. All rights reserved.
//

#import "SOSongManager.h"

#import "SOSong.h"

@interface SOSongManager ()

@property SOAllSongsPlaylist* allSongsPlaylist;
@property NSMutableArray* cachedUserPlaylists;

@end

@implementation SOSongManager

+ (SOSongManager*) sharedSongManager {
    static SOSongManager* sharedSongManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSongManager = [[SOSongManager alloc] init];
        sharedSongManager.allSongsPlaylist = [[SOAllSongsPlaylist alloc] init];
        sharedSongManager.cachedUserPlaylists = [NSMutableArray array];
        
        sharedSongManager.selectedPlaylist = sharedSongManager.allSongsPlaylist;
        
        [[NSNotificationCenter defaultCenter] addObserverForName:SOMusicUserDataChangedNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
                                                          NSLog(@"user did change data");
                                                      }];
    });
    return sharedSongManager;
}

- (NSArray*) userPlaylists {
    return [self.cachedUserPlaylists copy];
}

+ (void) userDataDidChange {
    [[NSNotificationQueue defaultQueue] enqueueNotification:[NSNotification notificationWithName:SOMusicUserDataChangedNotification object:nil]
                                               postingStyle:NSPostNow];
}

- (void) loadData {
    NSData* allSongsPlaylistData = [[NSUserDefaults standardUserDefaults] dataForKey:@"allSongsPlaylist"];
    if (allSongsPlaylistData)
        self.allSongsPlaylist = [NSKeyedUnarchiver unarchiveObjectWithData:allSongsPlaylistData];
    
    NSData* userPlaylistsData = [[NSUserDefaults standardUserDefaults] dataForKey:@"userPlaylists"];
    if (userPlaylistsData)
        self.cachedUserPlaylists = [NSKeyedUnarchiver unarchiveObjectWithData:userPlaylistsData];
    
    NSLog(@"%@", self.allSongsPlaylist.songs);
}

- (void) saveSongs {
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:self.cachedUserPlaylists] forKey:@"userPlaylists"];
    [[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:self.allSongsPlaylist] forKey:@"allSongsPlaylist"];
}

- (SOPlaylist*) makeNewPlaylist {
    SOPlaylist* playlist = [[SOPlaylist alloc] init];
    [self.cachedUserPlaylists addObject:playlist];
    [SOSongManager userDataDidChange];
    return playlist;
}

- (void) importSongsUnderURLs:(NSArray*)urls {
    [[NSNotificationCenter defaultCenter] postNotificationName:SOMusicImportBeginNotification object:nil];
    
    [SOSongManager filterOnlyPlayableURLs:urls completionHandler:^(NSArray *urls) {
        [self.allSongsPlaylist addSongsWithURLs:urls];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SOMusicImportEndNotification object:nil];
    }];
}

+ (void) filterOnlyPlayableURLs:(NSArray*)urls completionHandler:(void(^)(NSArray* urls))handler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray* list = [NSMutableArray array];
        
        NSFileManager* fileManager = [[NSFileManager alloc] init];
        
        for (NSURL* url in urls) {
            BOOL isDir;
            BOOL exists = [fileManager fileExistsAtPath:[url path] isDirectory:&isDir];
            if (!exists)
                continue;
            
            if (isDir) {
                NSDirectoryEnumerator* dirEnum = [fileManager enumeratorAtURL:url
                                                   includingPropertiesForKeys:@[]
                                                                      options:NSDirectoryEnumerationSkipsPackageDescendants & NSDirectoryEnumerationSkipsHiddenFiles
                                                                 errorHandler:^BOOL(NSURL *url, NSError *error) {
                                                                     NSLog(@"error for [%@]! %@", url, error);
                                                                     return YES;
                                                                 }];
                
                for (NSURL* file in dirEnum) {
                    AVURLAsset* asset = [AVURLAsset assetWithURL:file];
                    if ([asset isPlayable]) {
                        [list addObject:file];
                    }
                }
            }
            else {
                AVURLAsset* asset = [AVURLAsset assetWithURL:url];
                if ([asset isPlayable]) {
                    [list addObject:url];
                }
            }
        }
        
        NSArray* urls = [list valueForKeyPath:@"fileReferenceURL"];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            handler(urls);
        });
    });
}

@end
