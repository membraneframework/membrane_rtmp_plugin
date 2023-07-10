#pragma once

#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <stdbool.h>
#include <unifex/unifex.h>

typedef struct State State;

struct State {
  AVFormatContext *output_ctx;

  bool audio_present;
  bool video_present;
  bool closed;

  int video_stream_index;
  int64_t current_video_dts;

  int audio_stream_index;
  int64_t current_audio_pts;

  bool header_written;
};

#include "_generated/rtmp_sink.h"
