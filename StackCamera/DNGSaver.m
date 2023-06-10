//
//  DNGSaver.m
//  StackCamera
//
//  Created by Robert Mukhtarov on 04.03.2023.
//
//  Useful links:
//  Saving DNG from a bayer matrix: https://lab.apertus.org/T759
//  Libtiff tags: https://gitlab.com/libtiff/libtiff/-/blob/master/libtiff/tif_dirinfo.c
//

#import "DNGSaver.h"
#include "libraw_src/libraw/libraw.h"
#include "libtiff/include/tiffio.h"

@implementation DNGSaver

+ (NSURL *)createDNGfromMTLTexture:(id<MTLTexture>)mtlTexture usingReferenceDNGURL:(NSURL *)referenceDNGURL tiffTagOrientation:(NSInteger)tiffTagOrientation {
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef) referenceDNGURL, NULL);
    NSDictionary *metadata = (NSDictionary *)CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSString *deviceModel = metadata[@"{TIFF}"][@"Model"];
    NSDictionary *dngMetadata = metadata[@"{DNG}"];
    float *colorMatrix1 = cArrayFromNSArrayOfFloats(dngMetadata[@"ColorMatrix1"]);
    float *colorMatrix2 = cArrayFromNSArrayOfFloats(dngMetadata[@"ColorMatrix2"]);
    NSInteger calibrationIlluminant1 = [dngMetadata[@"CalibrationIlluminant1"] intValue];
    NSInteger calibrationIlluminant2 = [dngMetadata[@"CalibrationIlluminant2"] intValue];

    libraw_data_t *rawData = libraw_init(0);
    int msg = libraw_open_file(rawData, [[referenceDNGURL path] UTF8String]);
    if (msg != LIBRAW_SUCCESS) {
        libraw_close(rawData);
        NSLog(@"Couldn't open file. Error: %d", msg);
        return nil;
    }
    msg = libraw_unpack(rawData);
    if (msg != LIBRAW_SUCCESS) {
        libraw_close(rawData);
        NSLog(@"Couldn't unpack raw data. Error: %d", msg);
        return nil;
    }
    float *asShotNeutral = (*rawData).color.dng_levels.asshotneutral;
    float blackLevel = (float) (*rawData).color.black;
    uint32_t whiteLevel = (*rawData).color.maximum;
    char *uniqueCameraModel = (*rawData).color.UniqueCameraModel;
    char *lensMake = (*rawData).lens.LensMake;
    NSInteger width = libraw_get_raw_width(rawData);
    NSInteger height = libraw_get_raw_height(rawData);
    NSInteger bytesPerPixel = 2;
    NSInteger bytesPerRow = bytesPerPixel * width;
    uint16_t cfaPatternDim[] = {2, 2};
    uint8_t cfaPattern[] = {0, 1, 1, 2};  // RGGB
    ushort *bayerMatrix = malloc(width * height * bytesPerPixel);
    MTLRegion mtlRegion = MTLRegionMake2D(0, 0, width, height);
    [mtlTexture getBytes:bayerMatrix bytesPerRow:bytesPerRow fromRegion:mtlRegion mipmapLevel:0];
    
    NSURL *tiffURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"new image.dng"];
    TIFF *tif = TIFFOpen([[tiffURL path] UTF8String], "w");
    if (tif == nil) {
        NSLog(@"Error: tif is nil");
        return nil;
    }

    TIFFSetField(tif, TIFFTAG_SUBFILETYPE, 0);
    TIFFSetField(tif, TIFFTAG_MAKE, lensMake);
    TIFFSetField(tif, TIFFTAG_MODEL, [deviceModel UTF8String]);
    TIFFSetField(tif, TIFFTAG_UNIQUECAMERAMODEL, uniqueCameraModel);
    TIFFSetField(tif, TIFFTAG_ORIENTATION, tiffTagOrientation);
    TIFFSetField(tif, TIFFTAG_SOFTWARE, "Stack Camera 1.0");
    TIFFSetField(tif, TIFFTAG_DNGVERSION, "\01\03\00\00");
    TIFFSetField(tif, TIFFTAG_DNGBACKWARDVERSION, "\01\03\00\00");
    TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, colorMatrix1);
    TIFFSetField(tif, TIFFTAG_COLORMATRIX2, 9, colorMatrix2);
    TIFFSetField(tif, TIFFTAG_ASSHOTNEUTRAL, 3, asShotNeutral);
    TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, calibrationIlluminant1);
    TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT2, calibrationIlluminant2);
    TIFFSetField(tif, TIFFTAG_IMAGEWIDTH, width);
    TIFFSetField(tif, TIFFTAG_IMAGELENGTH, height);
    TIFFSetField(tif, TIFFTAG_BITSPERSAMPLE, bytesPerPixel * 8);
    TIFFSetField(tif, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_CFA);
    TIFFSetField(tif, TIFFTAG_SAMPLESPERPIXEL, 1);
    TIFFSetField(tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
    TIFFSetField(tif, TIFFTAG_CFAREPEATPATTERNDIM, &cfaPatternDim);
    TIFFSetField(tif, TIFFTAG_CFAPATTERN, 4, &cfaPattern);
    TIFFSetField(tif, TIFFTAG_WHITELEVEL, 1, &whiteLevel);
    TIFFSetField(tif, TIFFTAG_BLACKLEVEL, 1, &blackLevel);
    
    for (int row = 0; row < height; row++)
        TIFFWriteScanline(tif, &bayerMatrix[row * width], row, 0);
    
    free(bayerMatrix);
    TIFFClose(tif);
    libraw_free_image(rawData);
    libraw_recycle(rawData);
    libraw_close(rawData);
    
    return tiffURL;
}

float *cArrayFromNSArrayOfFloats(NSArray *array) {
    NSUInteger count = array.count;
    float *cArray = (float *)malloc(count * sizeof(float));
    for (NSUInteger i = 0; i < count; i++) {
        NSNumber *number = array[i];
        cArray[i] = [number floatValue];
    }
    return cArray;
}

@end
