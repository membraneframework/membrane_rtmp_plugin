#pragma once

#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <stdbool.h>
#include <unifex/unifex.h>

typedef struct State State;

struct State
{
    AVFormatContext *input_ctx;
    int number_of_streams;
    bool ready;
    
    AVBSFContext* h264_bsf_ctx;
    
    UnifexPid target;
    UnifexTid thread;
};

#include "_generated/rtmp.h"