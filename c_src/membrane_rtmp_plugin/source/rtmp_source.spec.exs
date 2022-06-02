module Membrane.RTMP.Source.Native

state_type "State"
interface [NIF]

spec create() :: {:ok :: label, state}

spec await_open(state, url :: string, timeout :: int) ::
       {:ok :: label, state}
       | {:error :: label, :timeout :: label}
       | {:error :: label, :interrupted :: label}
       | {:error :: label, reason :: string}

spec get_video_params(state) :: {:ok :: label, params :: payload} | {:error :: label, :no_stream}
spec get_audio_params(state) :: {:ok :: label, params :: payload} | {:error :: label, :no_stream}

spec set_terminate(state) :: :ok :: label

spec read_frame(state) ::
       {:ok, :audio :: label, pts :: int64, dts :: int64, frame :: payload}
       | {:ok, :video :: label, pts :: int64, dts :: int64, frame :: payload}
       | {:error :: label, reason :: string}
       | (:end_of_stream :: label)

dirty :io, await_open: 3, read_frame: 1
