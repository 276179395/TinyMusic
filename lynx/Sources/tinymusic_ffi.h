#ifndef TINYMUSIC_FFI_H
#define TINYMUSIC_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 启动本地后端，返回 JSON 字符串：
///   {"baseUrl":"http://127.0.0.1:PORT","token":"..."}  或  {"error":"..."}
/// 返回的指针必须用 tm_free 释放。
char *tm_start(const char *config_json);

/// 停止后端（进程退出前调用即可）
void tm_stop(void);

/// 释放 tm_start 返回的字符串
void tm_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* TINYMUSIC_FFI_H */
