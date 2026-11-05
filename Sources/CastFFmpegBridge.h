#ifndef CAST_FFMPEG_BRIDGE_H
#define CAST_FFMPEG_BRIDGE_H
#include <stdint.h>
#include "StremioZlib.h"
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
int64_t ffmpeg_kit_session_get_session_id(void *session);
// Statistics handles returned by *_at own a reference and must be released.
// Both time getters return milliseconds in pinned v0.11.2-ios.
int64_t ffmpeg_kit_session_get_statistics_count(void *session);
void *ffmpeg_kit_session_get_statistics_at(void *session, int64_t index);
int64_t ffmpeg_kit_statistics_get_video_frame_number(void *statistics);
double ffmpeg_kit_statistics_get_video_fps(void *statistics);
int64_t ffmpeg_kit_statistics_get_size(void *statistics);
double ffmpeg_kit_statistics_get_time(void *statistics);
double ffmpeg_kit_statistics_get_time_elapsed(void *statistics);
double ffmpeg_kit_statistics_get_speed(void *statistics);
int64_t ffmpeg_kit_statistics_get_dup_frames(void *statistics);
int64_t ffmpeg_kit_statistics_get_drop_frames(void *statistics);
void *media_information_create_session_from_argv(int argc, const char **argv);
void media_information_session_execute_async(void *session, int64_t timeout);
void *media_information_session_get_media_information(void *session);
char *media_information_get_all_properties_json(void *information);
void ffprobe_kit_cancel_session(int64_t session_id);
// Public C API, pinned v0.11.2-ios; returned string uses ffmpeg_kit_free.
char *ffmpeg_kit_packages_get_registered_encoders(void);
#endif
