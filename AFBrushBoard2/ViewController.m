//
//  ViewController.m
//  AFBrushBoard2
//
//  Created by 初毅 on 2018/5/17.
//  Copyright © 2018年 初毅. All rights reserved.
//

#import "ViewController.h"
#import "AFBrushBoard2.h"

// UI Constants
static const CGFloat kClearButtonHeight = 100.0;

@interface ViewController ()
@property AFBrushBoard2 *brushBoard;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.brushBoard = [[AFBrushBoard2 alloc]initWithFrame:self.view.bounds];
    [self.view addSubview:self.brushBoard];
    [self.brushBoard setBrushColorWithRed:1 green:0 blue:0];
    
    
    UIButton *btn = [[UIButton alloc]initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, kClearButtonHeight)];
    [btn addTarget:self.brushBoard action:@selector(erase) forControlEvents:UIControlEventTouchUpInside];
    btn.backgroundColor = [UIColor cyanColor];
    [self.view addSubview:btn];
}

- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
}




@end
