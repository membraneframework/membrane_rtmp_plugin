#include "rtmp.h"
#include <stdbool.h>

static int IOWriteFunc(void *opaque, uint8_t *buf, int buf_size);
static int64_t IOSeekFunc (void *opaque, int64_t offset, int whence);

UNIFEX_TERM create(UnifexEnv* env, char* url) {
    State* s = unifex_alloc_state(env);
    s->input_ctx = avformat_alloc_context();
    unifex_self(env, &s->target);
    AVDictionary *d = NULL;
    av_dict_set(&d, "rtmp_listen", "1", 0);
    if(avformat_open_input(&s->input_ctx, url, NULL, &d) < 0) {
        unifex_free(s);
        return create_result_error(env, "Cannot open input");
    }

    if(avformat_find_stream_info(s->input_ctx, NULL) < 0) {
        unifex_free(s);
        return create_result_error(env, "Couldn't get stream info");
    }
    
    // Setup custom IO to not write to not write to a freaking file
    s->buffer = (uint8_t *) unifex_alloc(1024);
    AVOutputFormat * const output_format = av_guess_format("flv", NULL, NULL);

    avformat_alloc_output_context2(&s->output_ctx, output_format,
                NULL, NULL);

    s->output_ctx->pb = avio_alloc_context( s->buffer, 1024, 1, s, 0, &IOWriteFunc, &IOSeekFunc);
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
    avformat_write_header(s->output_ctx, NULL);

    return create_result_ok(env, s);
}

UNIFEX_TERM get_frame(UnifexEnv* env, State* state) {
    state->env = env;
    if(!state || !state->input_ctx) {
        return get_frame_result_error(env, "Invalid state");
    }

    AVPacket packet; 
    UNIFEX_TERM res;

    if(av_read_frame(state->input_ctx, &packet) >= 0) {
        bool is_valid = packet.stream_index >= state->number_of_streams || state->streams_index[packet.stream_index] < 0;
        if (is_valid) {
            res = get_frame_result_error(env, "Invalid stream index");
            av_packet_unref(&packet);
        } else {
            AVStream* in_stream  = state->input_ctx->streams[packet.stream_index];
            packet.stream_index = state->streams_index[packet.stream_index];
            AVStream* out_stream = state->output_ctx->streams[packet.stream_index];

            /* copy packet */
            packet.pts = av_rescale_q_rnd(packet.pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
            packet.dts = av_rescale_q_rnd(packet.dts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
            packet.duration = av_rescale_q(packet.duration, in_stream->time_base, out_stream->time_base);
            packet.pos = -1;
            
            av_interleaved_write_frame(state->output_ctx, &packet);
            av_packet_unref(&packet);

            res = get_frame_result_ok(env);
        }
    } else {
        res = get_frame_result_error(env, "stream finished");
    }
    
    return res;
}

void handle_destroy_state(UnifexEnv* env, State* s) {
    UNIFEX_UNUSED(env);
    if(s->input_ctx) {
        avformat_close_input(&s->input_ctx);
    }
    if(s->buffer) {
        unifex_free(s->buffer);
    }
}

//// IO Functions
static int IOWriteFunc(void *opaque, uint8_t *buf, int buf_size) {
    printf("IOWriteFunc: %d\n", buf_size);
    State* s = (State*) opaque;
    UnifexEnv* env = unifex_alloc_env(NULL);
    UnifexPayload* payload = unifex_alloc(sizeof(UnifexPayload));
    unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, buf_size, payload);
    memcpy(payload->data, buf, buf_size);
    printf("Payload allocated\n");
    
    if(!send_data(env, s->target, UNIFEX_SEND_THREADED, payload)) {       
        printf("Error sending data\n");
    } else { printf("Sent data\n"); }
    unifex_payload_release(payload);
    unifex_free(payload);
    payload = NULL;
    
    return buf_size;
}

static int64_t IOSeekFunc (void *opaque, int64_t offset, int whence) {
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