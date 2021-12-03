#pragma once

#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <stdbool.h>
#include <unifex/unifex.h>

typedef struct State State;

struct State {
  AVFormatContext *output_ctx;
  int video_stream_index;
};

#include "_generated/rtmp_sink.h"