module Membrane.RTMP.Native

state_type "State"
interface ["NIF"]

spec create(string) :: {:ok :: label, state} | {:error :: label, reason :: string}
spec stream_frames(state) :: (:ok :: label) | {:error :: label, reason :: string}
spec stop_streaming(state) :: (:ok :: label) | {:error :: label, reason :: string}

sends {:frame :: label, data :: payload}
sends (:end_of_stream :: label)
