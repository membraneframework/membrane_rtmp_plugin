module Membrane.RTMP.Sink.Native

state_type "State"
interface [NIF]

spec create(rtmp_url :: string) :: {:ok :: label, state} | {:error :: label, reason :: string}
# WARN: connect will conflict with POSIX function name
spec try_connect(state) ::
       (:ok :: label)
       | {:error :: label, :econnrefused :: label}
       | {:error :: label, reason :: string}

spec finalize_stream(state) :: :ok :: label

spec init_video_stream(state, width :: int, height :: int, avc_config :: payload) ::
       {:ok :: label, ready :: bool, state} | {:error :: label, :caps_resent :: label}

spec write_video_frame(state, frame :: payload, dts :: int64, is_key_frame :: bool) ::
       {:ok :: label, state} | {:error :: label, reason :: string}

spec init_audio_stream(state, channels :: int, sample_rate :: int, aac_config :: payload) ::
       {:ok :: label, ready :: bool, state} | {:error :: label, :caps_resent :: label}

spec write_audio_frame(state, frame :: payload, pts :: int64) ::
       {:ok :: label, state} | {:error :: label, reason :: string}

dirty :io, write_video_frame: 4, write_audio_frame: 3
