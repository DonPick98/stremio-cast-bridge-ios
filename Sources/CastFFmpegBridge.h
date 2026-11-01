#ifndef CAST_FFMPEG_BRIDGE_H
#define CAST_FFMPEG_BRIDGE_H
#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/filio.h>
static inline int CastFIFOAvailableBytes(int fd) {
    int bytes = 0;
    return ioctl(fd,FIONREAD,&bytes) == 0 ? bytes : -1;
}
// Narrow C ABI from the pinned ffmpegkit_wrapper.h. Avoid importing its
// internal FFmpeg/C++ headers into Swift or the independent VLC framework.
void ffmpeg_kit_initialize(void);
void *ffmpeg_kit_create_session_from_argv(int argc, const char **argv);
void ffmpeg_kit_session_execute_async(void *session);
void ffmpeg_kit_session_cancel(void *session);
int ffmpeg_kit_session_get_state(void *session);
int64_t ffmpeg_kit_session_get_return_code(void *session);
void ffmpeg_kit_handle_release(void *session);
void ffmpeg_kit_set_session_history_size(int64_t size);
void ffmpeg_kit_config_set_log_level(int level);
char *ffmpeg_kit_session_get_output(void *session);
char *session_get_debug_log(void *session);
void session_enable_debug_log(void *session);
void ffmpeg_kit_free(void *pointer);
#endif
