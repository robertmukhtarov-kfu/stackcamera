#include <metal_stdlib>
using namespace metal;

constant uint UINT16_MAX = 65535;


kernel void fillWithZeros(texture2d<float, access::write> texture [[texture(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    texture.write(0, gid);
}


kernel void textureUInt16ToFloat(texture2d<uint, access::read> inTexture [[texture(0)]],
                                 texture2d<float, access::write> outTexture [[texture(1)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    uint4 uintValue = inTexture.read(gid);
    float4 floatValue = float4(uintValue) / UINT16_MAX;
    outTexture.write(floatValue, gid);
}


kernel void sumTextures(texture2d<float, access::read> texture1 [[texture(0)]],
                        texture2d<float, access::read_write> texture2 [[texture(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
    float4 outColor = texture1.read(gid) + texture2.read(gid);
    texture2.write(outColor, gid);
}


kernel void sumTexturesWeighted(texture2d<float, access::read> texture1 [[texture(0)]],
                                texture2d<float, access::read> texture2 [[texture(1)]],
                                texture2d<float, access::read> weightTexture [[texture(2)]],
                                texture2d<float, access::write> outTexture [[texture(3)]],
                                uint2 gid [[thread_position_in_grid]]) {
    float intensity1 = texture1.read(gid).r;
    float intensity2 = texture2.read(gid).r;
    float weight = weightTexture.read(gid).r;
    float outIntensity = weight * intensity2 + (1 - weight) * intensity1;
    outTexture.write(outIntensity, gid);
}


kernel void upsampleTextureNearest(texture2d<int, access::read> inTexture [[texture(0)]],
                                   texture2d<int, access::write> outTexture [[texture(1)]],
                                   constant float& scaleX [[buffer(0)]],
                                   constant float& scaleY [[buffer(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    
    int x = int(round(float(gid.x) / scaleX));
    int y = int(round(float(gid.y) / scaleY));
    int4 outColor = inTexture.read(uint2(x, y));
    outTexture.write(outColor, gid);
}


kernel void upsampleTextureBilinear(texture2d<float, access::read> inTexture [[texture(0)]],
                                    texture2d<float, access::write> outTexture [[texture(1)]],
                                    constant float& scaleX [[buffer(0)]],
                                    constant float& scaleY [[buffer(1)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    float x = float(gid.x) / scaleX;
    float y = float(gid.y) / scaleY;
    float epsilon = 1e-5;
    
    float4 i1, i2;
    if (abs(x - round(x)) < epsilon) {
        i1 = float4(inTexture.read(uint2(round(x), floor(y))));
        i2 = float4(inTexture.read(uint2(round(x), ceil(y) )));
    } else {
        float4 i11 = float4(inTexture.read(uint2(floor(x), floor(y))));
        float4 i12 = float4(inTexture.read(uint2(floor(x), ceil(y) )));
        float4 i21 = float4(inTexture.read(uint2(ceil(x),  floor(y))));
        float4 i22 = float4(inTexture.read(uint2(ceil(x),  ceil(y) )));
        i1 = (ceil(x) - x) * i11 + (x - floor(x)) * i21;
        i2 = (ceil(x) - x) * i12 + (x - floor(x)) * i22;
    }
    
    float4 i;
    if (abs(y - round(y)) < epsilon) {
        i = i1;
    } else {
        i = (ceil(y) - y) * i1 + (y - floor(y)) * i2;
    }
    
    outTexture.write(i, gid);
}


kernel void averagePool(texture2d<float, access::read> inTexture [[texture(0)]],
                        texture2d<float, access::write> outTexture [[texture(1)]],
                        constant int& scale [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    float outPixel = 0;
    int x0 = gid.x * scale;
    int y0 = gid.y * scale;
    for (int dx = 0; dx < scale; dx++) {
        for (int dy = 0; dy < scale; dy++) {
            int x = x0 + dx;
            int y = y0 + dy;
            outPixel += inTexture.read(uint2(x, y)).r;
        }
    }
    outPixel /= (scale*scale);
    outTexture.write(outPixel, gid);
}


kernel void calculateMergedAverage(texture2d<float, access::read> inTexture [[texture(0)]],
                                   texture2d<uint, access::write> outTexture [[texture(1)]],
                                   constant int& divisor [[buffer(0)]],
                                   uint2 gid [[thread_position_in_grid]]) {
    float inColor = inTexture.read(gid).r;
    uint out = int(round(inColor * UINT16_MAX / divisor));
    outTexture.write(out, gid);
}


kernel void calculateTileDifferences(texture2d<float, access::read> referenceTexture [[texture(0)]],
                                     texture2d<float, access::read> alternateTexture [[texture(1)]],
                                     texture2d<int, access::read> previousAlignment [[texture(2)]],
                                     texture3d<float, access::write> tileDifferences [[texture(3)]],
                                     constant int& downscaleFactor [[buffer(0)]],
                                     constant int& tileSize [[buffer(1)]],
                                     constant int& searchDist [[buffer(2)]],
                                     constant int& nTilesX [[buffer(3)]],
                                     constant int& nTilesY [[buffer(4)]],
                                     uint3 gid [[thread_position_in_grid]]) {
    
    int textureWidth = referenceTexture.get_width();
    int textureHeight = referenceTexture.get_height();
    int tileHalfSize = tileSize / 2;
    int nPos1D = 2*searchDist + 1;
    
    int x0 = int(floor(tileHalfSize + float(gid.x)/float(nTilesX-1) * (textureWidth  - tileSize - 1)));
    int y0 = int(floor(tileHalfSize + float(gid.y)/float(nTilesY-1) * (textureHeight - tileSize - 1)));
    
    int dy0 = gid.z / nPos1D - searchDist;
    int dx0 = gid.z % nPos1D - searchDist;
    
    int4 prevAlignment = previousAlignment.read(uint2(gid.x, gid.y));
    dx0 += downscaleFactor * prevAlignment.x;
    dy0 += downscaleFactor * prevAlignment.y;
    
    float diff = 0;
    for (int dx1 = -tileHalfSize; dx1 < tileHalfSize; dx1++){
        for (int dy1 = -tileHalfSize; dy1 < tileHalfSize; dy1++){
            int refTileX = x0 + dx1;
            int refTileY = y0 + dy1;
            int altTileX = x0 + dx0 + dx1;
            int altTileY = y0 + dy0 + dy1;
            if ((altTileX < 0) || (altTileY < 0) || (altTileX >= textureWidth) || (altTileY >= textureHeight)) {
                diff += 2;
            } else {
                diff += abs(referenceTexture.read(uint2(refTileX, refTileY)).r - alternateTexture.read(uint2(altTileX, altTileY)).r);
            }
        }
    }
    
    tileDifferences.write(diff, gid);
}


kernel void calculateTileAlignments(texture3d<float, access::read> tileDifferences [[texture(0)]],
                                    texture2d<int, access::read> previousAlignment [[texture(1)]],
                                    texture2d<int, access::write> currentAlignment [[texture(2)]],
                                    constant int& downscaleFactor [[buffer(0)]],
                                    constant int& searchDist [[buffer(1)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    int nPos1D = 2 * searchDist + 1;
    int nPos2D = nPos1D * nPos1D;
    
    float currentDiff;
    float minDiffValue = tileDifferences.read(uint3(gid.x, gid.y, 0)).r;
    int minDiffIndex = 0;
    for (int i = 0; i < nPos2D; i++) {
        currentDiff = tileDifferences.read(uint3(gid.x, gid.y, i)).r;
        if (currentDiff < minDiffValue) {
            minDiffValue = currentDiff;
            minDiffIndex = i;
        }
    }
    
    int dy = minDiffIndex / nPos1D - searchDist;
    int dx = minDiffIndex % nPos1D - searchDist;
    
    int4 prevAlign = previousAlignment.read(gid);
    dx += downscaleFactor * prevAlign.x;
    dy += downscaleFactor * prevAlign.y;
    
    int4 out = int4(dx, dy, 0, 0);
    currentAlignment.write(out, gid);
}


kernel void shiftTiles(texture2d<float, access::read> inTexture [[texture(0)]],
                       texture2d<float, access::read_write> outTexture [[texture(1)]],
                       texture2d<int, access::read> previousAlignment [[texture(2)]],
                       constant int& downscaleFactor [[buffer(0)]],
                       constant int& tileSize [[buffer(1)]],
                       constant int& nTilesX [[buffer(2)]],
                       constant int& nTilesY [[buffer(3)]],
                       uint2 gid [[thread_position_in_grid]]) {
    
    int textureWidth = inTexture.get_width();
    int textureHeight = inTexture.get_height();
    int tileHalfSize = tileSize / 2;
    
    int x1Pixel = gid.x;
    int y1Pixel = gid.y;
    
    float x1Grid = float(x1Pixel - tileHalfSize) / float(textureWidth  - tileSize - 1) * (nTilesX - 1);
    float y1Grid = float(y1Pixel - tileHalfSize) / float(textureHeight - tileSize - 1) * (nTilesY - 1);
    
    int xGridArr[] = {int(floor(x1Grid)), int(floor(x1Grid)), int(ceil (x1Grid)), int(ceil(x1Grid))};
    int yGridArr[] = {int(floor(y1Grid)), int(ceil (y1Grid)), int(floor(y1Grid)), int(ceil(y1Grid))};
    
    float totalIntensity = 0;
    float totalWeight = 0;
    for (int i = 0; i < 4; i++){
        
        int xGrid = xGridArr[i];
        int yGrid = yGridArr[i];
        
        int x0Pix = int(floor( tileHalfSize + float(xGrid)/float(nTilesX-1) * (textureWidth  - tileSize - 1) ));
        int y0Pix = int(floor( tileHalfSize + float(yGrid)/float(nTilesY-1) * (textureHeight - tileSize - 1) ));
        
        if ((abs(x1Pixel - x0Pix) <= tileHalfSize) && (abs(y1Pixel - y0Pix) <= tileHalfSize)) {
            
            int4 prevAlign = previousAlignment.read(uint2(xGrid, yGrid));
            int dx = downscaleFactor * prevAlign.x;
            int dy = downscaleFactor * prevAlign.y;
            
            int x2Pix = x1Pixel + dx;
            int y2Pix = y1Pixel + dy;
            
            int distX = abs(x1Pixel - x0Pix);
            int distY = abs(y1Pixel - y0Pix);
            float weightX = tileSize - distX - distY;
            float weightY = tileSize - distX - distY;
            float currentWeight = weightX * weightY;
            totalWeight += currentWeight;
            
            totalIntensity += currentWeight * inTexture.read(uint2(x2Pix, y2Pix)).r;
        }
    }
    
    float outIntensity = totalIntensity / totalWeight;
    outTexture.write(outIntensity, uint2(x1Pixel, y1Pixel));
}


kernel void blurOverX(texture2d<float, access::read> inTexture [[texture(0)]],
                      texture2d<float, access::write> outTexture [[texture(1)]],
                      constant int& kernelSize [[buffer(0)]],
                      constant int& mosaicPatternSize [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    
    int textureWidth = inTexture.get_width();
    
    float totalIntensity = 0;
    float totalWeight = 0;
    int y = gid.y;
    for (int dx = -kernelSize; dx <= kernelSize; dx++) {
        int x = gid.x + mosaicPatternSize*dx;
        if (0 <= x && x < textureWidth) {
            float weight = kernelSize - dx + 1;
            totalIntensity += weight * inTexture.read(uint2(x, y)).r;
            totalWeight += weight;
        }
    }
    
    float outIntensity = totalIntensity / totalWeight;
    outTexture.write(outIntensity, gid);
}


kernel void blurOverY(texture2d<float, access::read> inTexture [[texture(0)]],
                      texture2d<float, access::write> outTexture [[texture(1)]],
                      constant int& kernelSize [[buffer(0)]],
                      constant int& mosaicPatternWidth [[buffer(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    
    // load args
    int textureHeight = inTexture.get_height();
    
    // compute a sigle output pixel
    float totalIntensity = 0;
    float totalWeight = 0;
    int x = gid.x;
    for (int dy = -kernelSize; dy <= kernelSize; dy++) {
        int y = gid.y + mosaicPatternWidth * dy;
        if (0 <= y && y < textureHeight) {
            float weight = kernelSize - dy + 1;
            totalIntensity += weight * inTexture.read(uint2(x, y)).r;
            totalWeight += weight;
        }
    }
    
    // write output pixel
    float outIntensity = totalIntensity / totalWeight;
    outTexture.write(outIntensity, gid);
}


kernel void averageOverY(texture2d<float, access::read> inTexture [[texture(0)]],
                      texture1d<float, access::write> outTexture [[texture(1)]],
                      uint gid [[thread_position_in_grid]]) {
    uint x = gid;
    int textureHeight = inTexture.get_height();
    float total = 0;
    for (int y = 0; y < textureHeight; y++) {
        total += inTexture.read(uint2(x, y)).r;
    }
    float avg = total / textureHeight;
    outTexture.write(avg, x);
}


kernel void averageOverX(texture1d<float, access::read> inTexture [[texture(0)]],
                      device float *outBuffer [[buffer(0)]],
                      constant int& width [[buffer(1)]],
                      uint gid [[thread_position_in_grid]]) {
    float total = 0;
    for (int x = 0; x < width; x++) {
        total += inTexture.read(uint(x)).r;
    }
    float avg = total / width;
    outBuffer[0] = avg;
}


kernel void colorDifference(texture2d<float, access::read> texture1 [[texture(0)]],
                            texture2d<float, access::read> texture2 [[texture(1)]],
                            texture2d<float, access::write> outTexture [[texture(2)]],
                            constant int& mosaicPatternWidth [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    float totalDiff = 0;
    int x0 = gid.x * mosaicPatternWidth;
    int y0 = gid.y * mosaicPatternWidth;
    for (int dx = 0; dx < mosaicPatternWidth; dx++) {
        for (int dy = 0; dy < mosaicPatternWidth; dy++) {
            int x = x0 + dx;
            int y = y0 + dy;
            float i1 = texture1.read(uint2(x, y)).r;
            float i2 = texture2.read(uint2(x, y)).r;
            totalDiff += abs(i1 - i2);
        }
    }
    outTexture.write(totalDiff, gid);
}


kernel void calculateMergeWeights(texture2d<float, access::read> textureDiff [[texture(0)]],
                                  texture2d<float, access::write> weightTexture [[texture(1)]],
                                  constant float* noiseSDBuffer [[buffer(0)]],
                                  constant float& robustness [[buffer(1)]],
                                  uint2 gid [[thread_position_in_grid]]) {
    
    float noiseSD = noiseSDBuffer[0];
    float diff = textureDiff.read(gid).r;
    float weight;
    if (robustness == 0) {
        weight = 1;
    } else {
        float maxDiff = noiseSD / robustness;
        weight =  1 - diff / maxDiff;
        weight = clamp(weight, 0.0, 1.0);
    }
    weightTexture.write(weight, gid);
}
