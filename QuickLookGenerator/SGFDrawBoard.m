//
//  SGFDrawBoard.m
//  SGFTools
//
//  Created by John Mifsud on 1/15/10.
//  This class implements a class that draws a go board.
//
// The MIT License
//
// Copyright (c) 2010 SGF Tools Developers
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "SGFDrawBoard.h"

#define DEFAULT_BOUNDS NSMakeRect(0.0, 0.0, 128.0, 128.0)
#define BOARD_WIDTH (locationWidth*size)
#define HOSHI_WIDTH 3.0

@interface SGFDrawBoard ()  // for private funcs
- (void) drawHoshiAtX:(unsigned)x Y:(unsigned)y;
- (void) drawFlatStoneAtPoint:(NSPoint)point color:(NSColor*)color;
- (void) drawShadedStoneAtPoint:(NSPoint)point color:(NSColor*)color;

- (void) createShadedStoneShadow:(NSShadow**) ptheShadow 
                        noShadow:(NSShadow**) pnoShadow;

- (void) createShadedStoneGradient:(NSGradient**) pstoneGradient forColor:(NSColor*)color;

- (void) drawShadedStoneAtPoint:(NSPoint)point
                         Shadow:(NSShadow*) theShadow 
                       noShadow:(NSShadow*) noShadow
                       gradient:(NSGradient*) stoneGradient 
                          color:(NSColor*)color;
@end


@implementation SGFDrawBoard

@synthesize flatStyle, cfBundle;


- (unsigned) size {
    return size;
}

- (void) setSize:(unsigned)newSize {
    if ((newSize > 0) && (newSize <= MAX_BOARD_SIZE)) {
        size = newSize;
        locationWidth = bounds.size.height / (CGFloat)size;
    }
}


- (id)initWithBoardSize:(unsigned)newSize {
    if ((self = [super init]))
    {
        self.size = newSize;
        [self setBounds:DEFAULT_BOUNDS];
    }
    return self;
}


- (void) setBounds:(NSRect)newBounds {
    bounds = newBounds;
    locationWidth = bounds.size.height / (CGFloat)size;
}



- (void) drawPosition:(NSString*)position {
    unsigned boardSize;
    NSString *blackStones, *whiteStones;
    if (![SGFGoban getSize:&boardSize blackStones:&blackStones whiteStones:&whiteStones ofPosition:position]) {
        return;
    }
    self.size = boardSize;
    
    [self drawBoardColor:DEFAULT_BOARD_NSCOLOR];
    [self drawGrid];
        
    if (flatStyle) {
        for (unsigned loc=0; loc < [blackStones length]; loc += 2) {
            [self drawFlatStoneAtPoint:[self getPointForLocation:[blackStones substringWithRange:NSMakeRange(loc,2)]]
                                 color:[NSColor blackColor]];
        }
        
        for (unsigned loc=0; loc < [whiteStones length]; loc += 2) {
            [self drawFlatStoneAtPoint:[self getPointForLocation:[whiteStones substringWithRange:NSMakeRange(loc,2)]]
                                 color:[NSColor whiteColor]];
        }
    } else {
        NSShadow *theShadow, *noShadow;
        NSGradient *stoneGradient;
        [self createShadedStoneShadow:&theShadow noShadow:&noShadow];
        [self createShadedStoneGradient:&stoneGradient forColor:[NSColor blackColor]];
        
        for (unsigned loc=0; loc < [blackStones length]; loc += 2) {
            [self drawShadedStoneAtPoint:[self getPointForLocation:[blackStones substringWithRange:NSMakeRange(loc,2)]] 
                                  Shadow:theShadow noShadow:noShadow gradient:stoneGradient color:[NSColor blackColor]];
        }
        
        [stoneGradient release];
        [self createShadedStoneGradient:&stoneGradient forColor:DEFAULT_WHITE_NON_FLAT_STONE_NSCOLOR];
        
        for (unsigned loc=0; loc < [whiteStones length]; loc += 2) {
            [self drawShadedStoneAtPoint:[self getPointForLocation:[whiteStones substringWithRange:NSMakeRange(loc,2)]] 
                                  Shadow:theShadow noShadow:noShadow gradient:stoneGradient 
                                   color:DEFAULT_WHITE_NON_FLAT_STONE_NSCOLOR];
        }
        
        [theShadow release];
        [noShadow release];
        [stoneGradient release];
    }
}


- (void) drawFlatStoneAtPoint:(NSPoint)point color:(NSColor*)color {
    NSRect srect;
    srect.origin.x = point.x+0.25;
    srect.origin.y = point.y+0.25;
    srect.size.width = locationWidth-0.5;
    srect.size.height = srect.size.width;
    
    [color setFill];
    [[NSBezierPath bezierPathWithOvalInRect:srect] fill];
}


- (void) createShadedStoneShadow:(NSShadow**) ptheShadow 
                        noShadow:(NSShadow**) pnoShadow {
    *ptheShadow = [[NSShadow alloc] init];
    *pnoShadow = [[NSShadow alloc] init];
    if (locationWidth > 10.0) {
        [*ptheShadow setShadowOffset:NSMakeSize(2.0, -2.0)];
        [*ptheShadow setShadowBlurRadius:3.0];
    } else {
        [*ptheShadow setShadowOffset:NSMakeSize(1.0, -1.0)];
        [*ptheShadow setShadowBlurRadius:1.0];
    }
    
    [*ptheShadow setShadowColor:[[NSColor blackColor] colorWithAlphaComponent:0.4]];
}

- (void) createShadedStoneGradient:(NSGradient**) pstoneGradient forColor:(NSColor*)color {
    if (color != [NSColor blackColor]) {
        *pstoneGradient = [[NSGradient alloc] initWithStartingColor:[NSColor whiteColor]  
                                                        endingColor:[color blendedColorWithFraction:0.03 ofColor:[NSColor whiteColor]]];
    } else {
        *pstoneGradient = [[NSGradient alloc] initWithStartingColor:[color blendedColorWithFraction:0.3 ofColor:[NSColor whiteColor]]
                                                        endingColor:[color blendedColorWithFraction:0.03 ofColor:[NSColor whiteColor]]];
    }
}

- (void) drawShadedStoneAtPoint:(NSPoint)point
                         Shadow:(NSShadow*) theShadow 
                       noShadow:(NSShadow*) noShadow
                       gradient:(NSGradient*) stoneGradient 
                       color:(NSColor*)color {
    NSRect srect;
    srect.origin.x = point.x+0.25;
    srect.origin.y = point.y+0.25;
    srect.size.width = locationWidth-0.5;
    srect.size.height = srect.size.width;
    
    [theShadow set];
    [color setFill];
    [[NSBezierPath bezierPathWithOvalInRect:srect] fill];
    [noShadow set];
    
    CGFloat gradRadius = srect.size.width/2.5;
    NSPoint centerPoint = NSMakePoint(NSMidX(srect) - (gradRadius/6.0), NSMidY(srect) - (gradRadius/6.0));
    NSPoint highlightPoint = NSMakePoint(centerPoint.x - (gradRadius/4.5), centerPoint.y - (gradRadius/3.8));
    [stoneGradient drawFromCenter:highlightPoint radius:0.0
                         toCenter:centerPoint radius:gradRadius
                          options:0];
}    

- (void) drawShadedStoneAtPoint:(NSPoint)point color:(NSColor*)color {
    NSShadow *theShadow, *noShadow;
    NSGradient *stoneGradient;
    [self createShadedStoneShadow:&theShadow noShadow:&noShadow];
    [self createShadedStoneGradient:&stoneGradient forColor:color];
    [self drawShadedStoneAtPoint:point Shadow:theShadow noShadow:noShadow gradient:stoneGradient color:color];
    [theShadow release];
    [noShadow release];
    [stoneGradient release];
}


- (void) drawStoneAtLocation:(NSString*)location color:(NSColor*)color {
    [self drawStoneAtPoint:[self getPointForLocation:location] color:color];
}

- (void) drawStoneAtPoint:(NSPoint)point color:(NSColor*)color {
    if (flatStyle) {
        [self drawFlatStoneAtPoint:point color:color];
    } else {
        [self drawShadedStoneAtPoint:point color:color];
    }
}


- (void) drawBoardColor:(NSColor*)color {
    if (flatStyle) {
        [color setFill];
    } else {
        NSURL *imageUrl = [(NSURL *) CFBundleCopyResourceURL(cfBundle, CFSTR("boardFill.png"), NULL, NULL) autorelease];
        NSImage* img = [[[NSImage alloc] initWithContentsOfURL:imageUrl] autorelease];
        if (img) {
            [[NSColor colorWithPatternImage:img] setFill];
        } else {
            [color setFill];
        }
    }
    
    [NSBezierPath fillRect:NSMakeRect(0.0, 0.0, BOARD_WIDTH, BOARD_WIDTH)];
}


- (void) drawHoshiAtX:(unsigned)x Y:(unsigned)y {
    NSPoint loc = [self getCenterPointForX:x Y:y];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(loc.x - (HOSHI_WIDTH/2), loc.y - (HOSHI_WIDTH/2), 
                                                       HOSHI_WIDTH, HOSHI_WIDTH)] fill]; 
}


- (void) drawGrid {
    if (size < 2) {
        return;
    }
        
    // draw outer box
    NSPoint loc0 = [self getCenterPointForX:0 Y:0];
    NSPoint locMax = [self getCenterPointForX:size-1 Y:size-1];
    
    [[NSColor blackColor] set];
    [NSBezierPath setDefaultLineWidth:1.0];
    [NSBezierPath strokeRect:NSMakeRect(loc0.x, loc0.y, locMax.x-loc0.x, locMax.y-loc0.y)];
    
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    // draw inner lines
    NSBezierPath *gridPath = [NSBezierPath bezierPath];
    [[[NSColor blackColor] colorWithAlphaComponent:0.5] set];
    
    NSPoint loc;
    for (unsigned x=1; x < size-1; x++) {
        loc = [self getCenterPointForX:x Y:0];
        [gridPath moveToPoint:NSMakePoint(loc.x, loc0.y)];
        [gridPath lineToPoint:NSMakePoint(loc.x, locMax.y)];
        
        [gridPath moveToPoint:NSMakePoint(loc0.x, loc.x)];
        [gridPath lineToPoint:NSMakePoint(locMax.x, loc.x)];
    }
    
    [gridPath stroke];
    
    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    // draw hoshi
    if ((size < 3) || (4 == size)) {
        return; // no hoshi points for these board sizes
    }
    
    [[[NSColor blackColor] colorWithAlphaComponent:0.8] set];

    if (3 == size) {
        [self drawHoshiAtX:1 Y:1];
        return;
    } else if (5 == size) {
        [self drawHoshiAtX:1 Y:1];
        [self drawHoshiAtX:1 Y:3];
        [self drawHoshiAtX:2 Y:2];
        [self drawHoshiAtX:3 Y:1];
        [self drawHoshiAtX:3 Y:3];
        return;
    }
  
    // all remaining sizes have corner hoshi
    unsigned corner;
    if (size <= 11) {
        corner = 2;
    } else {
        corner = 3;
    }
    [self drawHoshiAtX:corner Y:corner];
    [self drawHoshiAtX:size-1-corner Y:corner];
    [self drawHoshiAtX:corner Y:size-1-corner];
    [self drawHoshiAtX:size-1-corner Y:size-1-corner];
    
    // no center or side hoshi for even sizes
    if (size%2 == 0) {
        return;
    }
    
    // center hoshi
    unsigned middle = (size / 2);
    [self drawHoshiAtX:middle Y:middle];
    
    if (size < 12) {
        return;  // so side hoshi for these sizes
    }
    
    // all remaining sizes have side hoshi
    [self drawHoshiAtX:middle Y:corner];
    [self drawHoshiAtX:middle Y:size-1-corner];
    [self drawHoshiAtX:corner Y:middle];
    [self drawHoshiAtX:size-1-corner Y:middle];
}


// returns graphics coords for center point of board intersection x,y
- (NSPoint) getCenterPointForX:(unsigned)x Y:(unsigned)y {
    CGFloat cx, cy;
    cx = floor(((CGFloat)x*locationWidth)+(locationWidth/2)) + 0.5f;
    cy = floor(((CGFloat)y*locationWidth)+(locationWidth/2)) + 0.5f;
    
    return NSMakePoint(cx, cy);
}

// returns graphics coords for upper-left point of board intersection x,y
- (NSPoint) getPointForX:(unsigned)x Y:(unsigned)y {
    return NSMakePoint((CGFloat)x*locationWidth, (CGFloat)y*locationWidth);
}

- (NSPoint) getPointForLocation:(NSString*)location {
    return [self getPointForX:[SGFGoban getColOf:location] Y:[SGFGoban getRowOf:location]];
}


@end
