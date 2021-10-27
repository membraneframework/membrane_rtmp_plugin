module Membrane.RTMP.Source.Native

state_type "State"
interface [NIF]

spec native_create(string, timeout :: string) :: {:ok :: label, state} | {:error :: label, reason :: string}
spec stop_streaming(state) :: (:ok :: label) | {:error :: label, reason :: string}
spec stream_frames(state) :: (:ok :: label) | {:error :: label, reason :: string}

sends {:audio_params :: label, data :: payload}
sends {:audio :: label, data :: payload}

sends {:video_params :: label, data :: payload}
sends {:video :: label, data :: payload}

sends (:end_of_stream :: label)
