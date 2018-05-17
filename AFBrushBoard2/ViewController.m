//
//  ViewController.m
//  AFBrushBoard2
//
//  Created by 初毅 on 2018/5/17.
//  Copyright © 2018年 初毅. All rights reserved.
//

#import "ViewController.h"
#import "AFBrushBoard2.h"

@interface ViewController ()
@property AFBrushBoard2 *brushBoard;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.brushBoard = [[AFBrushBoard2 alloc]initWithFrame:self.view.bounds];
    [self.view addSubview:self.brushBoard];
    [self.brushBoard setBrushColorWithRed:1 green:0 blue:0];
    
    
    
}

- (void)viewWillAppear:(BOOL)animated{
    NSLog(@"will");
}

- (void)viewDidAppear:(BOOL)animated{
    
}




@end
