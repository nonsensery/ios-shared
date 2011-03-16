//
//  SDSearchDisplayController.m
//  walmart
//
//  Created by brandon on 3/9/11.
//  Copyright 2011 Set Direction. All rights reserved.
//

#import "SDSearchDisplayController.h"

@interface SDSearchDisplayController(Private)
- (void)setup;
@end

@implementation SDSearchDisplayController

@synthesize userDefaultsKey;
@synthesize maximumCount;
@synthesize filterString;
@synthesize useAlternateResultsToMatchFilter;

static NSString *kSDSearchUserDefaultsKey = @"kSDSearchUserDefaultsKey";

- (id)initWithSearchBar:(UISearchBar *)searchBar contentsController:(UIViewController *)viewController
{
    self = [super initWithSearchBar:searchBar contentsController:viewController];
    [self setup];
    return self;
}

- (void)awakeFromNib
{
    [self setup];
}

- (void)dealloc
{
    [searchHistory release];
    [userDefaultsKey release];
    [recentSearchTableView release];
    [filterString release];
    [filteredHistory release];
    [alternateResults release];
    
    [super dealloc];
}

- (void)setup
{
    self.userDefaultsKey = kSDSearchUserDefaultsKey;
    self.maximumCount = 5;
    self.useAlternateResultsToMatchFilter = NO;
    
    alternateResults = [[NSMutableArray alloc] init];
}

- (void)setFilterString:(NSString *)value
{
    [filterString release];
    filterString = [value retain];
    
    [filteredHistory release];
    filteredHistory = nil;
    
    if (filterString && [filterString length] > 0)
    {
        if (!useAlternateResultsToMatchFilter)
        {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(SELF beginswith[cd] %@)", filterString];
            filteredHistory = [[searchHistory filteredArrayUsingPredicate:predicate] retain];
        }
        else
        {
            NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(SELF beginswith[cd] %@)", filterString];
            NSMutableArray *temp = [[alternateResults filteredArrayUsingPredicate:predicate] mutableCopy];
            [temp sortUsingSelector:@selector(compare:)];
            filteredHistory = temp;
        }
    }
    else
    {
        filteredHistory = [searchHistory retain];
        UIView *superview = self.searchContentsController.view;
        // this is sketchy, but needs to happen.  if it doesn't, our tableview ends up in the BG because something
        // internal to the searchDisplayController puts the darkened overlay over us.
        [superview performSelector:@selector(bringSubviewToFront:) withObject:recentSearchTableView afterDelay:0];
    }
}

- (void)addStringToHistory:(NSString *)string
{
    if (string && [string length] > 0)
    {
        if ([searchHistory count] == 0)
            [searchHistory addObject:string];
        else
        if ([searchHistory indexOfObject:string] == NSNotFound)
            [searchHistory insertObject:string atIndex:0];
    }
    
    if ([searchHistory count] >= self.maximumCount)
        [searchHistory removeLastObject];
    
    [[NSUserDefaults standardUserDefaults] setObject:searchHistory forKey:self.userDefaultsKey];
    // write it immediately, don't let it lazy-write.
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addArrayToHistory:(NSArray *)array
{
    for (NSString *item in array)
    {
        if ([item isKindOfClass:[NSString class]])
            [self addStringToHistory:item];
    }
}

- (void)addStringToAlternateResults:(NSString *)string
{
    if (string && [string length] > 0)
    {
        if ([alternateResults count] == 0)
            [alternateResults addObject:string];
        else
        if ([alternateResults indexOfObject:string] == NSNotFound)
            [alternateResults insertObject:string atIndex:0];
    }
    
    // may not want to do this, but it keeps things from getting out of hand.
    if ([alternateResults count] >= 500)
        [alternateResults removeObjectAtIndex:0];
}

- (void)addArrayToAlternateResults:(NSArray *)array
{
    for (NSString *item in array)
    {
        if ([item isKindOfClass:[NSString class]])
            [self addStringToAlternateResults:item];
    }
}

- (void)setActive:(BOOL)visible animated:(BOOL)animated
{
    if (!self.searchResultsDelegate)
        self.searchResultsDelegate = self;
    if (!self.searchResultsDataSource)
        self.searchResultsDataSource = self;
    
    [super setActive:visible animated:animated];
    
    if (visible && !recentSearchTableView)
    {        
        searchHistory = [[[NSUserDefaults standardUserDefaults] arrayForKey:self.userDefaultsKey] mutableCopy];
        if (!searchHistory)
            searchHistory = [[NSMutableArray alloc] init];
        
        UITableView *defaultTableView = self.searchResultsTableView;
        
        recentSearchTableView = [[UITableView alloc] initWithFrame:CGRectZero style:defaultTableView.style];
        recentSearchTableView.delegate = self;
        recentSearchTableView.dataSource = self;
        
        UIView *superview = self.searchContentsController.view;
        recentSearchTableView.frame = CGRectMake(0, 44, 320, 200);
        recentSearchTableView.alpha = 0;
        [superview addSubview:recentSearchTableView];
        
        if (animated)
        {
            [UIView animateWithDuration:0.2 animations:^{
                recentSearchTableView.alpha = 1.0;
            }];   
        }
        else
        {
            recentSearchTableView.alpha = 1.0;
        }
    }
    else
    if (!visible && recentSearchTableView)
    {
        if (animated)
        {
            [UIView animateWithDuration:0.2 
                             animations:^{
                                 recentSearchTableView.alpha = 0;
                             }
                             completion:^(BOOL finished){
                                 [recentSearchTableView removeFromSuperview];
                                 [recentSearchTableView release];
                                 recentSearchTableView = nil;
                             }];            
        }
        else
        {
            [recentSearchTableView removeFromSuperview];
            [recentSearchTableView release];
            recentSearchTableView = nil;            
        }
    }
}

#pragma mark tableview delegate/datasource methods

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 44;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView == recentSearchTableView)
    {
        // set the searchbar text here.
        self.searchBar.text = [searchHistory objectAtIndex:indexPath.row];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
    else
    {
        self.searchBar.text = [filteredHistory objectAtIndex:indexPath.row];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }

    if (self.searchBar.delegate && [self.searchBar.delegate respondsToSelector:@selector(searchBarSearchButtonClicked:)])
        [self.searchBar.delegate searchBarSearchButtonClicked:self.searchBar];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == recentSearchTableView)
    {
        if (searchHistory)
            return [searchHistory count];
    }
    else
    {
        return [filteredHistory count];        
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
    if (tableView == recentSearchTableView)
    {
        static NSString *identifier = @"SDSearchDisplayControllerHistoryCell";
        cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell)
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        
        cell.textLabel.text = [searchHistory objectAtIndex:indexPath.row];
    }
    else
    {
        static NSString *searchCell = @"SDSearchDisplayControllerCell";
        cell = [tableView dequeueReusableCellWithIdentifier:searchCell];
        if (!cell)
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:searchCell] autorelease];
        
        cell.textLabel.text = [filteredHistory objectAtIndex:indexPath.row];        
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (tableView == recentSearchTableView)
        return @"Recent Searches";
    return nil;
}

@end