//
//  FGalleryPhoto.m
//  FGallery
//
//  Created by Grant Davis on 5/20/10.
//  Copyright 2011 Grant Davis Interactive, LLC. All rights reserved.
//

#import "FGalleryPhoto.h"

@interface FGalleryPhoto (Private)

// delegate notifying methods
- (void)willLoadThumbFromUrl;
- (void)willLoadFullsizeFromUrl;
- (void)willLoadThumbFromPath;
- (void)willLoadFullsizeFromPath;
- (void)didLoadThumbnail;
- (void)didLoadFullsize;

// loading local images with threading
- (void)loadFullsizeInThread;
- (void)loadThumbnailInThread;

// cleanup
- (void)killThumbnailLoadObjects;
- (void)killFullsizeLoadObjects;

-(UIImage*) decompressedThumbnailImageUsingData_:(NSData*)data;
@end


@implementation FGalleryPhoto
@synthesize tag;
@synthesize thumbnail = _thumbnail;
@synthesize fullsize = _fullsize;
@synthesize delegate = _delegate;
@synthesize renderThumbnailInThread;
@synthesize sourceHasAlpha;
@synthesize isFullsizeLoading = _isFullsizeLoading;
@synthesize hasFullsizeLoaded = _hasFullsizeLoaded;
@synthesize isThumbLoading = _isThumbLoading;
@synthesize hasThumbLoaded = _hasThumbLoaded;


- (id)initWithThumbnailUrl:(NSString*)thumb fullsizeUrl:(NSString*)fullsize delegate:(NSObject<FGalleryPhotoDelegate>*)delegate
{
	self = [super init];
	_useNetwork = YES;
	_thumbUrl = [thumb retain];
	_fullsizeUrl = [fullsize retain];
	_delegate = delegate;
	return self;
}

- (id)initWithThumbnailPath:(NSString*)thumb fullsizePath:(NSString*)fullsize delegate:(NSObject<FGalleryPhotoDelegate>*)delegate
{
	self = [super init];
	
	_useNetwork = NO;
	_thumbUrl = [thumb retain];
	_fullsizeUrl = [fullsize retain];
	_delegate = delegate;
	return self;
}


- (void)loadThumbnail
{
	if( _isThumbLoading || _hasThumbLoaded ) return;
	
	// load from network
	if( _useNetwork )
	{
		// notify delegate
		[self willLoadThumbFromUrl];
		
		_isThumbLoading = YES;
		
		NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:_thumbUrl]];
		_thumbConnection = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
		_thumbData = [[NSMutableData alloc] init];
	}
	
	// load from disk
	else {
		
		// notify delegate
		[self willLoadThumbFromPath];
		
		_isThumbLoading = YES;
		
        NSOperationQueue *operationQueue = [_delegate galleryPhotoNeedsOperationQueueForImageLoading:self];
        NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^(void) {
            [self loadThumbnailInThread];
        }];
        [operationQueue addOperation:op];
	}
}


- (void)loadFullsize
{
	if( _isFullsizeLoading || _hasFullsizeLoaded ) return;
	
	if( _useNetwork )
	{
		// notify delegate
		[self willLoadFullsizeFromUrl];
		
		_isFullsizeLoading = YES;
		
		NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:_fullsizeUrl]];
		_fullsizeConnection = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
		_fullsizeData = [[NSMutableData alloc] init];
	}
	else
	{
		[self willLoadFullsizeFromPath];
		
		_isFullsizeLoading = YES;
		
		// spawn a new thread to load from disk
		[NSThread detachNewThreadSelector:@selector(loadFullsizeInThread) toTarget:self withObject:nil];
	}
}


- (void)loadFullsizeInThread
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
    NSString *path = nil;
    if([_fullsizeUrl hasPrefix:@"/"]) {
        path = _fullsizeUrl;
    }else{
        path = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], _fullsizeUrl];
    }
    
	_fullsize = [[UIImage imageWithContentsOfFile:path] retain];
	
	_hasFullsizeLoaded = YES;
	_isFullsizeLoading = NO;

	[self performSelectorOnMainThread:@selector(didLoadFullsize) withObject:nil waitUntilDone:YES];
	
	[pool release];
}


-(UIImage*) decompressedThumbnailImageUsingData_:(NSData*)data
{
    CGDataProviderRef dataProvider = CGDataProviderCreateWithCFData((CFDataRef)data);
    CGImageRef image = nil;

    image = CGImageCreateWithJPEGDataProvider(dataProvider, NULL, NO, kCGRenderingIntentDefault);
    if(!image) {
        image = CGImageCreateWithPNGDataProvider(dataProvider, NULL, NO, kCGRenderingIntentDefault);
    }
    // use the data provider to get a CGImage; release the data provider
    CGDataProviderRelease(dataProvider);
    
    if(!image) {
        return nil;
    }
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(image);
    if(alphaInfo == kCGImageAlphaFirst || alphaInfo == kCGImageAlphaLast || alphaInfo == kCGImageAlphaOnly || alphaInfo == kCGImageAlphaPremultipliedFirst || alphaInfo == kCGImageAlphaPremultipliedLast) {
        self.sourceHasAlpha = YES;
    }
    
    // make a bitmap context of a suitable size to draw to, forcing decode
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    
    CGSize newSize = CGSizeMake(width, height);
    
    static BOOL retinaChecked = NO;
    static BOOL isRetina = NO;
    if(!retinaChecked) {
        retinaChecked = YES;
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)] && [[UIScreen mainScreen] scale] == 2){
            isRetina = YES;
        }
    }
    
    CGFloat targetBoxSize = isRetina ? 150 : 75;

    if(width > height) {
        newSize = CGSizeMake(targetBoxSize, roundf(newSize.height/newSize.width*targetBoxSize));
    }else{
        newSize = CGSizeMake(roundf(newSize.width/newSize.height*targetBoxSize), targetBoxSize);
    }
    
    width = newSize.width;
    height = newSize.height;
    
    unsigned char *imageBuffer = (unsigned char *)malloc(width*height*4);
    
    CGColorSpaceRef colourSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef imageContext =
    CGBitmapContextCreate(imageBuffer, width, height, 8, width*4, colourSpace,
                          kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    
    CGColorSpaceRelease(colourSpace);
    
    // draw the image to the context, release it
    CGContextSetInterpolationQuality(imageContext,kCGInterpolationHigh);
    CGContextDrawImage(imageContext, CGRectMake(0, 0, width, height), image);
    CGImageRelease(image);
    
    // now get an image ref from the context
    CGImageRef outputImage = CGBitmapContextCreateImage(imageContext);
    
    UIImage *ret = [UIImage imageWithCGImage:outputImage];
    
    // clean up
    CGImageRelease(outputImage);
    CGContextRelease(imageContext);
    free(imageBuffer);
    
    return ret;
}

- (void)loadThumbnailInThread
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
    NSString *path = nil;
    if([_thumbUrl hasPrefix:@"/"]) {
        path = _thumbUrl;
    }else{
        path = [NSString stringWithFormat:@"%@/%@", [[NSBundle mainBundle] bundlePath], _thumbUrl];
    }
    
    UIImage *decompressedImage = nil;
    
    if(self.renderThumbnailInThread) {
        decompressedImage = [self decompressedThumbnailImageUsingData_:[NSData dataWithContentsOfFile:path]];
    }
    
    if(decompressedImage) {
        _thumbnail = [decompressedImage retain];
    }else{
        _thumbnail = [[UIImage imageWithContentsOfFile:path] retain];
        CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(_thumbnail.CGImage);
        if(alphaInfo == kCGImageAlphaFirst || alphaInfo == kCGImageAlphaLast || alphaInfo == kCGImageAlphaOnly || alphaInfo == kCGImageAlphaPremultipliedFirst || alphaInfo == kCGImageAlphaPremultipliedLast) {
            self.sourceHasAlpha = YES;
        }
    }
	
	_hasThumbLoaded = YES;
	_isThumbLoading = NO;
	
	[self performSelectorOnMainThread:@selector(didLoadThumbnail) withObject:nil waitUntilDone:YES];
	
	[pool release];
}


- (void)unloadFullsize
{
	[_fullsizeConnection cancel];
	[self killFullsizeLoadObjects];
	
	_isFullsizeLoading = NO;
	_hasFullsizeLoaded = NO;
	
	[_fullsize release];
	_fullsize = nil;
}

- (void)unloadThumbnail
{
	[_thumbConnection cancel];
	[self killThumbnailLoadObjects];
	
	_isThumbLoading = NO;
	_hasThumbLoaded = NO;
	
	[_thumbnail release];
	_thumbnail = nil;
}


#pragma mark -
#pragma mark NSURLConnection Delegate Methods


- (void)connection:(NSURLConnection *)conn didReceiveResponse:(NSURLResponse *)response {
	
	if( conn == _thumbConnection )
		[_thumbData setLength:0];
	
    else if( conn == _fullsizeConnection )
		[_fullsizeData setLength:0];
	
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
}



- (void)connection:(NSURLConnection *)conn didReceiveData:(NSData *)data 
{
	if( conn == _thumbConnection )
		[_thumbData appendData:data];
	
    else if( conn == _fullsizeConnection )
		[_fullsizeData appendData:data];
	
	[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
}



- (void)connectionDidFinishLoading:(NSURLConnection *)conn 
{	
	if( conn == _thumbConnection )
	{
		_isThumbLoading = NO;
		_hasThumbLoaded = YES;
		
		// create new image with data
		_thumbnail = [[UIImage alloc] initWithData:_thumbData];
		
		// cleanup 
		[self killThumbnailLoadObjects];
		
		// notify delegate
		if( _delegate ) 
			[self didLoadThumbnail];
	}
    else if( conn == _fullsizeConnection )
	{
		_isFullsizeLoading = NO;
		_hasFullsizeLoaded = YES;
		
		// create new image with data
		_fullsize = [[UIImage alloc] initWithData:_fullsizeData];
		
		// cleanup 
		[self killFullsizeLoadObjects];
		
		// notify delegate
		if( _delegate )
			[self didLoadFullsize];
	}
	
	// turn off data indicator
	if( !_isFullsizeLoading && !_isThumbLoading ) 
		[[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
}

#pragma mark -
#pragma mark Delegate Notification Methods


- (void)willLoadThumbFromUrl
{
	if([_delegate respondsToSelector:@selector(galleryPhoto:willLoadThumbnailFromUrl:)])
		[_delegate galleryPhoto:self willLoadThumbnailFromUrl:_thumbUrl];
}


- (void)willLoadFullsizeFromUrl
{
	if([_delegate respondsToSelector:@selector(galleryPhoto:willLoadFullsizeFromUrl:)])
		[_delegate galleryPhoto:self willLoadFullsizeFromUrl:_fullsizeUrl];
}


- (void)willLoadThumbFromPath
{
	if([_delegate respondsToSelector:@selector(galleryPhoto:willLoadThumbnailFromPath:)])
		[_delegate galleryPhoto:self willLoadThumbnailFromPath:_thumbUrl];
}


- (void)willLoadFullsizeFromPath
{
	if([_delegate respondsToSelector:@selector(galleryPhoto:willLoadFullsizeFromPath:)])
		[_delegate galleryPhoto:self willLoadFullsizeFromPath:_fullsizeUrl];
}


- (void)didLoadThumbnail
{
//	FLog(@"gallery phooto did load thumbnail!");
	if([_delegate respondsToSelector:@selector(galleryPhoto:didLoadThumbnail:)])
		[_delegate galleryPhoto:self didLoadThumbnail:_thumbnail];
}


- (void)didLoadFullsize
{
//	FLog(@"gallery phooto did load fullsize!");
	if([_delegate respondsToSelector:@selector(galleryPhoto:didLoadFullsize:)])
		[_delegate galleryPhoto:self didLoadFullsize:_fullsize];
}


#pragma mark -
#pragma mark Memory Management


- (void)killThumbnailLoadObjects
{
	
	[_thumbConnection release];
	[_thumbData release];
	_thumbConnection = nil;
	_thumbData = nil;
}



- (void)killFullsizeLoadObjects
{
	
	[_fullsizeConnection release];
	[_fullsizeData release];
	_fullsizeConnection = nil;
	_fullsizeData = nil;
}



- (void)dealloc
{
//	NSLog(@"FGalleryPhoto dealloc");
	
//	[_delegate release];
	_delegate = nil;
	
	[_fullsizeConnection cancel];
	[_thumbConnection cancel];
	[self killFullsizeLoadObjects];
	[self killThumbnailLoadObjects];
	
	[_thumbUrl release];
	_thumbUrl = nil;
	
	[_fullsizeUrl release];
	_fullsizeUrl = nil;
	
	[_thumbnail release];
	_thumbnail = nil;
	
	[_fullsize release];
	_fullsize = nil;
	
	[super dealloc];
}


@end
