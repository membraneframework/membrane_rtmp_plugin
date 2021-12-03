module Membrane.RTMP.Sink.Native

state_type "State"
interface [NIF]

spec init_connection(rtmp_url :: string) :: {:ok :: label, state} | {:error :: label, reason :: string}
spec close_connection(state) :: {:ok :: label} | {:error :: label, reason :: string}

spec init_video_stream(state, width :: int, height :: int, frames :: int, seconds :: int) :: {:ok :: label, state} | {:error :: label, reason :: string}
spec write_video_frame(state, frame :: payload) :: {:ok :: label, state} | {:error :: label, reason :: string}

