#ifndef TINYMUSIC_FFI_H
#define TINYMUSIC_FFI_H

#ifdef __cplusplus
extern "C" {
#endif

/// 启动 S3-only 后端，返回 {"ok":true,"version":"..."}
char *tm_start(const char *config_json);

/// 执行一条命令，返回 {"ok":true,"data":...} 或 {"ok":false,"error":"..."}
char *tm_invoke(const char *cmd, const char *args_json);

/// 停止后端
void tm_stop(void);

/// 释放 tm_start / tm_invoke 返回的字符串
void tm_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
