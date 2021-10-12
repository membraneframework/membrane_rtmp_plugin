#include "rtmp.h"
#include <stdbool.h>

static int IOWriteFunc(void *opaque, uint8_t *buf, int buf_size);
static int64_t IOSeekFunc (void *opaque, int64_t offset, int whence);

UNIFEX_TERM native_create(UnifexEnv* env, char* url, char* timeout) {
    State* s = unifex_alloc_state(env);
    s->input_ctx = avformat_alloc_context();
    s->ready = false;

    unifex_self(env, &s->target);
    AVDictionary *d = NULL;
    av_dict_set(&d, "listen", "1", 0);
    
    if(strcmp(timeout, "0") != 0) { // 0 indicates that timeout should be infinity
        printf("Setting timeout to %s\n", timeout);
        av_dict_set(&d, "timeout", timeout, 0);
    }

    if(avformat_open_input(&s->input_ctx, url, NULL, &d) < 0) {
        avformat_free_context(s->input_ctx);
        unifex_release_state(env, s);
        return native_create_result_error(env, "Couldn't open input. This might be caused by invalid address, occupied port or connection timeout");
    }

    if(avformat_find_stream_info(s->input_ctx, NULL) < 0) {
        avformat_free_context(s->input_ctx);
        unifex_release_state(env, s);
        return native_create_result_error(env, "Couldn't get stream info");
    }
    
    // Setup custom IO to not write to not write to a file
    s->buffer = (uint8_t *) unifex_alloc(8192);
    AVOutputFormat * const output_format = av_guess_format("flv", NULL, NULL);

    avformat_alloc_output_context2(&s->output_ctx, output_format,
                NULL, NULL);

    s->output_ctx->pb = avio_alloc_context( s->buffer, 8192, 1, s, 0, &IOWriteFunc, &IOSeekFunc);
    s->output_ctx->flags |= AVFMT_FLAG_CUSTOM_IO; 
    s->output_ctx->oformat = output_format;
    
    s->number_of_streams = s->input_ctx->nb_streams;
    s->streams_index = (int *) unifex_alloc(sizeof(int) * s->number_of_streams);

    int streams_index = 0;
    
    for(int i = 0; i < s->number_of_streams; i++) {
        AVStream* out_stream;
        AVStream* in_stream = s->input_ctx->streams[i];
        AVCodecParameters *in_codecpar = in_stream->codecpar;
        if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO && in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO && in_codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) {
            s->streams_index[i] = -1;
            continue;
        }
        
        s->streams_index[i] = streams_index++;
        out_stream = avformat_new_stream(s->output_ctx, NULL);
        avcodec_parameters_copy(out_stream->codecpar, in_codecpar);
    }
    
    av_dump_format(s->output_ctx, 0, NULL, 1);
    if(avformat_write_header(s->output_ctx, NULL) < 0) {
        avformat_free_context(s->output_ctx); avformat_free_context(s->input_ctx);
        unifex_release_state(env, s);
        return native_create_result_error(env, "Couldn't write header");
    }

    return native_create_result_ok(env, s);
}

void* get_frame(void* opaque) {
    State* state = (State*) opaque;

    if(!state || !state->input_ctx || !state->output_ctx || state->ready) {
        printf("Tried to stream with invalid state, terminating the process");
        return NULL;
    }

    UnifexEnv* env = unifex_alloc_env(NULL);
    AVPacket packet; 
    state->ready = true;
 
    while(state->ready && av_read_frame(state->input_ctx, &packet) >= 0) {
        if(!(packet.stream_index >= state->number_of_streams || state->streams_index[packet.stream_index] < 0)) {
            AVStream* in_stream  = state->input_ctx->streams[packet.stream_index];
            packet.stream_index = state->streams_index[packet.stream_index];
            AVStream* out_stream = state->output_ctx->streams[packet.stream_index];

            // copy packet and rescale timestamps 
            packet.pts = av_rescale_q_rnd(packet.pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
            packet.dts = av_rescale_q_rnd(packet.dts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
            packet.duration = av_rescale_q(packet.duration, in_stream->time_base, out_stream->time_base);
            packet.pos = -1;
            
            av_interleaved_write_frame(state->output_ctx, &packet);
        }

        av_packet_unref(&packet); // always unref that packet or bad things will happen
    }

    state->ready = false; 
    av_write_trailer(state->output_ctx);
    send_end_of_stream(env, state->target, UNIFEX_SEND_THREADED);
    unifex_free_env(env);
    env = NULL;

    return NULL;
}

UNIFEX_TERM stream_frames(UnifexEnv* env, State* state) {
    if(!state || !state->input_ctx || !state->output_ctx || state->ready) {
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

void handle_destroy_state(UnifexEnv* env, State* s) {
    UNIFEX_UNUSED(env);
    stop_streaming(env, s);
    if(s->input_ctx) {
        avformat_close_input(&s->input_ctx);
    }
    if(s->buffer) {
        unifex_free(s->buffer);
    }
}

//// IO Functions
static int IOWriteFunc(void* opaque, uint8_t *buf, int buf_size) {
    State* s = (State*) opaque;
    UnifexEnv* env = unifex_alloc_env(NULL);
    UnifexPayload* payload = unifex_alloc(sizeof(UnifexPayload));
    unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, buf_size, payload);
    memcpy(payload->data, buf, buf_size);
    
    if(!send_frame(env, s->target, UNIFEX_SEND_THREADED, payload)) {       
        printf("Error sending data\n");
    }
    unifex_payload_release(payload);
    unifex_free(payload);
    unifex_free_env(env);
    
    return buf_size;
}

static int64_t IOSeekFunc (void * __attribute__((__unused__)) opaque, int64_t __attribute__((__unused__)) size, int whence) {
    switch(whence){
        case SEEK_SET:
            return 1;
        case SEEK_CUR:
            return 1;
        case SEEK_END:
            return 1;
        case AVSEEK_SIZE:
            return 4096;
        default:
           return -1;
    }
    return 1;
}