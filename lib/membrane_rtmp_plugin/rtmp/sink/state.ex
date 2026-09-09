defmodule Membrane.RTMP.Sink.State do
  @moduledoc false

  alias Membrane.{Buffer, Pad}

  @enforce_keys [
    :rtmp_url,
    :max_attempts,
    :tracks,
    :reset_timestamps,
    :frame_buffer,
    :forward_mode?
  ]
  defstruct @enforce_keys ++ [attempts: 0, native: nil, ready?: false, video_base_dts: nil]

  @type t :: %__MODULE__{
          rtmp_url: String.t(),
          max_attempts: pos_integer() | :infinity,
          tracks: [Membrane.RTMP.Sink.track_type()],
          reset_timestamps: boolean(),
          attempts: non_neg_integer(),
          native: reference() | nil,
          # Keys are the pad references, values are buffers waiting to be interleaved.
          frame_buffer: %{Pad.ref() => Buffer.t() | nil},
          ready?: boolean(),
          # Activated when one of the source inputs gets closed. Interleaving is
          # disabled, frame buffer is flushed and from that point buffers on the
          # remaining pad are simply forwarded to the output.
          # Always on if a single track is connected.
          forward_mode?: boolean(),
          video_base_dts: Membrane.Time.t() | nil
        }
end
