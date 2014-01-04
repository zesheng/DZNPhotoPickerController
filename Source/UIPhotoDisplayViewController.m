//
//  UIPhotoDisplayController.m
//  UIPhotoPickerController
//  https://github.com/dzenbot/UIPhotoPickerController
//
//  Created by Ignacio Romero Zurbuchen on 10/5/13.
//  Copyright (c) 2013 DZN Labs. All rights reserved.
//  Licence: MIT-Licence
//

#import "UIPhotoDisplayViewController.h"
#import "UIPhotoPickerController.h"
#import "UIPhotoEditViewController.h"

#import "UIPhotoDisplayViewCell.h"
#import "UIPhotoDescription.h"

static NSString *kThumbCellID = @"kThumbCellID";
static NSString *kThumbHeaderID = @"kThumbHeaderID";
static NSString *kThumbFooterID = @"kThumbFooterID";

@interface UIPhotoDisplayViewController () <UISearchDisplayDelegate, UISearchBarDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) NSMutableArray *photoDescriptions;
@property (nonatomic, readwrite) UISearchBar *searchBar;
@property (nonatomic, readwrite) UIButton *loadButton;
@property (nonatomic, readwrite) UIView *overlayView;
@property (nonatomic, readwrite) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) NSArray *controlTitles;
@property (nonatomic) UIPhotoPickerControllerServiceType selectedService;
@property (nonatomic) UIPhotoPickerControllerServiceType previousService;
@property (nonatomic) int resultPerPage;
@property (nonatomic) int currentPage;

@property (nonatomic, strong) PXRequest *PXRequest;

@end

@implementation UIPhotoDisplayViewController

- (id)init
{
    self = [super initWithCollectionViewLayout:[UIPhotoDisplayViewController flowLayout]];
    if (self) {
        
        self.title = NSLocalizedString(@"Internet Photos", nil);
        _selectedService = UIPhotoPickerControllerServiceType500px;
        _previousService = UIPhotoPickerControllerServiceTypeNone;
        _currentPage = 1;
    }
    return self;
}


#pragma mark - View lifecycle

- (void)loadView
{
    [super loadView];
    
    self.collectionView.backgroundView = [UIView new];
    self.collectionView.backgroundView.backgroundColor = [UIColor whiteColor];
    
    self.edgesForExtendedLayout = UIRectEdgeTop;
    self.extendedLayoutIncludesOpaqueBars = NO;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _columnCount = 4;
    _rowCount = [self rowCount];
    _resultPerPage = _columnCount*_rowCount;
    
    [self.collectionView registerClass:[UIPhotoDisplayViewCell class] forCellWithReuseIdentifier:kThumbCellID];
    [self.collectionView registerClass:[UICollectionReusableView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:kThumbHeaderID];
    [self.collectionView registerClass:[UICollectionReusableView class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                   withReuseIdentifier:kThumbFooterID];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (!_photoDescriptions) {
        _photoDescriptions = [NSMutableArray new];

        if (_searchTerm.length > 0) {
            self.searchBar.text = _searchTerm;
            [self searchPhotosWithKeyword:_searchTerm];
        }
        else {
            [self.searchBar becomeFirstResponder];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}


#pragma mark - Getter methods

+ (UICollectionViewFlowLayout *)flowLayout
{
    UICollectionViewFlowLayout *flowLayout = [[UICollectionViewFlowLayout alloc] init];
    flowLayout.minimumLineSpacing = 2.0;
    flowLayout.minimumInteritemSpacing = 0.0;
    return flowLayout;
}

- (CGSize)cellSize
{
    UICollectionViewFlowLayout *flowLayout = (UICollectionViewFlowLayout *)self.collectionViewLayout;
    CGFloat size = (self.navigationController.view.bounds.size.width/_columnCount) - flowLayout.minimumLineSpacing;
    return CGSizeMake(size, size);
}

- (CGSize)headerSize
{
    return [_searchBar isFirstResponder] ? CGSizeMake(0, 94.0) : CGSizeMake(0, 50.0);
}

- (CGSize)footerSize
{
    return CGSizeMake(0, (self.navigationController.view.frame.size.height > 480.0) ? 60.0 : 50.0);
}

- (UIPhotoPickerController *)navigationController
{
    return (UIPhotoPickerController *)[super navigationController];
}

- (UISearchBar *)searchBar
{
    if (!_searchBar)
    {
        _searchBar = [[UISearchBar alloc] initWithFrame:CGRectZero];
        _searchBar.placeholder = NSLocalizedString(@"Search", nil);
        _searchBar.barStyle = UIBarStyleDefault;
        _searchBar.searchBarStyle = UISearchBarStyleProminent;
        _searchBar.backgroundColor = [UIColor whiteColor];
        _searchBar.barTintColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        _searchBar.tintColor = self.view.window.tintColor;
        _searchBar.keyboardType = UIKeyboardAppearanceDark;
        _searchBar.delegate = self;
        
        [self.view addSubview:self.overlayView];
    }
    return _searchBar;
}

- (UIButton *)loadButton
{
    if (!_loadButton)
    {
        _loadButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_loadButton setTitle:NSLocalizedString(@"Load More", nil) forState:UIControlStateNormal];
        [_loadButton setTitleColor:[UIColor clearColor] forState:UIControlStateNormal];
        [_loadButton addTarget:self action:@selector(downloadData) forControlEvents:UIControlEventTouchUpInside];
        [_loadButton.titleLabel setFont:[UIFont systemFontOfSize:17.0]];
        [_loadButton setBackgroundColor:self.collectionView.backgroundView.backgroundColor];
        
        [_loadButton addSubview:self.activityIndicator];
    }
    return _loadButton;
}

- (UIActivityIndicatorView *)activityIndicator
{
    if (!_activityIndicator)
    {
        _activityIndicator = [[UIActivityIndicatorView alloc] init];
        _activityIndicator.hidesWhenStopped = YES;
    }
    _activityIndicator.center = _activityIndicator.superview.center;
    return _activityIndicator;
}

/*
 * The overlay to be used when the search bar is first responder.
 * This mimics the same behavior than the UISearchDisplayController when dimming the content view with a dark overlay.
 */
- (UIView *)overlayView
{
    if (!_overlayView)
    {
        CGFloat barHeight = self.navigationController.navigationBar.frame.size.height*2;
        _overlayView = [[UIView alloc] initWithFrame:CGRectMake(0, barHeight+[UIApplication sharedApplication].statusBarFrame.size.height, self.view.bounds.size.width, self.view.bounds.size.height-barHeight)];
        _overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
        _overlayView.alpha = 0;
        _overlayView.hidden = YES;
        
        UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [_overlayView addGestureRecognizer:tapGesture];
    }
    return _overlayView;
}

/*
 * The collectionView's content size calculation.
 */
- (CGSize)contentSize
{
    CGFloat viewHeight = self.navigationController.view.frame.size.height;
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        CGFloat statusHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
        viewHeight -= statusHeight;
    }
    
    CGFloat navigationHeight = self.navigationController.navigationBar.frame.size.height;
    viewHeight -= navigationHeight;
    
    CGFloat headerSize = [self headerSize].height;
    viewHeight -= headerSize;
    
    return CGSizeMake(self.navigationController.view.frame.size.width, viewHeight);
}

/*
 * Dinamically calculate the available row count based on the collectionView's content size and the cell height.
 * This allows to easily modify the collectionView layout, for displaying the image thumbs.
 */
- (NSUInteger)rowCount
{
    CGSize contentSize = [self contentSize];
    
    CGFloat footerSize = [self footerSize].height;
    contentSize.height -= footerSize;
    
    CGFloat cellHeight = [self cellSize].height;
    
    NSUInteger count = (int)(contentSize.height/cellHeight);
    return count;
}

/*
 * Returns the segmented control titles, based on the service types to support.
 * Default returns "500px" & "Flickr".
 */
- (NSArray *)controlTitles
{
    if (!_controlTitles)
    {
        NSMutableArray *titles = [NSMutableArray array];
        
        if ((self.navigationController.serviceType & UIPhotoPickerControllerServiceType500px) > 0) {
            [titles addObject:NSStringFromServiceType(UIPhotoPickerControllerServiceType500px)];
        }
        if ((self.navigationController.serviceType & UIPhotoPickerControllerServiceTypeFlickr) > 0) {
            [titles addObject:NSStringFromServiceType(UIPhotoPickerControllerServiceTypeFlickr)];
        }
        if ((self.navigationController.serviceType & UIPhotoPickerControllerServiceTypeGoogleImages) > 0) {
            [titles addObject:NSStringFromServiceType(UIPhotoPickerControllerServiceTypeGoogleImages)];
        }
        if ((self.navigationController.serviceType & UIPhotoPickerControllerServiceTypeBingImages) > 0) {
            [titles addObject:NSStringFromServiceType(UIPhotoPickerControllerServiceTypeBingImages)];
        }
        if ((self.navigationController.serviceType & UIPhotoPickerControllerServiceTypeYahooImages) > 0) {
            [titles addObject:NSStringFromServiceType(UIPhotoPickerControllerServiceTypeYahooImages)];
        }
        if ((self.navigationController.serviceType & UIPhotoPickerControllerServiceTypePanoramio) > 0) {
            [titles addObject:NSStringFromServiceType(UIPhotoPickerControllerServiceTypePanoramio)];
        }
        if ((self.navigationController.serviceType & UIPhotoPickerControllerServiceTypeInstagram) > 0) {
            [titles addObject:NSStringFromServiceType(UIPhotoPickerControllerServiceTypeInstagram)];
        }
        
        _controlTitles = [NSArray arrayWithArray:titles];
    }
    return _controlTitles;
}

/*
 * Returns the service name string based on the service enum type.
 */
NSString *NSStringFromServiceType(UIPhotoPickerControllerServiceType service)
{
    switch (service) {
        case UIPhotoPickerControllerServiceType500px:
            return @"500px";
            
        case UIPhotoPickerControllerServiceTypeFlickr:
            return @"Flickr";
            
        case UIPhotoPickerControllerServiceTypeGoogleImages:
            return @"Google Images";
            
        case UIPhotoPickerControllerServiceTypeBingImages:
            return @"Bing Images";
            
        case UIPhotoPickerControllerServiceTypeYahooImages:
            return @"Yahoo Images";
            
        case UIPhotoPickerControllerServiceTypePanoramio:
            return @"Panoramio";
            
        case UIPhotoPickerControllerServiceTypeInstagram:
            return @"Instagram";
            
        default:
            return nil;
    }
}

/*
 * Returns the selected service name.
 */
- (NSString *)selectedServiceName
{
    return NSStringFromServiceType(_selectedService);
}

/*
 * Returns the a complete & valide source url of a specific service url.
 * This applies only for some photo search services, that do not expose the source url on their API.
 */
- (NSString *)sourceUrlForImageUrl:(NSString *)url
{
    switch (_selectedService) {
        case UIPhotoPickerControllerServiceType500px:
            return nil;
            
        case UIPhotoPickerControllerServiceTypeFlickr:
        {
            NSArray *components = [url componentsSeparatedByString:@"/"];
            NSString *lastComponent = [components lastObject];
            
            NSArray *ids = [lastComponent componentsSeparatedByString:@"_"];
            
            if (ids.count > 0) {
                NSString *photoId = [ids objectAtIndex:0];
                NSString *profileUrl = [NSString stringWithFormat:@"http://flickr.com/photo.gne?id=%@/", photoId];
                return [NSURL URLWithString:profileUrl];
            }
            else {
                return nil;
            }
        }
            
        case UIPhotoPickerControllerServiceTypeGoogleImages:
            return nil;
            
        case UIPhotoPickerControllerServiceTypeBingImages:
            return nil;
            
        case UIPhotoPickerControllerServiceTypeYahooImages:
            return nil;
            
        default:
            return nil;
    }
}

/*
 * Returns a list of photo descriptions from a request response.
 * This is the simple parser to created custom data model objects.
 */
- (NSArray *)photoDescriptionsFromResponse:(NSArray *)reponse
{
    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:reponse.count];
    
    if ((_selectedService & UIPhotoPickerControllerServiceType500px) > 0) {
        for (NSDictionary *object in reponse) {

            UIPhotoDescription *description = [UIPhotoDescription photoDescriptionWithTitle:[object valueForKey:@"username"]
                                             authorName:[NSString stringWithFormat:@"%@ %@",[object valueForKeyPath:@"user.firstname"],[object valueForKeyPath:@"user.lastname"]]
                                               thumbURL:[NSURL URLWithString:[[[object valueForKey:@"images"] objectAtIndex:0] valueForKey:@"url"]]
                                                fullURL:[NSURL URLWithString:[[[object valueForKey:@"images"] objectAtIndex:1] valueForKey:@"url"]]
                                             sourceName:[self selectedServiceName]];
            
            [result addObject:description];
        }
    }
    else if ((_selectedService & UIPhotoPickerControllerServiceTypeFlickr) > 0) {
        for (NSDictionary *object in reponse) {
            
            UIPhotoDescription *description = [UIPhotoDescription photoDescriptionWithTitle:[object valueForKey:@"title"]
                                             authorName:[object valueForKey:@"owner"]
                                               thumbURL:[[FlickrKit sharedFlickrKit] photoURLForSize:FKPhotoSizeLargeSquare150 fromPhotoDictionary:object]
                                                fullURL:[[FlickrKit sharedFlickrKit] photoURLForSize:FKPhotoSizeLarge1024 fromPhotoDictionary:object]
                                             sourceName:[self selectedServiceName]];
            
            [result addObject:description];
        }
    }
    
    return result;
}

/*
 * Checks if an additional footer for loading more content should be displayed.
 */
- (BOOL)shouldShowFooter
{
    return (_photoDescriptions.count%_resultPerPage == 0) ? YES : NO;
}


#pragma mark - Setter methods

- (void)resetPhotos
{
    [self setPhotoDescriptions:nil];
    _photoDescriptions = [NSMutableArray new];
    
    _currentPage = 1;
    
    [self.collectionView reloadData];
}


#pragma mark - UIPhotoDisplayController methods

- (void)handleResponse:(NSArray *)response
{
    [self showActivityIndicators:NO];
    
    [_photoDescriptions addObjectsFromArray:[self photoDescriptionsFromResponse:response]];
    [self.collectionView reloadData];
}

- (void)handleError:(NSError *)error
{
    [self showActivityIndicators:NO];
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", nil) message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles: nil];
    [alert show];
}

- (void)showActivityIndicators:(BOOL)visible
{
    if ([UIApplication sharedApplication].networkActivityIndicatorVisible == visible) {
        return;
    }
    
    [UIApplication sharedApplication].networkActivityIndicatorVisible = visible;
    
    if (visible) {
        [self.activityIndicator startAnimating];
        [_loadButton setTitleColor:[UIColor clearColor] forState:UIControlStateNormal];
    }
    else {
        [self.activityIndicator stopAnimating];
    }
    
    _loading = visible;
}

- (void)handleSelectionAtIndexPath:(NSIndexPath *)indexPath
{
    UIPhotoDescription *description = [_photoDescriptions objectAtIndex:indexPath.row];
    
    if (self.navigationController.allowsEditing) {
        
        NSLog(@"self.navigationController.editingMode : %d", self.navigationController.editingMode);
        
        UIPhotoEditViewController *photoEditViewController = [[UIPhotoEditViewController alloc] initWithPhotoDescription:description cropMode:self.navigationController.editingMode];
        photoEditViewController.cropSize = self.navigationController.customCropSize;
        
        [self.navigationController pushViewController:photoEditViewController animated:YES];
    }
    else {
        
        [self showActivityIndicators:YES];

        [[SDWebImageDownloader sharedDownloader] downloadImageWithURL:description.fullURL
                                                              options:SDWebImageCacheMemoryOnly|SDWebImageLowPriority
                                                             progress:NULL
                                                            completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished){
                                                                if (!error) {
                                                                    [UIPhotoEditViewController didFinishPickingEditedImage:nil
                                                                                                              withCropRect:CGRectZero
                                                                                                         fromOriginalImage:image
                                                                                                              referenceURL:description.fullURL
                                                                                                                authorName:description.authorName
                                                                                                                sourceName:description.sourceName];
                                                                }
                                                                else {
                                                                    [self handleError:error];
                                                                }
                                                                
                                                                [self showActivityIndicators:NO];
                                                            }];
    }
    
    [self.collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

- (void)searchPhotosWithKeyword:(NSString *)keyword
{
    [self showActivityIndicators:YES];
    _searchTerm = keyword;
    
    if ((_selectedService & UIPhotoPickerControllerServiceType500px) > 0) {
        
        NSString *term = [_searchTerm stringByReplacingOccurrencesOfString:@" " withString:@"+"];
        
        _PXRequest = [PXRequest requestForSearchTerm:term page:_currentPage resultsPerPage:_resultPerPage
                             photoSizes:PXPhotoModelSizeSmallThumbnail | PXPhotoModelSizeExtraLarge
                                 except:PXPhotoModelCategoryUncategorized
                             completion:^(NSDictionary *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (response) [self handleResponse:[response valueForKey:@"photos"]];
                else [self handleError:error];
            });
        }];
    }
    else if ((_selectedService & UIPhotoPickerControllerServiceTypeFlickr) > 0) {
        
        FKFlickrPhotosSearch *search = [[FKFlickrPhotosSearch alloc] init];
        search.text = _searchTerm; //[keyword stringByReplacingOccurrencesOfString:@" " withString:@" OR "];
        search.content_type = @"1";
        search.safe_search = @"1";
        search.media = @"photos";
        search.in_gallery = @"true";
        search.per_page = [NSString stringWithFormat:@"%d",_resultPerPage];
        search.page = [NSString stringWithFormat:@"%d",_currentPage];

        [[FlickrKit sharedFlickrKit] call:search completion:^(NSDictionary *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (response) [self handleResponse:[response valueForKeyPath:@"photos.photo"]];
                else [self handleError:error];
            });
        }];
    }
}

- (void)stopAnyRequest
{
    [self showActivityIndicators:NO];
    
    if ((_selectedService & UIPhotoPickerControllerServiceType500px) > 0) {
        
        if (_PXRequest) {
            [_PXRequest cancel];
            _PXRequest = nil;
        }
    }
    else if ((_selectedService & UIPhotoPickerControllerServiceTypeFlickr) > 0) {
        
//        [FlickrKit sharedFlickrKit]
    }
    
    for (UIPhotoDisplayViewCell *cell in [self.collectionView visibleCells]) {
        [cell.imageView cancelCurrentImageLoad];
    }
}

- (void)downloadData
{
    _loadButton.enabled = NO;
    
    _currentPage++;
    [self searchPhotosWithKeyword:_searchTerm];
}

- (void)handleTap:(UITapGestureRecognizer *)gesture
{
    if ([_searchBar isFirstResponder]) {
        [_searchBar resignFirstResponder];
    }
}


#pragma mark - UICollectionViewDataSource methods

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return _photoDescriptions.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UIPhotoDisplayViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kThumbCellID forIndexPath:indexPath];
    cell.tag = indexPath.row;
    
    UIPhotoDescription *description = [_photoDescriptions objectAtIndex:indexPath.row];
    
    [cell.imageView cancelCurrentImageLoad];
    [cell.imageView setImageWithURL:description.thumbURL placeholderImage:nil
                              options:SDWebImageCacheMemoryOnly|SDWebImageRetryFailed completed:NULL];
    
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    if ([kind isEqualToString:UICollectionElementKindSectionHeader]) {
        
        UICollectionReusableView *header = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:kThumbHeaderID forIndexPath:indexPath];
        
        if (header.subviews.count == 0) {
            CGRect rect = header.frame;
            rect.size.height = 44.0;
            
            [header addSubview:self.searchBar];
            _searchBar.frame = rect;
            _searchBar.scopeButtonTitles = self.controlTitles;
            _searchBar.selectedScopeButtonIndex = _selectedService-1;
        }
        
        return header;
    }
    else if ([kind isEqualToString:UICollectionElementKindSectionFooter]) {
        
        UICollectionReusableView *footer = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:kThumbFooterID forIndexPath:indexPath];
        
        if ([self shouldShowFooter]) {
            if (footer.subviews.count == 0) {
                [footer addSubview:self.loadButton];
            }
            _loadButton.frame = footer.bounds;
            
            if (_photoDescriptions.count > 0) {
                _loadButton.enabled = YES;
                [_loadButton setTitleColor:self.view.window.tintColor forState:UIControlStateNormal];

                [self.activityIndicator setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleGray];
            }
            else {
                _loadButton.enabled = NO;
                [_loadButton setTitleColor:[UIColor clearColor] forState:UIControlStateNormal];

                [self.activityIndicator setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
                self.activityIndicator.color = [UIColor grayColor];
            }
        }
        else {
            [_loadButton removeFromSuperview];
            [self setLoadButton:nil];
        }
        return footer;
    }
    return nil;
}


#pragma mark - UICollectionViewDataDelegate methods

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath;
{
    if ([[UIMenuController sharedMenuController] isMenuVisible]) {
        return NO;
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    [collectionView selectItemAtIndexPath:indexPath animated:YES scrollPosition:UICollectionViewScrollPositionCenteredHorizontally];

    if ([_searchBar isFirstResponder]) {
        [_searchBar resignFirstResponder];
        [self performSelector:@selector(handleSelectionAtIndexPath:) withObject:indexPath afterDelay:0.3];
    }
    else [self handleSelectionAtIndexPath:indexPath];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath
{
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([[UIMenuController sharedMenuController] isMenuVisible]) {
        return NO;
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath;
{

}

- (void)collectionView:(UICollectionView *)collectionView didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath;
{
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath
{
    
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingSupplementaryView:(UICollectionReusableView *)view forElementOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self cellSize];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section
{
    return [self headerSize];
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForFooterInSection:(NSInteger)section
{
    CGSize size = CGSizeZero;
    if (_photoDescriptions.count == 0) size = [self contentSize];
    else size = [self footerSize];
    
    return size;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath
{
    UIPhotoDisplayViewCell *cell = (UIPhotoDisplayViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
    if (cell.imageView.image) {
        return YES;
    }
    return NO;
}

- (BOOL)collectionView:(UICollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if (![NSStringFromSelector(action) isEqualToString:@"copy:"]) {
        return NO;
    }
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if ([NSStringFromSelector(action) isEqualToString:@"copy:"])
    {
        UIPhotoDisplayViewCell *cell = (UIPhotoDisplayViewCell *)[collectionView cellForItemAtIndexPath:indexPath];

        UIImage *image = cell.imageView.image;
        if (image) [[UIPasteboard generalPasteboard] setImage:image];
    }
}


#pragma mark - UISearchBarDelegate methods

- (BOOL)searchBarShouldBeginEditing:(UISearchBar *)searchBar
{
    if (_loading) {
        [self stopAnyRequest];
    }
    return YES;
}

- (BOOL)searchBarShouldEndEditing:(UISearchBar *)searchBar
{
    return YES;
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    [searchBar setShowsCancelButton:YES animated:YES];
    
    _overlayView.hidden = NO;

    [UIView animateWithDuration:0.4 animations:^{
        
        _overlayView.alpha = 1.0;
        
        [searchBar setShowsScopeBar:YES];
        [searchBar sizeToFit];
        [self.collectionViewLayout invalidateLayout];
        
    }];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar
{
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [searchBar setShowsCancelButton:NO animated:YES];
    
    [UIView animateWithDuration:0.4 animations:^{
        
        _overlayView.alpha = 0;

        [searchBar setShowsScopeBar:NO];
        [searchBar sizeToFit];
        [self.collectionViewLayout invalidateLayout];
        
    } completion:^(BOOL finished){
        _overlayView.hidden = YES;
    }];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    [searchBar setText:nil];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar
{
    [searchBar resignFirstResponder];
    
    if (_previousService != _selectedService || _searchTerm != searchBar.text) {
        _previousService = _selectedService;
        [self resetPhotos];

        [self searchPhotosWithKeyword:searchBar.text];
    }
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{
    
}

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope
{
    _selectedService = (1 << selectedScope);
}


#pragma mark - View lifeterm

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}


#pragma mark - View Auto-Rotation

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

- (BOOL)shouldAutorotate
{
    return NO;
}

@end