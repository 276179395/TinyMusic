//
// Lynx 是 Objective-C 实现，Swift 侧通过桥接头使用。
//

#import <Lynx/LynxEnv.h>
#import <Lynx/LynxView.h>
#import <Lynx/LynxConfig.h>
#import <Lynx/LynxTemplateProvider.h>
#import <Lynx/LynxModule.h>

// 本进程内的 Rust 后端（crates/ffi）
#import "tinymusic_ffi.h"
