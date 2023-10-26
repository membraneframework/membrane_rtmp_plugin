#include "rtmp_sink.h"
#include <stdlib.h>

const AVRational MEMBRANE_TIME_BASE = (AVRational){1, 1000000000};

void handle_init_state(State *state);

static bool is_ready(State *state);

UNIFEX_TERM create(UnifexEnv *env, char *rtmp_url, int audio_present,
                   int video_present) {
  State *state = unifex_alloc_state(env);
  handle_init_state(state);

  state->audio_present = audio_present;
  state->video_present = video_present;

  UNIFEX_TERM create_result;
  avformat_alloc_output_context2(&state->output_ctx, NULL, "flv", rtmp_url);
  if (!state->output_ctx) {
    create_result =
        create_result_error(env, "Failed to initialize output context");
    goto end;
  }
  create_result = create_result_ok(env, state);
end:
  unifex_release_state(env, state);
  return create_result;
}

UNIFEX_TERM try_connect(UnifexEnv *env, State *state) {
  const char *rtmp_url = state->output_ctx->url;
  if (!(state->output_ctx->oformat->flags & AVFMT_NOFILE)) {
    int av_err = avio_open(&state->output_ctx->pb, rtmp_url, AVIO_FLAG_WRITE);
    if (av_err == AVERROR(ECONNREFUSED)) {
      return try_connect_result_error_econnrefused(env);
    } else if (av_err == AVERROR(ETIMEDOUT)) {
      return try_connect_result_error_etimedout(env);
    } else if (av_err < 0) {
      return try_connect_result_error(env, av_err2str(av_err));
    }
  }
  return try_connect_result_ok(env);
}

UNIFEX_TERM flush_and_close_stream(UnifexEnv *env, State *state) {
  if (!state->output_ctx || state->closed || !is_ready(state)) {
    return finalize_stream_result_ok(env);
  }
  if (av_write_trailer(state->output_ctx)) {
    return unifex_raise(env, "Failed writing stream trailer");
  }
  avio_close(state->output_ctx->pb);
  avformat_free_context(state->output_ctx);
  state->closed = true;
  return finalize_stream_result_ok(env);
}

UNIFEX_TERM finalize_stream(UnifexEnv *env, State *state) {
  // Retained for backward compatibility.
  return flush_and_close_stream(env, state);
}

UNIFEX_TERM init_video_stream(UnifexEnv *env, State *state, int width,
                              int height, UnifexPayload *avc_config) {
  AVStream *video_stream;
  if (state->video_stream_index != -1) {
    return init_video_stream_result_error_stream_format_resent(env);
  }

  video_stream = avformat_new_stream(state->output_ctx, NULL);
  if (!video_stream) {
    return unifex_raise(env, "Failed allocation video stream");
  }
  state->video_stream_index = video_stream->index;

  video_stream->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
  video_stream->codecpar->codec_id = AV_CODEC_ID_H264;
  video_stream->codecpar->width = width;
  video_stream->codecpar->height = height;

  video_stream->codecpar->extradata_size = avc_config->size;
  video_stream->codecpar->extradata =
      (uint8_t *)av_malloc(avc_config->size + AV_INPUT_BUFFER_PADDING_SIZE);
  if (!video_stream->codecpar->extradata) {
    return unifex_raise(env,
                        "Failed allocating video stream configuration data");
  }
  memcpy(video_stream->codecpar->extradata, avc_config->data, avc_config->size);

  bool ready = is_ready(state);
  if (ready && !state->header_written) {
    if (avformat_write_header(state->output_ctx, NULL) < 0) {
      return unifex_raise(env, "Failed writing header");
    }
    state->header_written = true;
  }
  return init_video_stream_result_ok(env, ready, state);
}

UNIFEX_TERM init_audio_stream(UnifexEnv *env, State *state, int channels,
                              int sample_rate, UnifexPayload *aac_config) {
  AVStream *audio_stream;
  if (state->audio_stream_index != -1) {
    return init_audio_stream_result_error_stream_format_resent(env);
  }

  audio_stream = avformat_new_stream(state->output_ctx, NULL);
  if (!audio_stream) {
    return unifex_raise(env, "Failed allocating audio stream");
  }
  state->audio_stream_index = audio_stream->index;

  AVChannelLayout *channel_layout = malloc(sizeof *channel_layout);
  if (!channel_layout) {
    return unifex_raise(env, "Failed allocating channel layout");
  }
  av_channel_layout_default(channel_layout, channels);

  audio_stream->codecpar->codec_type = AVMEDIA_TYPE_AUDIO;
  audio_stream->codecpar->codec_id = AV_CODEC_ID_AAC;
  audio_stream->codecpar->sample_rate = sample_rate;
  audio_stream->codecpar->ch_layout = *channel_layout;
  audio_stream->codecpar->extradata_size = aac_config->size;
  audio_stream->codecpar->extradata =
      (uint8_t *)av_malloc(aac_config->size + AV_INPUT_BUFFER_PADDING_SIZE);

  if (!audio_stream->codecpar->extradata) {
    return unifex_raise(env, "Failed allocating audio stream extradata");
  }
  memcpy(audio_stream->codecpar->extradata, aac_config->data, aac_config->size);

  bool ready = is_ready(state);
  if (ready && !state->header_written) {
    if (avformat_write_header(state->output_ctx, NULL) < 0) {
      return unifex_raise(env, "Failed writing header");
    }
    state->header_written = true;
  }
  return init_audio_stream_result_ok(env, ready, state);
}

UNIFEX_TERM write_video_frame(UnifexEnv *env, State *state,
                              UnifexPayload *frame, int64_t dts, int64_t pts,
                              int is_key_frame) {
  if (state->video_stream_index == -1) {
    return write_video_frame_result_error(
        env,
        "Video stream is not initialized. Stream format has not been received");
  }

  AVRational video_stream_time_base =
      state->output_ctx->streams[state->video_stream_index]->time_base;
  AVPacket *packet = av_packet_alloc();

  uint8_t *data = (uint8_t *)av_malloc(frame->size);
  memcpy(data, frame->data, frame->size);
  av_packet_from_data(packet, data, frame->size);

  UNIFEX_TERM write_frame_result;

  if (is_key_frame) {
    packet->flags |= AV_PKT_FLAG_KEY;
  }

  packet->stream_index = state->video_stream_index;

  if (!packet->data) {
    write_frame_result =
        unifex_raise(env, "Failed allocating video frame data");
    goto end;
  }

  int64_t dts_scaled =
      av_rescale_q(dts, MEMBRANE_TIME_BASE, video_stream_time_base);
  int64_t pts_scaled =
      av_rescale_q(pts, MEMBRANE_TIME_BASE, video_stream_time_base);
  packet->dts = dts_scaled;
  packet->pts = pts_scaled;

  packet->duration = dts_scaled - state->current_video_dts;
  state->current_video_dts = dts_scaled;

  int result = av_write_frame(state->output_ctx, packet);

  if (result) {
    write_frame_result =
        write_video_frame_result_error(env, av_err2str(result));
    goto end;
  }
  write_frame_result = write_video_frame_result_ok(env, state);

end:
  av_packet_free(&packet);
  return write_frame_result;
}

UNIFEX_TERM write_audio_frame(UnifexEnv *env, State *state,
                              UnifexPayload *frame, int64_t pts) {
  if (state->audio_stream_index == -1) {
    return write_audio_frame_result_error(
        env, "Audio stream has not been initialized. Stream format has not "
             "been received");
  }

  AVRational audio_stream_time_base =
      state->output_ctx->streams[state->audio_stream_index]->time_base;
  AVPacket *packet = av_packet_alloc();

  uint8_t *data = (uint8_t *)av_malloc(frame->size);
  memcpy(data, frame->data, frame->size);
  av_packet_from_data(packet, data, frame->size);

  UNIFEX_TERM write_frame_result;

  packet->stream_index = state->audio_stream_index;

  if (!packet->data) {
    write_frame_result =
        unifex_raise(env, "Failed allocating audio frame data.");
    goto end;
  }

  int64_t pts_scaled =
      av_rescale_q(pts, MEMBRANE_TIME_BASE, audio_stream_time_base);
  // Packet DTS is set to PTS since AAC buffers do not contain DTS
  packet->dts = pts_scaled;
  packet->pts = pts_scaled;

  packet->duration = pts_scaled - state->current_audio_pts;
  state->current_audio_pts = pts_scaled;

  int result = av_write_frame(state->output_ctx, packet);

  if (result) {
    write_frame_result =
        write_audio_frame_result_error(env, av_err2str(result));
    goto end;
  }
  write_frame_result = write_audio_frame_result_ok(env, state);

end:
  av_packet_free(&packet);
  return write_frame_result;
}

void handle_init_state(State *state) {
  state->video_stream_index = -1;
  state->current_video_dts = 0;

  state->audio_stream_index = -1;
  state->current_audio_pts = 0;

  state->header_written = false;
  state->closed = false;

  state->output_ctx = NULL;
}

void handle_destroy_state(UnifexEnv *env, State *state) {
  UNIFEX_UNUSED(env);
  if (!state->closed)
    flush_and_close_stream(env, state);
}

bool is_ready(State *state) {
  return (!state->audio_present || state->audio_stream_index != -1) &&
         (!state->video_present || state->video_stream_index != -1);
}
