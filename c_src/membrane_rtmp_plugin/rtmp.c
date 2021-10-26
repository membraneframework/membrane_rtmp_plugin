#include "rtmp.h"
#include <stdbool.h>

void handle_init_state(UnifexEnv*, State*);

UNIFEX_TERM native_create(UnifexEnv* env, char* url, char* timeout) {
    State* s = unifex_alloc_state(env);
    handle_init_state(env, s);

    AVDictionary *d = NULL;
    av_dict_set(&d, "listen", "1", 0);
    
    if(strcmp(timeout, "0") != 0) { // 0 indicates that timeout should be infinity
        printf("Setting timeout to %s\n", timeout);
        av_dict_set(&d, "timeout", timeout, 0);
    }

    if(avformat_open_input(&s->input_ctx, url, NULL, &d) < 0) {
        unifex_release_state(env, s);
        return native_create_result_error(env, "Couldn't open input. This might be caused by invalid address, occupied port or connection timeout");
    }

    if(avformat_find_stream_info(s->input_ctx, NULL) < 0) {
        avformat_close_input(&s->input_ctx);
        unifex_release_state(env, s);
        return native_create_result_error(env, "Couldn't get stream info");
    }
    
    s->number_of_streams = s->input_ctx->nb_streams;
    
    for(int i = 0; i < s->number_of_streams; i++) {
        AVStream* in_stream = s->input_ctx->streams[i];
        AVCodecParameters* in_codecpar = in_stream->codecpar;
        if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO && in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO) {
            continue;
        }
        
        if (in_codecpar->codec_id != AV_CODEC_ID_H264 && in_codecpar->codec_id != AV_CODEC_ID_AAC) {
            avformat_close_input(&s->input_ctx);
            unifex_release_state(env, s);

            char error_message[150];
            sprintf(error_message, "Unsupported codec: %s", avcodec_get_name(in_codecpar->codec_id));
            return native_create_result_error(env, &error_message);
        }
        
        UnifexPayload payload;
        unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, in_codecpar->extradata_size, &payload);
        memcpy(payload.data, in_codecpar->extradata, in_codecpar->extradata_size);

        int (*write_func)(UnifexEnv*, UnifexPid, int, UnifexPayload*) = NULL;
        
        if(in_stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            write_func = &send_video_params;
        } else if(in_stream->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            write_func = &send_audio_params;
        }
        
        if(!write_func(env, s->target, 0, &payload)) {       
            printf("Error sending data\n");
        }
        unifex_payload_release(&payload);
    }
    
    return native_create_result_ok(env, s);
}

void* get_frame(void* opaque) {
    State* state = (State*) opaque;
    UnifexEnv* env = unifex_alloc_env(NULL);

    if(!state || !state->input_ctx || state->ready) {
        unifex_raise(env, "Tried to stream with invalid state");
    }

    AVPacket packet; 
    state->ready = true;
 
    while(state->ready && av_read_frame(state->input_ctx, &packet) >= 0) {
        if(packet.stream_index >= state->number_of_streams) continue;

        AVStream* in_stream  = state->input_ctx->streams[packet.stream_index];

        int (*write_func)(UnifexEnv*, UnifexPid, int, UnifexPayload*) = NULL;
        
        switch (in_stream->codecpar->codec_type) {
            case AVMEDIA_TYPE_VIDEO:
                av_bsf_send_packet(state->h264_bsf_ctx, &packet);
                av_bsf_receive_packet(state->h264_bsf_ctx, &packet);
                write_func = &send_video;
                break;
            case AVMEDIA_TYPE_AUDIO:
                write_func = &send_audio;
                break;
            default:
                continue;
        }
        
        UnifexPayload payload;
        unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, packet.size, &payload);
        memcpy(payload.data, packet.data, packet.size);
        
        if(!write_func(env, state->target, UNIFEX_SEND_THREADED, &payload)) {       
            printf("Error sending data\n");
        }
        unifex_payload_release(&payload);

        av_packet_unref(&packet); // always unref that packet or bad things will happen
    }

    state->ready = false; 
    send_end_of_stream(env, state->target, UNIFEX_SEND_THREADED);
    unifex_free_env(env);
    env = NULL;

    return NULL;
}

UNIFEX_TERM stream_frames(UnifexEnv* env, State* state) {
    if(!state || !state->input_ctx || state->ready) {
        return stream_frames_result_error(env, "Already streaming");
    }

    unifex_thread_create(NULL, &state->thread, get_frame, state);
    return stream_frames_result_ok(env); 
}

UNIFEX_TERM stop_streaming(UnifexEnv* env, State* state) {
    if(!state || !state->ready) {
        return stop_streaming_result_error(env, "Already stopped");
    }

    // mark the process as not ready to stream.The thread will finish processing the current frame and exit. Some data might be lost
    // the thread might also write the format trailer before exiting, depending on the format
    state->ready = false; 
    unifex_thread_join(state->thread, NULL); // join ignoring return value
    return stop_streaming_result_ok(env);
}

void handle_init_state(UnifexEnv* env, State* s) {
    s->input_ctx = avformat_alloc_context();
    s->ready = false;
    const AVBitStreamFilter* h264_filter = av_bsf_get_by_name("h264_mp4toannexb");
    av_bsf_alloc(h264_filter, &s->h264_bsf_ctx);
    av_bsf_init(s->h264_bsf_ctx);
    if(s->h264_bsf_ctx == NULL) {
        unifex_raise(env, "Could not find h264_mp4toannexb");
    }
    unifex_self(env, &s->target);
}

void handle_destroy_state(UnifexEnv* env, State* s) {
    UNIFEX_UNUSED(env);
    stop_streaming(env, s);
    if(s->input_ctx) {
        avformat_close_input(&s->input_ctx);
    }
}