//
//  MAMHNController.m
//  Hacker News
//
//  Created by mmackh on 6/15/13.
//  Copyright (c) 2013 Maximilian Mackh. All rights reserved.
//

#import "MAMHNController.h"

// Dependancies
#import "AFNetworking/AFNetworking.h"
#import "RXMLElement.h"
#import "TFHpple.h"

@implementation MAMHNController

+ (BOOL)isPad
{
    static BOOL isPad;
    static int isSet = 0;
    if (isSet == 0)
    {
        isPad = (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad);
        isSet = 1;
    }
    return isPad;
}

+ (id)sharedController
{
    static dispatch_once_t onceToken;
    static MAMHNController *hnController;
    dispatch_once(&onceToken, ^{
        hnController = [[self alloc] init];
    });
    return hnController;
}

- (id)init
{
    self = [super init];
    if(!self) return nil;
    [[AFNetworkActivityIndicatorManager sharedManager] setEnabled:YES];
    [AFHTTPRequestOperation addAcceptableContentTypes:[NSSet setWithObjects:@"application/rss+xml",@"text/html",nil]];
    return self;
}

- (void)loadStoriesOfType:(HNControllerStoryType)storyType result:(void(^)(NSArray *results))completionBlock
{
    static const NSString *host = @"http://api.thequeue.org/hn/";
    NSString *targetURLString;
   
    switch (storyType)
    {
        case HNControllerStoryTypeTrending:
            targetURLString = [host stringByAppendingString:@"frontpage.xml"];
            break;
        case HNControllerStoryTypeNew:
            targetURLString = [host stringByAppendingString:@"new.xml"];
            break;
        case HNControllerStoryTypeBest:
            targetURLString = [host stringByAppendingString:@"best.xml"];
            break;
    }
    
    __weak id weakSelf = self;
    
    NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:targetURLString] cachePolicy:NSURLCacheStorageNotAllowed timeoutInterval:10];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setCacheResponseBlock:^NSCachedURLResponse *(NSURLConnection *connection, NSCachedURLResponse *cachedResponse) { return nil; }];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        NSString *responseString = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
        NSMutableArray *results = [[NSMutableArray alloc] init];
        
        RXMLElement *rootXML = [RXMLElement elementFromXMLString:responseString encoding:NSUTF8StringEncoding];
        [rootXML iterate:@"channel.item" usingBlock: ^(RXMLElement *e)
        {
            MAMHNStory *story = [[MAMHNStory alloc] init];
            [story setTitle:[e child:@"title"].text];
            [story setDescription:[e child:@"description"].text];
            [story setPubDate:[e child:@"pubDate"].text];
            [story setScore:[e child:@"score"].text];
            [story setUser:[e child:@"user"].text];
            [story setCommentsValue:[e child:@"comments"].text];
            [story setHnID:[e child:@"id"].text];
            [story setDiscussionLink:[e child:@"discussion"].text];
            [story setLink:[e child:@"link"].text];
            [results addObject:story];
        }];
        completionBlock(results);
        [NSKeyedArchiver archiveRootObject:results toFile:[weakSelf pathForPersistedStoriesOfType:storyType]];
    }
    failure:^(AFHTTPRequestOperation *operation, NSError *error)
    {
        NSLog(@"%@",error.description);
    }];
    [operation start];
}

- (void)loadCommentsOnStoryWithID:(NSString *)storyID result:(void(^)(NSArray *results))completionBlock
{
    NSString *queryURLString = [NSString stringWithFormat:@"https://news.ycombinator.com/item?id=%@",storyID];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:queryURLString] cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:10];
    AFHTTPRequestOperation *operation = [[AFHTTPRequestOperation alloc] initWithRequest:request];
    [operation setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject)
    {
        
        NSMutableArray *comments = [NSMutableArray new];
        
        TFHpple * doc       = [[TFHpple alloc] initWithHTMLData:responseObject];
        NSArray * elements  = [doc searchWithXPathQuery:@"//html/body/center/table/tr[3]/td/table[2]"];
        if (!elements.count) { completionBlock(nil); return; }
        NSArray *rawElements = [[elements objectAtIndex:0] children];
        for (TFHppleElement *element in rawElements)
        {
            TFHpple *comment = [[TFHpple alloc] initWithHTMLData:[[element raw] dataUsingEncoding:NSUTF8StringEncoding]];
            
            NSArray *rawCommentQuery = [comment searchWithXPathQuery:@"//span/font"];
            if (!rawCommentQuery.count)continue;
            NSString *commentHTML = [[rawCommentQuery objectAtIndex:0] raw];
          
            NSArray *indentationLevelQuery = [comment searchWithXPathQuery:@"//td/img"];
            int indentationLevel = [[[indentationLevelQuery objectAtIndex:0] objectForKey:@"width"] intValue] / 40;
            
            NSArray *usernameQuery = [comment searchWithXPathQuery:@"//div/span/a"];
            NSString *username = [[usernameQuery objectAtIndex:0] text];
        
            NSArray *timeQuery = [comment searchWithXPathQuery:@"//td/div/span"];
            NSString *time = [[[timeQuery objectAtIndex:0] text] stringByReplacingOccurrencesOfString:@"  | " withString:@""];
            
            NSArray *replyIDQuery = [comment searchWithXPathQuery:@"//font/u/a"];
            if (!replyIDQuery.count)continue;
            NSString *replyID = [[replyIDQuery objectAtIndex:0] objectForKey:@"href"];
            
            MAMHNComment *newComment = [MAMHNComment new];
            [newComment setComment:commentHTML];
            [newComment setTime:time];
            [newComment setUsername:username];
            [newComment setReplyID:replyID];
            [newComment setIndentationLevel:indentationLevel];
            [comments addObject:newComment];
        }
        completionBlock(comments);
    }
    failure:^(AFHTTPRequestOperation *operation, NSError *error)
    {
        NSLog(@"%@",error.description);
    }];
    [operation start];
    
}

- (void)loopWithObjectContainingPossbileObjects:(id)object completion:(void(^)(id result))block
{
    
}

#pragma mark -
#pragma mark Cache

- (NSArray *)loadStoriesFromCacheOfType:(HNControllerStoryType)storyType
{
    NSString *path = [self pathForPersistedStoriesOfType:storyType];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    NSArray *results = [NSKeyedUnarchiver unarchiveObjectWithFile:[self pathForPersistedStoriesOfType:storyType]];
    return results;
}

- (NSString *)pathForPersistedStoriesOfType:(HNControllerStoryType)storyType
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [NSString stringWithFormat:@"%@/x%ihn",[paths objectAtIndex:0],storyType];
}

@end
