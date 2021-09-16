#pragma once

#include <libavutil/timestamp.h>
#include <libavformat/avformat.h>
#include <stdbool.h>
#include <unifex/unifex.h>

typedef struct State State;

struct State
{
    AVFormatContext *input_ctx;
    AVFormatContext *output_ctx;
    uint8_t *buffer;
    int* streams_index;
    int number_of_streams;
    
    UnifexPid target;
    UnifexEnv* env;
};

#include "_generated/rtmp.h"