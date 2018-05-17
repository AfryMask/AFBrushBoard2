//
//  BezierTool.h
//  AFBrushBoard2
//
//  Created by 初毅 on 2018/5/17.
//  Copyright © 2018年 初毅. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface AFPointsManager : NSObject


- (void)startWithPoint:(CGPoint)point;
- (NSArray *)appendPoint:(CGPoint)point;
- (NSArray *)finishWithPoint:(CGPoint)point;
@end
