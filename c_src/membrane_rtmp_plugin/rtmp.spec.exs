module Membrane.RTMP.Source.Native

state_type "State"
interface [NIF]

spec native_create(string, timeout :: string) :: {:ok :: label, state} | {:error :: label, reason :: string}

spec get_video_params(state) :: {:ok :: label, params :: payload} | {:error :: label, :no_stream}
spec get_audio_params(state) :: {:ok :: label, params :: payload} | {:error :: label, :no_stream}
spec read_frame(state) :: {:ok, :audio :: label, frame :: payload} | {:ok, :video :: label, frame :: payload} | {:error :: label, reason :: string} | (:end_of_stream :: label)

dirty :io, native_create: 2, read_frame: 1
