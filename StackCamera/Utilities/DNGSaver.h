//
//  DNGSaver.h
//  StackCamera
//
//  Created by Robert Mukhtarov on 04.03.2023.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

@interface DNGSaver : NSObject

+ (nullable NSURL *)createDNGfromMTLTexture:(nonnull id<MTLTexture>)mtlTexture
                       usingReferenceDNGURL:(nonnull NSURL *)referenceDNGURL
                         tiffTagOrientation:(NSInteger)tiffTagOrientation
NS_SWIFT_NAME(createDNG(fromMTLTexture:usingReferenceURL:tiffTagOrientation:));

@end

