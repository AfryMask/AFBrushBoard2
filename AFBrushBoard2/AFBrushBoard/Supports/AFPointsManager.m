//
//  BezierTool.m
//  AFBrushBoard2
//
//  Created by 初毅 on 2018/5/17.
//  Copyright © 2018年 初毅. All rights reserved.
//

#import "AFPointsManager.h"

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
        self.maxSize = 60;
        self.minSize = 40;
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
    self.pointCount++;
    CGFloat distance = pointDistance(self.point3, point);
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
    self.pointCount++;
    self.point1 = self.point2;
    self.point2 = self.point3;
    self.point3 = point;
    if (self.pointCount == 2) {

        return [self makeLiner:self.point2 p2:self.point3];//线性2-3
    }else{
        NSArray *before = [self makeBezier:pointCenter(self.point1, self.point2)
                                        p2:pointCenter(self.point2, self.point3)
                                        cp:self.point2];
        NSArray *after = [self makeLiner:pointCenter(self.point2, self.point3) p2:self.point3];
        NSMutableArray *arr = [NSMutableArray arrayWithArray:before];
        [arr addObjectsFromArray:after];
        
        
        return [self smoothPoints:arr];//线性2.5-3
    }
//
//    return nil;
//
//    return [self makeLiner:self.point2 p2:self.point3];
}


- (NSArray *)makeLiner:(CGPoint)p1 p2:(CGPoint)p2{
    return @[[NSValue valueWithCGPoint:p1],[NSValue valueWithCGPoint:p2]];
}

- (NSArray *)makeBezier:(CGPoint)startP p2:(CGPoint)endP cp:(CGPoint)controlP{
    CGFloat dis = pointDistance(startP, endP);
    int segements = MAX((int)(dis/5), 2)*2;
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:segements];
    
    for (int i = 0; i<=segements; i++) {
        CGFloat t = i * 1.0 / segements;
        CGFloat x = pow(1-t,2)*startP.x + 2.0*(1-t)*t*controlP.x + t*t*endP.x;
        CGFloat y = pow(1-t,2)*startP.y + 2.0*(1-t)*t*controlP.y + t*t*endP.y;
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
    CGFloat distance = 1;
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:points.count];
    for (int i = 0; i<points.count; i++) {
        CGPoint p = [points[i] CGPointValue];
        CGFloat d = pointDistance(p, self.smoothPoint);
        if (d < distance) {
            continue;
        }
        CGFloat kx = (p.x-self.smoothPoint.x)/d;
        CGFloat ky = (p.y-self.smoothPoint.y)/d;
        while (1) {
            CGPoint newp = CGPointMake(self.smoothPoint.x+kx, self.smoothPoint.y+ky);
            if ((kx>0 && newp.x>p.x) || (kx<0 && newp.x<p.x)) {
                break;
            }
            if ((ky>0 && newp.y>p.y) || (ky<0 && newp.y<p.y)) {
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
