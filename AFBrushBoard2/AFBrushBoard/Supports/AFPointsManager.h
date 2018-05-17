//
//  BezierTool.h
//  AFBrushBoard2
//
//  Created by 初毅 on 2018/5/17.
//  Copyright © 2018年 初毅. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AFPoint : NSObject
@property CGPoint point;
@property CGFloat size;
@end

@interface AFPointsManager : NSObject
@property CGFloat step;
@property CGFloat maxSize;
@property CGFloat sizeSpeed;
@property CGFloat minSize;
@property CGFloat maxSpeed;
@property CGFloat minSpeed;

- (void)startWithPoint:(CGPoint)point;
- (NSArray *)appendPoint:(CGPoint)point;
- (NSArray *)finishWithPoint:(CGPoint)point;
@end
