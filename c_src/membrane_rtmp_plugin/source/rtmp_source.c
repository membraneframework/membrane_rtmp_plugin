#include "rtmp_source.h"
#include <stdbool.h>

void handle_init_state(State *);

static int interrupt_cb(void *ctx) {
  bool is_terminating = *(bool *)ctx;
  // interrupt if the flag is set
  return is_terminating;
}

UNIFEX_TERM create(UnifexEnv *env) {
  State *s = unifex_alloc_state(env);
  handle_init_state(s);

  if (s->h264_bsf_ctx == NULL) {
    unifex_release_state(env, s);
    return unifex_raise(env, "Could not find filter h264_mp4toannexb");
  }

  s->input_ctx->interrupt_callback.callback = interrupt_cb;
  s->input_ctx->interrupt_callback.opaque = &s->terminating;
  return create_result_ok(env, s);
}

UNIFEX_TERM await_open(UnifexEnv *env, State *s, char *url, int timeout) {
  AVDictionary *d = NULL;
  av_dict_set(&d, "listen", "1", 0);
  av_dict_set_int(&d, "timeout", timeout, 0);

  UNIFEX_TERM ret;

  int av_err = avformat_open_input(&s->input_ctx, url, NULL, &d);
  if (av_err == AVERROR(ETIMEDOUT)) {
    ret = await_open_result_error_timeout(env);
    goto err;
  } else if (av_err == AVERROR_EXIT) {
    // Error returned when interrupt_cb returns non-zero
    ret = await_open_result_error_interrupted(env);
    goto err;
  } else if (av_err < 0) {
    ret = await_open_result_error(env, av_err2str(av_err));
    goto err;
  }

  if (avformat_find_stream_info(s->input_ctx, NULL) < 0) {
    ret = await_open_result_error(env, "Couldn't get stream info");
    goto err;
  }

  s->number_of_streams = s->input_ctx->nb_streams;

  if (s->number_of_streams == 0) {
    ret = await_open_result_error(
        env, "No streams found - at least one stream is required");
    goto err;
  }

  for (int i = 0; i < s->number_of_streams; i++) {
    AVStream *in_stream = s->input_ctx->streams[i];
    AVCodecParameters *in_codecpar = in_stream->codecpar;
    if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO &&
        in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO) {
      continue;
    }

    if (in_codecpar->codec_id != AV_CODEC_ID_H264 &&
        in_codecpar->codec_id != AV_CODEC_ID_AAC) {
      ret = await_open_result_error(
          env, "Unsupported codec. Only H264 and AAC are supported");
      goto err;
    }
    if (in_codecpar->codec_id == AV_CODEC_ID_H264) {
      s->h264_bsf_ctx->time_base_in = in_stream->time_base;
      s->h264_bsf_ctx->par_in->codec_id = in_codecpar->codec_id;
    }
  }

  av_bsf_init(s->h264_bsf_ctx);
  ret = await_open_result_ok(env, s);
err:
  unifex_release_state(env, s);
  return ret;
}

UNIFEX_TERM set_terminate(UnifexEnv *env, State *s) {
  s->terminating = true;
  return set_terminate_result_ok(env);
}

UNIFEX_TERM get_audio_params(UnifexEnv *env, State *s) {
  for (int i = 0; i < s->number_of_streams; i++) {
    if (s->input_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
      UnifexPayload payload;
      unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY,
                           s->input_ctx->streams[i]->codecpar->extradata_size,
                           &payload);
      memcpy(payload.data, s->input_ctx->streams[i]->codecpar->extradata,
             s->input_ctx->streams[i]->codecpar->extradata_size);
      UNIFEX_TERM result = get_audio_params_result_ok(env, &payload);
      unifex_payload_release(&payload);
      return result;
    }
  }

  return get_audio_params_result_error(env);
}

UNIFEX_TERM get_video_params(UnifexEnv *env, State *s) {
  for (int i = 0; i < s->number_of_streams; i++) {
    if (s->input_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
      UnifexPayload payload;
      unifex_payload_alloc(env, UNIFEX_PAYLOAD_BINARY,
                           s->input_ctx->streams[i]->codecpar->extradata_size,
                           &payload);
      memcpy(payload.data, s->input_ctx->streams[i]->codecpar->extradata,
             s->input_ctx->streams[i]->codecpar->extradata_size);
      UNIFEX_TERM result = get_video_params_result_ok(env, &payload);
      unifex_payload_release(&payload);
      return result;
    }
  }

  return get_video_params_result_error(env);
}

int64_t get_pts(AVPacket *pkt, AVStream *stream) {
  const AVRational target_time_base = {1, 1000};
  return av_rescale_q_rnd(pkt->pts, stream->time_base, target_time_base,
                          AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
}

int64_t get_dts(AVPacket *pkt, AVStream *stream) {
  const AVRational target_time_base = {1, 1000};
  return av_rescale_q_rnd(pkt->dts, stream->time_base, target_time_base,
                          AV_ROUND_NEAR_INF | AV_ROUND_PASS_MINMAX);
}

UNIFEX_TERM read_frame(UnifexEnv *env, State *s) {
  AVPacket packet;
  AVStream *in_stream;
  enum AVMediaType codec_type;
  UNIFEX_TERM result;

  while (true) {
    if (av_read_frame(s->input_ctx, &packet) < 0) {
      result = read_frame_result_end_of_stream(env);
      goto end;
    }

    if (packet.stream_index >= s->number_of_streams) {
      result = read_frame_result_error(env, "Invalid stream index");
      goto end;
    }

    in_stream = s->input_ctx->streams[packet.stream_index];
    codec_type = in_stream->codecpar->codec_type;

    if (codec_type != AVMEDIA_TYPE_AUDIO && codec_type != AVMEDIA_TYPE_VIDEO) {
      av_packet_unref(&packet);
    } else {
      break;
    }
  }

  UNIFEX_TERM(*result_func)
  (UnifexEnv *, int64_t, int64_t, UnifexPayload *) = NULL;

  switch (codec_type) {
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
  result = result_func(env, get_pts(&packet, in_stream),
                       get_dts(&packet, in_stream), &payload);
  unifex_payload_release(&payload);

end:
  av_packet_unref(&packet);
  return result;
}

void handle_init_state(State *s) {
  s->input_ctx = avformat_alloc_context();
  s->terminating = false;
  const AVBitStreamFilter *h264_filter = av_bsf_get_by_name("h264_mp4toannexb");
  av_bsf_alloc(h264_filter, &s->h264_bsf_ctx);
}

void handle_destroy_state(UnifexEnv *env, State *s) {
  UNIFEX_UNUSED(env);

  s->terminating = true;

  if (s->h264_bsf_ctx) {
    av_bsf_free(&s->h264_bsf_ctx);
  }

  if (s->input_ctx) {
    avformat_close_input(&s->input_ctx);
  }
}
