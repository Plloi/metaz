//
//  TheMovieDbSearch.m
//  MetaZ
//
//  Created by Brian Olsen on 30/12/11.
//  Copyright 2011 Maven-Group. All rights reserved.
//

#import "TheMovieDbSearch.h"
#import <MetaZKit/MZLogger.h>
#import "Access.h"
#import "TheMovieDbPlugin.h"
#import <MetaZKit/MetaZKit-Swift.h>

@implementation TheMovieDbSearch

+ (id)searchWithProvider:(id)provider delegate:(id<MZSearchProviderDelegate>)delegate queue:(NSOperationQueue *)queue
{
    return [[[self alloc] initWithProvider:provider delegate:delegate queue:queue] autorelease];
}

- (id)initWithProvider:(id)theProvider delegate:(id<MZSearchProviderDelegate>)theDelegate queue:(NSOperationQueue *)theQueue
{
    self = [super init];
    if(self)
    {
        provider = theProvider;
        delegate = [theDelegate retain];
        queue = [theQueue retain];
    }
    return self;
}

- (void)dealloc
{
    [delegate release];
    [queue release];
    [configurationRequest release];
    [imageBaseURL release];
    [super dealloc];
}

@synthesize provider;
@synthesize delegate;

- (void)cancel
{
    [delegate searchFinished];
    [delegate release];
    delegate = nil;
    [super cancel];
}

- (void)queueOperation:(NSOperation *)operation
{
    [self addOperation:operation];
    [queue addOperation:operation];
}

- (void)operationsFinished
{
    [delegate searchFinished];
}

- (void)fetchConfiguration;
{
    NSString* url = [NSString stringWithFormat:
                     @"https://api.themoviedb.org/3/configuration?api_key=%@",
                     THEMOVIEDB_API_KEY];
    configurationRequest = [[MZHTTPRequest alloc] initWithURL:[NSURL URLWithString:url]];
    [configurationRequest addRequestHeader:@"Accept" value:@"application/json"];
    [configurationRequest setDelegate:self];
    configurationRequest.cacheStoragePolicy = ASICacheForSessionDurationCacheStoragePolicy;
    configurationRequest.didFinishBackgroundSelector = @selector(fetchConfigurationCompleted:);
    configurationRequest.didFailSelector = @selector(fetchConfigurationFailed:);
    
    [self addOperation:configurationRequest];
}

- (void)fetchConfigurationCompleted:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    int status = [theRequest responseStatusCode];
    if(status >= 400) {
        [self fetchConfigurationFailed:request];
        return;
    }
 
    id obj = [NSJSONSerialization JSONObjectWithData:[theRequest responseData] options:0 error:nil];
    imageBaseURL = [[[obj objectForKey:@"images"] objectForKey:@"secure_base_url"] retain];
}

- (void)fetchConfigurationFailed:(id)request;
{
    imageBaseURL = @"https://image.tmdb.org/t/p/";
}

- (void)fetchMovieSearch:(NSString *)query
{
    NSString* url = [NSString stringWithFormat:
        @"https://api.themoviedb.org/3/search/movie?api_key=%@&language=%@&query=%@",
        THEMOVIEDB_API_KEY,
        @"en",
        [query stringByAddingPercentEncodingWithAllowedCharacters: [NSCharacterSet URLQueryAllowedCharacterSet]]
        ];

    //MZLoggerDebug(@"Sending request to %@", url);
    //MZLoggerDebug(@"Sending request to %@", [NSURL URLWithString:url]);
    MZHTTPRequest* request = [[MZHTTPRequest alloc] initWithURL:[NSURL URLWithString:url]];
    [request addRequestHeader:@"Accept" value:@"application/json"];
    [request setDelegate:self];
    request.didFinishBackgroundSelector = @selector(fetchMovieSearchCompleted:);
    request.didFailSelector = @selector(fetchMovieSearchFailed:);

    if(configurationRequest)
        [request addDependency:configurationRequest];
    
    [self addOperation:request];
    [request release];
}

- (void)fetchMovieSearchCompleted:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    int status = [theRequest responseStatusCode];
    if(status >= 400) {
        [self fetchMovieSearchFailed:request];
        return;
    }
    //MZLoggerDebug(@"Got response from cache %@", [theRequest didUseCachedResponse] ? @"YES" : @"NO");
    id doc = [NSJSONSerialization JSONObjectWithData:[theRequest responseData] options:0 error:nil];

    NSArray* items = [doc objectForKey:@"results"];
    //MZLoggerDebug(@"Got TheMovieDb results %d", [items count]);
    for(id item in items)
    {
        NSNumber* movieId = [item objectForKey:@"id"];
        [self fetchMovieInfo:movieId];
    }
}

- (void)fetchMovieSearchFailed:(id)request;
{
    //ASIHTTPRequest* theRequest = request;
    //MZLoggerDebug(@"Request failed with status code %d", [theRequest responseStatusCode]);
}



- (void)fetchMovieInfo:(NSNumber *)identifier;
{
    NSString* url = [NSString stringWithFormat:
        @"https://api.themoviedb.org/3/movie/%@?api_key=%@&language=%@&append_to_response=credits,images,releases",
        identifier,
        THEMOVIEDB_API_KEY,
        @"en"];

    //MZLoggerDebug(@"Sending request to %@", url);
    MZHTTPRequest* request = [[MZHTTPRequest alloc] initWithURL:[NSURL URLWithString:url]];
    [request addRequestHeader:@"Accept" value:@"application/json"];
    [request setDelegate:self];
    request.didFinishBackgroundSelector = @selector(fetchMovieInfoCompleted:);
    request.didFailSelector = @selector(fetchMovieInfoFailed:);

    [self queueOperation:request];
    [request release];
}

- (void)fetchMovieInfoCompleted:(id)request;
{
    ASIHTTPRequest* theRequest = request;
    int status = [theRequest responseStatusCode];
    if(status >= 400) {
        [self fetchMovieInfoFailed:request];
        return;
    }

    //MZLoggerDebug(@"Got response from cache %@", [theRequest didUseCachedResponse] ? @"YES" : @"NO");
    id doc = [NSJSONSerialization JSONObjectWithData:[theRequest responseData] options:0 error:nil];

    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    
    NSString* title = [doc objectForKey:@"title"];
    if(title && ![title isEqual:[NSNull null]] && [title length] > 0)
    {
        MZTag* tag = [MZTag tagForIdentifier:MZTitleTagIdent];
        [dict setObject:[tag objectFromString:title] forKey:MZTitleTagIdent];
    }

    NSNumber* ident = [doc objectForKey:@"id"];
    MZTag* identTag = [MZTag tagForIdentifier:TMDbIdTagIdent];
    [dict setObject:[identTag objectFromString:[ident stringValue]] forKey:TMDbIdTagIdent];

    NSString* url = [NSString stringWithFormat:@"https://www.themoviedb.org/movie/%@", ident];
    //NSString* url = [doc objectForKey:@"homepage"];
    MZTag* urlTag = [MZTag tagForIdentifier:TMDbURLTagIdent];
    [dict setObject:[urlTag objectFromString:url] forKey:TMDbURLTagIdent];

    NSString* imdbId = [doc objectForKey:@"imdb_id"];
    if(imdbId && ![imdbId isEqual:[NSNull null]] && [imdbId length] > 0)
    {
        MZTag* imdbTag = [MZTag tagForIdentifier:MZIMDBTagIdent];
        [dict setObject:[imdbTag objectFromString:imdbId] forKey:MZIMDBTagIdent];
    }

    NSString* description = [doc objectForKey:@"overview"];
    if(description && ![description isEqual:[NSNull null]] && [description length] > 0)
    {
        [dict setObject:description forKey:MZShortDescriptionTagIdent];
        [dict setObject:description forKey:MZLongDescriptionTagIdent];
    }

    NSArray* countries = [[doc objectForKey:@"releases"] objectForKey:@"countries"];
    if(countries && ![countries isEqual:[NSNull null]] && [countries count] > 0)
    {
        NSString* rating = [[countries objectAtIndex:0] objectForKey:@"certification"];
        MZTag* ratingTag = [MZTag tagForIdentifier:MZRatingTagIdent];
        NSNumber* ratingNr = [ratingTag objectFromString:rating];
        if([ratingNr intValue] != MZNoRating)
            [dict setObject:ratingNr forKey:MZRatingTagIdent];
    }

    NSString* release = [doc objectForKey:@"release_date"];
    if( release && ![release isEqual:[NSNull null]] && [release length] > 0 )
    {
        NSDateFormatter* format = [[[NSDateFormatter alloc] init] autorelease];
        format.dateFormat = @"yyyy-MM-dd";
        NSDate* date = [format dateFromString:release];
        if(date) 
            [dict setObject:date forKey:MZDateTagIdent];
        else
            MZLoggerError(@"Unable to parse release date '%@'", release);
    }
    
    
    NSDictionary* credits = [doc objectForKey:@"credits"];
    if(credits && ![credits isEqual:[NSNull null]])
    {
        NSMutableArray* directorsArray = [NSMutableArray array];
        NSMutableArray* writersArray = [NSMutableArray array];
        NSMutableArray* producersArray = [NSMutableArray array];

        id crews = [credits objectForKey:@"crew"];
        if(crews && ![crews isEqual:[NSNull null]])
        {
            for(NSDictionary* crew in crews)
            {
                NSString* department = [crew objectForKey:@"department"];
                NSString* job = [crew objectForKey:@"job"];
                NSString* name = [crew objectForKey:@"name"];
                if([department isEqualToString:@"Writing"]) {
                    [writersArray addObject:name];
                } else if([department isEqualToString:@"Directing"]) {
                    [directorsArray addObject:name];
                } else if([job rangeOfString:@"Producer"].location != NSNotFound)
                    [producersArray addObject:name];
            }
        }
    
        if([directorsArray count] > 0) {
            NSString* directors = [directorsArray componentsJoinedByString:@", "];
            [dict setObject:directors forKey:MZDirectorTagIdent];
        }
    
        if([writersArray count] > 0) {
            NSString* writers = [writersArray componentsJoinedByString:@", "];
            [dict setObject:writers forKey:MZScreenwriterTagIdent];
        }
    
        if([producersArray count] > 0) {
            NSString* producers = [producersArray componentsJoinedByString:@", "];
            [dict setObject:producers forKey:MZProducerTagIdent];
        }

        NSMutableArray* actorsArray = [NSMutableArray array];
        id casts = [credits objectForKey:@"cast"];
        if(crews && ![crews isEqual:[NSNull null]])
        {
            for(NSDictionary* member in casts)
            {
                [actorsArray addObject:[member objectForKey:@"name"]];
            }
        }
        if([actorsArray count] > 0) {
            NSString* actors = [actorsArray componentsJoinedByString:@", "];
            [dict setObject:actors forKey:MZActorsTagIdent];
            [dict setObject:actors forKey:MZArtistTagIdent];
        }
    }

    
    NSArray* genres = [doc objectForKey:@"genres"];
    if(genres && ![genres isEqual:[NSNull null]] && [genres count] > 0) {
        NSString* genre = [[genres objectAtIndex:0] objectForKey:@"name"];
        [dict setObject:genre forKey:MZGenreTagIdent];
    }
    
    id imageJson = [doc objectForKey:@"images"];
    if(imageJson && ![imageJson isEqual:[NSNull null]])
    {
        NSArray* posters = [imageJson objectForKey:@"posters"];
        if(posters && ![posters isEqual:[NSNull null]])
        {
            NSMutableArray* images = [NSMutableArray array];
            for(NSDictionary* poster in posters)
            {
                NSString* path = [poster objectForKey:@"file_path"];
                NSString* url = [NSString stringWithFormat:@"%@%@%@", imageBaseURL, @"original", path];
                RemoteData* data = [[[RemoteData alloc] initWithImageUrl: [NSURL URLWithString:url]] autorelease];
                //MZRemoteData* data = [MZRemoteData imageDataWithURL:[NSURL URLWithString:url]];
                [images addObject:data];
                [data loadData];
            }
            if([images count] > 0)
                [dict setObject:[NSArray arrayWithArray:images] forKey:MZPictureTagIdent];
        }
    }

    MZSearchResult* result = [MZSearchResult resultWithOwner:provider dictionary:dict];
    [self performSelectorOnMainThread:@selector(providedResult:) withObject:result waitUntilDone:NO];
}

- (void)providedResult:(MZSearchResult *)result
{
    [delegate searchProvider:provider result:[NSArray arrayWithObject:result]];
}

- (void)fetchMovieInfoFailed:(id)request;
{
    //ASIHTTPRequest* theRequest = request;
    //MZLoggerDebug(@"Request failed with status code %d", [theRequest responseStatusCode]);
}

@end
