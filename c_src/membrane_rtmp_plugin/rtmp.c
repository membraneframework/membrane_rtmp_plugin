#include "rtmp.h"
#include <stdbool.h>

void handle_init_state(State *);

UNIFEX_TERM native_create(UnifexEnv *env, char *url, char *timeout) {
  State *s = unifex_alloc_state(env);
  handle_init_state(s);

  if (s->h264_bsf_ctx == NULL) {
    unifex_release_state(env, s);
    return unifex_raise(env, "Could not find filter h264_mp4toannexb");
  }

  UNIFEX_TERM ret;

  AVDictionary *d = NULL;
  av_dict_set(&d, "listen", "1", 0);

  // 0 indicates that timeout should be infinity
  if (strcmp(timeout, "0") != 0) {
    av_dict_set(&d, "timeout", timeout, 0);
  }

  if (avformat_open_input(&s->input_ctx, url, NULL, &d) < 0) {
    ret = native_create_result_error(
        env, "Couldn't open input. This might be caused by invalid address, occupied port or connection timeout");
    goto err;
  }

  if (avformat_find_stream_info(s->input_ctx, NULL) < 0) {
    ret = native_create_result_error(env, "Couldn't get stream info");
    goto err;
  }

  s->number_of_streams = s->input_ctx->nb_streams;
  
  if(s->number_of_streams == 0) {
    ret = native_create_result_error(env, "No streams found - at least one stream is required");
    goto err;
  }

  for (int i = 0; i < s->number_of_streams; i++) {
    AVStream *in_stream = s->input_ctx->streams[i];
    AVCodecParameters *in_codecpar = in_stream->codecpar;
    if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO &&
        in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO) {
      continue;
    }

    if (in_codecpar->codec_id != AV_CODEC_ID_H264 && in_codecpar->codec_id != AV_CODEC_ID_AAC) {
      ret = native_create_result_error(env, "Unsupported codec. Only H264 and AAC are supported");
      goto err;
    }
  }

  av_bsf_init(s->h264_bsf_ctx);
  ret = native_create_result_ok(env, s);
err:
  unifex_release_state(env, s);
  return ret;
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

int64_t get_timestamp(AVPacket* pkt, AVStream* stream) {
  const AVRational target_time_base = {1, 1000};
  return av_rescale_q_rnd(pkt->pts, stream->time_base, target_time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
}

UNIFEX_TERM read_frame(UnifexEnv* env, State* s) {
  AVPacket packet;
  AVStream* in_stream;
  enum AVMediaType codec_type;
  UNIFEX_TERM result;

  while(true) {
    if(av_read_frame(s->input_ctx, &packet) < 0) {
      result = read_frame_result_end_of_stream(env);
      goto end;
    }

    if(packet.stream_index >= s->number_of_streams) {
      result = read_frame_result_error(env, "Invalid stream index");
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
  
  UNIFEX_TERM (*result_func)(UnifexEnv*, int64_t, UnifexPayload*) = NULL;
  
  switch(codec_type) {
    case AVMEDIA_TYPE_VIDEO:
      av_bsf_send_packet(s->h264_bsf_ctx, &packet);
      av_bsf_receive_packet(s->h264_bsf_ctx, &packet);
      result_func = &read_frame_result_video;
      break;
    
    case AVMEDIA_TYPE_AUDIO:
      result_func = &read_frame_result_audio;
      break;

    default:
      return unifex_raise(env, "Unsupported frame type");
  }

  UnifexPayload payload;
  unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY, packet.size, &payload);
  memcpy(payload.data, packet.data, packet.size);
  result = result_func(env, get_timestamp(&packet, in_stream), &payload);
  unifex_payload_release(&payload);
  
end:
  av_packet_unref(&packet);
  return result;
}

void handle_init_state(State *s) {
  s->input_ctx = avformat_alloc_context();
  s->ready = false;
  const AVBitStreamFilter *h264_filter = av_bsf_get_by_name("h264_mp4toannexb");
  av_bsf_alloc(h264_filter, &s->h264_bsf_ctx);
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
