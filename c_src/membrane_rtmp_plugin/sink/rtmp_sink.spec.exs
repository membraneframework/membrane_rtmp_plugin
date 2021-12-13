module Membrane.RTMP.Sink.Native

state_type "State"
interface [NIF]

spec init_connection(rtmp_url :: string) :: {:ok :: label, state} | {:error :: label, reason :: string}
spec close_connection(state) :: {:ok :: label} | {:error :: label, reason :: string}

spec init_video_stream(state, width :: int, height :: int, avc_config :: payload) :: {:ok :: label, ready :: bool, state} | {:error :: label, reason :: string}
spec write_video_frame(state, frame :: payload, dts :: int64, is_key_frame :: bool) :: {:ok :: label, state} | {:error :: label, reason :: string}

spec init_audio_stream(state, channels :: int, sample_rate :: int, aac_config :: payload) :: {:ok :: label, ready :: bool, state} | {:error :: label, reason :: string}
spec write_audio_frame(state, frame :: payload, pts :: int64) :: {:ok :: label, state} | {:error :: label, reason :: string}

spec write_header(state) :: {:ok :: label, state} | {:error :: label, reason :: string}
