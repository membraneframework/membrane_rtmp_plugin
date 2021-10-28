#include "rtmp.h"
#include <stdbool.h>

void handle_init_state(UnifexEnv *, State *);

UNIFEX_TERM native_create(UnifexEnv *env, char *url, char *timeout) {
  State *s = unifex_alloc_state(env);
  handle_init_state(env, s);

  AVDictionary *d = NULL;
  av_dict_set(&d, "listen", "1", 0);

  // 0 indicates that timeout should be infinity
  if (strcmp(timeout, "0") != 0) {
    av_dict_set(&d, "timeout", timeout, 0);
  }

  if (avformat_open_input(&s->input_ctx, url, NULL, &d) < 0) {
    unifex_release_state(env, s);
    return native_create_result_error(
        env, "Couldn't open input. This might be caused by invalid address, occupied port or connection timeout");
  }

  if (avformat_find_stream_info(s->input_ctx, NULL) < 0) {
    unifex_release_state(env, s);
    return native_create_result_error(env, "Couldn't get stream info");
  }

  s->number_of_streams = s->input_ctx->nb_streams;
  
  if(s->number_of_streams == 0) {
    unifex_release_state(env, s);
    return native_create_result_error(env, "No streams found - at least one stream is required");
  }

  for (int i = 0; i < s->number_of_streams; i++) {
    AVStream *in_stream = s->input_ctx->streams[i];
    AVCodecParameters *in_codecpar = in_stream->codecpar;
    if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO &&
        in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO) {
      continue;
    }

    if (in_codecpar->codec_id != AV_CODEC_ID_H264 && in_codecpar->codec_id != AV_CODEC_ID_AAC) {
      unifex_release_state(env, s);
      return native_create_result_error(env, "Unsupported codec. Only H264 and AAC are supported");
    }
  }

  return native_create_result_ok(env, s);
}

UNIFEX_TERM get_audio_params(UnifexEnv* env, State* s) {
  for(int i = 0; i < s->number_of_streams; i++) {
    if(s->input_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
      UnifexPayload payload;
      unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, s->input_ctx->streams[i]->codecpar->extradata_size, &payload);
      memcpy(payload.data, s->input_ctx->streams[i]->codecpar->extradata, s->input_ctx->streams[i]->codecpar->extradata_size);
      UNIFEX_TERM result = get_audio_params_result_ok(env, &payload);
      unifex_payload_release(&payload);
      return result;
    }
  }
  
  return get_audio_params_result_error(env);
}

UNIFEX_TERM get_video_params(UnifexEnv* env, State* s) {
  for(int i = 0; i < s->number_of_streams; i++) {
      if(s->input_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
        UnifexPayload payload;
        unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, s->input_ctx->streams[i]->codecpar->extradata_size, &payload);
        memcpy(payload.data, s->input_ctx->streams[i]->codecpar->extradata, s->input_ctx->streams[i]->codecpar->extradata_size);
        UNIFEX_TERM result = get_video_params_result_ok(env, &payload);
        unifex_payload_release(&payload);
        return result;
      }
    }

  return get_video_params_result_error(env);
}

UNIFEX_TERM fetch_frame(UnifexEnv* env, State* s) {
  AVPacket packet;
  AVStream* in_stream;
  enum AVMediaType codec_type;
  UNIFEX_TERM result;

  while(true) {
    if(av_read_frame(s->input_ctx, &packet) < 0) {
      result = fetch_frame_result_end_of_stream(env);
      goto end;
    }

    if(packet.stream_index >= s->number_of_streams) {
      result = fetch_frame_result_error(env, "Invalid stream index");
      goto end;
    }
    
    in_stream = s->input_ctx->streams[packet.stream_index];
    codec_type = in_stream->codecpar->codec_type;

    if(codec_type != AVMEDIA_TYPE_AUDIO && codec_type != AVMEDIA_TYPE_VIDEO) {
      av_packet_unref(&packet);
    } else {
      break;
    }
  }
  
  UNIFEX_TERM (*result_func)(UnifexEnv*, UnifexPayload*) = NULL;
  
  switch(codec_type) {
    case AVMEDIA_TYPE_VIDEO:
      av_bsf_send_packet(s->h264_bsf_ctx, &packet);
      av_bsf_receive_packet(s->h264_bsf_ctx, &packet);
      result_func = &fetch_frame_result_video;
      break;
    
    case AVMEDIA_TYPE_AUDIO:
      result_func = &fetch_frame_result_audio;
      break;

    default:
      unifex_raise(env, "Unsupported frame type");
  }

  UnifexPayload payload;
  unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, packet.size, &payload);
  memcpy(payload.data, packet.data, packet.size);
  av_packet_unref(&packet);
  result = result_func(env, &payload);
  unifex_payload_release(&payload);
  
end:
  av_packet_unref(&packet);
  return result;
}

void handle_init_state(UnifexEnv *env, State *s) {
  s->input_ctx = avformat_alloc_context();
  s->ready = false;
  const AVBitStreamFilter *h264_filter = av_bsf_get_by_name("h264_mp4toannexb");
  av_bsf_alloc(h264_filter, &s->h264_bsf_ctx);
  av_bsf_init(s->h264_bsf_ctx);
  if (s->h264_bsf_ctx == NULL) {
    unifex_release_state(env, s);
    unifex_raise(env, "Could not find h264_mp4toannexb");
  }
  unifex_self(env, &s->target);
}

void handle_destroy_state(UnifexEnv *env, State *s) {
  UNIFEX_UNUSED(env);

  if(s->h264_bsf_ctx) {
    av_bsf_free(&s->h264_bsf_ctx);
  }

  if (s->input_ctx) {
    avformat_close_input(&s->input_ctx);
  }
}