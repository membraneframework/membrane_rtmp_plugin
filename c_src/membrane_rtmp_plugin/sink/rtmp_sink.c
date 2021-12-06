#include "rtmp_sink.h"
#include <stdlib.h>

const float H264_BPP = 0.116f;
const AVRational MEMBRANE_TIME_BASE  = (AVRational) {1, 1000000000};

void handle_init_state(State* state);

void handle_destroy_state(UnifexEnv* env, State* state);

UNIFEX_TERM init_connection(UnifexEnv* env, char* rtmp_url) {
    State* state = unifex_alloc_state(env);
    handle_init_state(state);
    AVFormatContext* output_ctx;
    
    avformat_alloc_output_context2(&output_ctx, NULL, "flv", rtmp_url);
    if(!output_ctx){
        unifex_release_state(env, state);
        return init_connection_result_error(env, "Failed to initialize output context.");
    }

    if (!(output_ctx->oformat->flags & AVFMT_NOFILE)) {
        if(avio_open(&output_ctx->pb, rtmp_url, AVIO_FLAG_WRITE) < 0){
            unifex_release_state(env, state);
            return init_connection_result_error(env, "Failed to open provided URL for writing.");
        }
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
    video_stream->avg_frame_rate = (AVRational) {frames, seconds};

    video_stream->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
    video_stream->codecpar->codec_id = AV_CODEC_ID_H264;
    video_stream->codecpar->width = width;
    video_stream->codecpar->height = height;
    video_stream->codecpar->bit_rate = (int64_t) (H264_BPP * width * height * frames / seconds);
    video_stream->codecpar->format = AV_PIX_FMT_YUV420P;

    int ready = (state->video_stream_index != -1 && state->audio_stream_index != -1);
    return init_video_stream_result_ok(env, ready, state);
}

UNIFEX_TERM init_audio_stream(UnifexEnv* env, State* state, int channels, int sample_rate, UnifexPayload* aac_config){
    AVStream* audio_stream;

    if(state->audio_stream_index == -1){
        audio_stream = avformat_new_stream(state->output_ctx, NULL);
        if(!audio_stream){
            return init_audio_stream_result_error(env, "Failed allocating audio stream");
        }
        state->audio_stream_index = audio_stream->index;
    }
    else{
        audio_stream = state->output_ctx->streams[state->audio_stream_index];
    }

    audio_stream->codecpar->codec_type = AVMEDIA_TYPE_AUDIO;
    audio_stream->codecpar->codec_id = AV_CODEC_ID_AAC;
    audio_stream->codecpar->sample_rate = sample_rate;
    audio_stream->codecpar->extradata_size = aac_config->size;
    audio_stream->codecpar->extradata = (uint8_t*) av_malloc(aac_config->size + AV_INPUT_BUFFER_PADDING_SIZE);

    if(!audio_stream->codecpar->extradata){
        return init_audio_stream_result_error(env, "Failed allocating audio stream extradata");
    }
    memcpy(audio_stream->codecpar->extradata, aac_config->data, aac_config->size);

    int ready = (state->video_stream_index != -1 && state->audio_stream_index != -1);
    return init_audio_stream_result_ok(env, ready, state);
}

UNIFEX_TERM write_header(UnifexEnv* env, State* state, UnifexPayload* avc_configuration_record){
    if(!state->header_written){
        AVStream* video_stream = state->output_ctx->streams[state->video_stream_index];
        video_stream->codecpar->extradata_size = avc_configuration_record->size;
        video_stream->codecpar->extradata = (uint8_t*) av_malloc(avc_configuration_record->size + AV_INPUT_BUFFER_PADDING_SIZE);

        if(!video_stream->codecpar->extradata){
            return write_header_result_error(env, "Failed allocation video stream sps and pps data");
        }
        memcpy(video_stream->codecpar->extradata, avc_configuration_record->data, avc_configuration_record->size);
        
        if(avformat_write_header(state->output_ctx, NULL) < 0){
            return write_header_result_error(env, "Failed writing header.");
        }
        state->header_written = true;
    }
    return write_header_result_ok(env, state);
}

UNIFEX_TERM write_video_frame(UnifexEnv* env, State* state, UnifexPayload* frame, int64_t dts, int is_key_frame){
    if(state->video_stream_index == -1){
        return write_video_frame_result_error(env, "Failed attempting to write video frame without initialized video stream");
    }

    AVRational video_stream_time_base = state->output_ctx->streams[state->video_stream_index]->time_base;
    AVPacket* packet = av_packet_alloc();

    if(is_key_frame){
        packet->flags |= AV_PKT_FLAG_KEY;
    }

    packet->stream_index = state->video_stream_index;
    packet->size = frame->size;
    packet->data = (uint8_t*) av_malloc(frame->size);

    if(!packet->data){
        return write_video_frame_result_error(env, "Failed allocating video frame data.");
    }

    memcpy(packet->data, frame->data, frame->size);

    int64_t dts_scaled = av_rescale_q(dts, MEMBRANE_TIME_BASE, video_stream_time_base);

    packet->dts = dts_scaled;
    packet->pts = dts_scaled;

    packet->duration = dts_scaled - state->current_video_dts;
    state->current_video_dts = dts_scaled;

    
    if(av_interleaved_write_frame(state->output_ctx, packet)){
        return write_video_frame_result_error(env, "Failed writing video frame");
    }
  

    av_packet_unref(packet);
    av_packet_free(&packet);
    return write_video_frame_result_ok(env, state);
}

UNIFEX_TERM write_audio_frame(UnifexEnv* env, State* state, UnifexPayload* frame, int64_t pts){
    if(state->audio_stream_index == -1){
        return write_audio_frame_result_error(env, "Failed attempting to write audio frame without initialized audio stream");
    }

    AVPacket* packet = av_packet_alloc();

    packet->stream_index = state->audio_stream_index;
    packet->size = frame->size;

    packet->data = (uint8_t*) av_malloc(frame->size);
    if(!packet->data){
        return write_audio_frame_result_error(env, "Failed allocating audio frame data.");
    }
    memcpy(packet->data, frame->data, frame->size);
    
    packet->dts = pts;
    packet->pts = pts;

    packet->duration = pts - state->current_audio_pts;
    state->current_audio_pts = pts;
    
    if(av_interleaved_write_frame(state->output_ctx, packet)){
        return write_audio_frame_result_error(env, "Failed writing audio frame");
    }
    
    av_packet_unref(packet);
    av_packet_free(&packet);
    return write_audio_frame_result_ok(env, state);
}

void handle_init_state(State* state){
    state->video_stream_index = -1;
    state->current_video_dts = 0;
   
    state->audio_stream_index = -1;
    state->current_audio_pts = 0;
    
    state->header_written = false;

    state->output_ctx = NULL;
}

void handle_destroy_state(UnifexEnv* env, State* state) {
    UNIFEX_UNUSED(env);
    if (state->output_ctx && !(state->output_ctx->oformat->flags & AVFMT_NOFILE)){
		avio_closep(&state->output_ctx->pb);
    }
    if(state->output_ctx){
        avformat_free_context(state->output_ctx);
    }
    state->video_stream_index = -1;
}

