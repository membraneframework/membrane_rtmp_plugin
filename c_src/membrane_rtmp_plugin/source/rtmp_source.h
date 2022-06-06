#pragma once

#include <libavcodec/version.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <stdbool.h>
#include <unifex/unifex.h>

#if LIBAVCODEC_VERSION_MAJOR >= 59
// In FFmpeg 5.0 (libavcodec 59) AVBSFContext was moved to a separate header
#include <libavcodec/bsf.h>
#endif

typedef struct State State;

struct State {
  AVFormatContext *input_ctx;
  int number_of_streams;
  bool terminating;

  AVBSFContext *h264_bsf_ctx;
};

#include "_generated/rtmp_source.h"
