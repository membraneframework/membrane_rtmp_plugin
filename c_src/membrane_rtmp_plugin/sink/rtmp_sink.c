#include "rtmp_sink.h"

#define H264_BPP 0.116f

void handle_init_state(State* state);

void handle_destroy_state(UnifexEnv* env, State* state);

UNIFEX_TERM init_connection(UnifexEnv* env, char* rtmp_url) {
    State* state = unifex_alloc_state(env);
    handle_init_state(state);
    AVFormatContext* output_ctx;
    
    avformat_alloc_output_context2(&output_ctx, NULL, "flv", rtmp_url);
    if(!output_ctx){
        unifex_release_state(env, state);
        return init_connection_result_error(env, "Failed to connect to output URL.");
    }

    state->output_ctx = output_ctx;
    return init_connection_result_ok(env, state);
}

UNIFEX_TERM close_connection(UnifexEnv* env, State* state){
    handle_destroy_state(env, state);
    return close_connection_result_ok(env);
}

UNIFEX_TERM init_video_stream(UnifexEnv* env, State* state, int width, int height, int frames, int seconds){
    AVStream* video_stream;

    if(state->video_stream_index == -1){
        video_stream = avformat_new_stream(state->output_ctx, NULL);
        if(!video_stream){
            return init_video_stream_result_error(env, "Failed allocation video stream");
        }
        state->video_stream_index = video_stream->index;
    }
    else{
        video_stream = state->output_ctx->streams[state->video_stream_index];
    }
    
    video_stream->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
    video_stream->codecpar->codec_id = AV_CODEC_ID_H264;

    video_stream->codecpar->width = width;
    video_stream->codecpar->height = height;
    video_stream->codecpar->bit_rate = (int64_t) (H264_BPP * width * height * frames / seconds);

    video_stream->codecpar->format = AV_PIX_FMT_YUV420P;
    
    // Those paremeters can be set once first video keyframe is received
    video_stream->codecpar->extradata_size = -1;
    video_stream->codecpar->extradata = NULL;

    return init_video_stream_result_ok(env, state);
}

UNIFEX_TERM write_video_frame(UnifexEnv* env, State* state, UnifexPayload* frame){
    if(state->video_stream_index == -1){
        return write_video_frame_result_error(env, "Failed attempting to write video frame to without initialized video stream");
    }
    
    AVPacket packet;
    packet.stream_index = state->video_stream_index;
    packet.data = (uint8_t*) frame->data;
    packet.size = frame->size;
    packet.pos = -1;

    if(av_interleaved_write_frame(state->output_ctx, &packet)){
        return write_video_frame_result_error(env, "Failed writing video frame");
    }

    av_packet_unref(&packet);
    return write_video_frame_result_ok(env, state);
}

void handle_init_state(State* state){
    state->video_stream_index = -1;
    state->output_ctx = NULL;
}

void handle_destroy_state(UnifexEnv* env, State* state) {
    UNIFEX_UNUSED(env);
    if(state->output_ctx){
        avformat_free_context(state->output_ctx);
    }
    state->video_stream_index = -1;
}

