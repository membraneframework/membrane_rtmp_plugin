module Membrane.RTMP.Native

state_type "State"
interface ["NIF"]

spec create(string) :: {:ok :: label, state} | {:error :: label, reason :: string}
spec get_frame(state :: state) :: (:ok :: label) | {:data :: label, data :: payload} | {:error :: label, reason :: string}
sends {:data :: label, data :: payload}
