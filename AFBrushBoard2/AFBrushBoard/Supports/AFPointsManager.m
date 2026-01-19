//
//  BezierTool.m
//  AFBrushBoard2
//
//  Created by 初毅 on 2018/5/17.
//  Copyright © 2018年 初毅. All rights reserved.
//

#import "AFPointsManager.h"

// Constants for point smoothing and curve generation
#define kSmoothingDistance      0.3     // Minimum distance between smoothed points
#define kBezierSegmentLength    5       // Target length for bezier curve segments
#define kMinimumPointDistance   4       // Minimum distance to register a new point
#define kMaxSmoothingIterations 10000   // Safety limit for smoothing loop
#define kTargetDistanceThreshold 0.01   // Distance threshold to stop smoothing

@implementation AFPoint

@end

@interface AFPointsManager ()
@property CGPoint point1;
@property CGPoint point2;
@property CGPoint point3;
@property int pointCount;

@property CGFloat currentSize;
@property CGFloat aimSize;
@property CGPoint smoothPoint;
@end

@implementation AFPointsManager

- (instancetype)init{
    if (self = [super init]) {
        self.step = 1;
        self.maxSize = 40;
        self.minSize = 20;
        self.maxSpeed = 30;
        self.minSpeed = 2;
        self.sizeSpeed = (self.maxSize - self.minSize)/200;
    }
    return self;
}


- (void)startWithPoint:(CGPoint)point{
    self.pointCount = 1;
    self.currentSize = self.maxSize;
    self.smoothPoint = CGPointZero;
    
    self.point3 = point;
}
- (NSArray *)appendPoint:(CGPoint)point{
    CGFloat distance = pointDistance(self.point3, point);
    if (distance < kMinimumPointDistance) {
        return nil;
    }
    self.pointCount++;
    CGFloat percent = MAX(MIN(1-(distance-self.minSpeed)/(self.maxSpeed-self.minSpeed),1),0);
    self.aimSize = (self.minSize+(self.maxSize-self.minSize)*percent + self.currentSize)/2;
    
    self.point1 = self.point2;
    self.point2 = self.point3;
    self.point3 = point;
    if (self.pointCount == 2) {
        NSArray *arr = [self makeLiner:self.point2 p2:pointCenter(self.point2, self.point3)];//线性2-2.5
        return [self smoothPoints:arr];
    }else{
        NSArray *arr = [self makeBezier:pointCenter(self.point1, self.point2)
                             p2:pointCenter(self.point2, self.point3)
                             cp:self.point2];//贝塞尔曲线1.5-[2]-2.5
        return [self smoothPoints:arr];
    }
    
}
- (NSArray *)finishWithPoint:(CGPoint)point{
    // Currently not rendering additional points on touch end
    // to avoid drawing artifacts when user lifts finger
    return nil;
}


- (NSArray *)makeLiner:(CGPoint)p1 p2:(CGPoint)p2{
    return @[[NSValue valueWithCGPoint:p1],[NSValue valueWithCGPoint:p2]];
}

- (NSArray *)makeBezier:(CGPoint)startP p2:(CGPoint)endP cp:(CGPoint)controlP{
    CGFloat dis = pointDistance(startP, endP);
    int segements = MAX((int)(dis / kBezierSegmentLength), 2) * 2;
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:segements];

    // Optimize quadratic Bezier curve calculation by avoiding pow() calls
    // Formula: B(t) = (1-t)^2 * P0 + 2*(1-t)*t * P1 + t^2 * P2
    CGFloat invSegments = 1.0 / segements;

    for (int i = 0; i <= segements; i++) {
        CGFloat t = i * invSegments;
        CGFloat oneMinusT = 1.0 - t;

        // Calculate basis functions
        CGFloat b0 = oneMinusT * oneMinusT;  // (1-t)^2
        CGFloat b1 = 2.0 * oneMinusT * t;    // 2*(1-t)*t
        CGFloat b2 = t * t;                  // t^2

        // Calculate point coordinates
        CGFloat x = b0 * startP.x + b1 * controlP.x + b2 * endP.x;
        CGFloat y = b0 * startP.y + b1 * controlP.y + b2 * endP.y;

        [array addObject:[NSValue valueWithCGPoint:CGPointMake(x, y)]];
    }
    return array;
}


- (NSArray *)smoothPoints:(NSArray *)points{
    if (points.count == 0) {
        return nil;
    }
    if (CGPointEqualToPoint(self.smoothPoint, CGPointZero)) {
        self.smoothPoint = [points[0] CGPointValue];
    }
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:points.count];
    for (int i = 0; i<points.count; i++) {
        CGPoint p = [points[i] CGPointValue];
        CGFloat d = pointDistance(p, self.smoothPoint);
        if (d < kSmoothingDistance) {
            continue;
        }
        CGFloat kx = (p.x-self.smoothPoint.x)/d;
        CGFloat ky = (p.y-self.smoothPoint.y)/d;

        // Calculate the number of steps needed to reach the target point
        // This avoids potential infinite loops and is more efficient
        int maxSteps = (int)ceil(d / 1.0); // 1.0 is the step size (kx, ky are unit vectors)

        // Safety limit: prevent excessive iterations
        if (maxSteps > kMaxSmoothingIterations) {
            maxSteps = kMaxSmoothingIterations;
        }

        for (int step = 0; step < maxSteps; step++) {
            CGPoint newp = CGPointMake(self.smoothPoint.x+kx, self.smoothPoint.y+ky);

            // Check if we've reached or passed the target point
            if ((kx>0 && newp.x>p.x) || (kx<0 && newp.x<p.x)) {
                break;
            }
            if ((ky>0 && newp.y>p.y) || (ky<0 && newp.y<p.y)) {
                break;
            }

            // Additional safety check: if step size is too small, break to avoid getting stuck
            CGFloat distanceToTarget = pointDistance(newp, p);
            if (distanceToTarget < kTargetDistanceThreshold) {
                break;
            }

            self.smoothPoint = newp;

            AFPoint *afp = [AFPoint new];
            if (self.currentSize < self.aimSize) {
                self.currentSize+=self.sizeSpeed;
            }else{
                self.currentSize-=self.sizeSpeed;
            }
            afp.size = self.currentSize;
            afp.point = newp;
            [arr addObject:afp];
        }
    }
    return arr;

}

CGPoint pointCenter(CGPoint p1, CGPoint p2){
    return CGPointMake((p1.x+p2.x)*0.5, (p1.y+p2.y)*0.5);
}

CGFloat pointDistance(CGPoint p1, CGPoint p2){
    return sqrtf((p1.x-p2.x)*(p1.x-p2.x)+(p1.y-p2.y)*(p1.y-p2.y));
}

@end
