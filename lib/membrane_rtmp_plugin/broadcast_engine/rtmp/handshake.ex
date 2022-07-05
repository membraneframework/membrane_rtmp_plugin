defmodule BroadcastEngine.RTMP.Handshake do
  @moduledoc """
  RTMP handshake structure and utility functions.

  The handshake procedure is described [at](https://rtmp.veriskope.com/docs/spec/#52handshake).
  """

  defmodule Step do
    @moduledoc """
    Structure representing a single handshake step.
    """

    @enforce_keys [:data, :type]
    defstruct @enforce_keys

    @typedoc """
    RTMP handshake types.

    The handshake flow between client and server looks as follows:

     +-------------+                            +-------------+
     |   Client    |        TCP/IP Network      |    Server   |
     +-------------+             |              +-------------+
            |                    |                     |
     Uninitialized               |               Uninitialized
            |           C0       |                     |
            |------------------->|         C0          |
            |                    |-------------------->|
            |           C1       |                     |
            |------------------->|         S0          |
            |                    |<--------------------|
            |                    |         S1          |
      Version sent               |<--------------------|
            |           S0       |                     |
            |<-------------------|                     |
            |           S1       |                     |
            |<-------------------|                Version sent
            |                    |         C1          |
            |                    |-------------------->|
            |           C2       |                     |
            |------------------->|         S2          |
            |                    |<--------------------|
         Ack sent                |                  Ack Sent
            |           S2       |                     |
            |<-------------------|                     |
            |                    |         C2          |
            |                    |-------------------->|
      Handshake Done             |              Handshake Done
            |                    |                     |

    Where `C0` and `S0` are RTMP protocol version (set to 0x03).

    Both sides exchange random chunks of 1536 bytes and the other side is supposed to
    respond with those bytes remaining unchanged.

    In case of `S1` and `S2`, the latter is supposed to be equal to `C1` while
    the client has to respond by sending `C2` with the `S1` as the value.
    """
    @type handshake_type_t :: :c0_c1 | :s0_s1_s2 | :c2

    @type t :: %__MODULE__{
            data: binary(),
            type: handshake_type_t()
          }

    @rtmp_version 0x03

    @handshake_size 1536
    @s1_s2_size 2 * @handshake_size

    defmacrop invalid_step_error(type) do
      quote do
        {:error, {:invalid_handshake_step, unquote(type)}}
      end
    end

    @doc """
    Serializes the step.
    """
    @spec serialize(t()) :: binary()
    def serialize(%__MODULE__{type: type, data: data}) when type in [:c0_c1, :s0_s1_s2] do
      <<@rtmp_version, data::binary>>
    end

    def serialize(%__MODULE__{data: data}), do: data

    @doc """
    Deserializes the handshake step given the type.
    """
    @spec deserialize(handshake_type_t(), binary()) ::
            {:ok, t()} | {:error, :invalid_handshake_step}
    def deserialize(:c0_c1 = type, <<0x03, data::binary-size(@handshake_size)>>) do
      {:ok, %__MODULE__{type: type, data: data}}
    end

    def deserialize(:s0_s1_s2 = type, <<0x03, data::binary-size(@s1_s2_size)>>) do
      {:ok, %__MODULE__{type: type, data: data}}
    end

    def deserialize(:c2 = type, <<data::binary-size(@handshake_size)>>) do
      {:ok, %__MODULE__{type: type, data: data}}
    end

    def deserialize(_type, _data), do: {:error, :invalid_handshake_step}

    @doc """
    Verifies if the following handshake step matches the previous one.

    C1 should have the same value as S2 and C2 be the same as  S1.
    """
    @spec verify_next_step(t() | nil, t()) ::
            :ok | {:error, {:invalid_handshake_step, handshake_type_t()}}
    def verify_next_step(previous_step, next_step)

    def verify_next_step(nil, %Step{type: :c0_c1}), do: :ok

    def verify_next_step(%Step{type: :c0_c1, data: c1}, %Step{type: :s0_s1_s2, data: s1_s2}) do
      <<_s1::binary-size(@handshake_size), s2::binary-size(@handshake_size)>> = s1_s2

      if s2 == c1 do
        :ok
      else
        invalid_step_error(:s0_s1_s2)
      end
    end

    def verify_next_step(%Step{type: :s0_s1_s2, data: s1_s2}, %Step{type: :c2, data: c2}) do
      <<s1::binary-size(@handshake_size), _s2::binary>> = s1_s2

      if c2 == s1 do
        :ok
      else
        invalid_step_error(:c2)
      end
    end

    @doc """
    Returns epoch timestamp of the connection. 
    """
    @spec epoch(t()) :: non_neg_integer()
    def epoch(%__MODULE__{data: <<epoch::32, _rest::binary>>}), do: epoch
  end

  defmodule State do
    @moduledoc false

    @enforce_keys [:step]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            step: Step.t() | nil
          }
  end

  @handshake_size 1536

  @doc """
  Initializes handshake process as a server. 
  """
  @spec init_server() :: State.t()
  def init_server() do
    %State{step: nil}
  end

  Spec

  @doc """
  Initializes handshake process as a client. 
  """
  @spec init_client(non_neg_integer()) :: {Step.t(), State.t()}
  def init_client(epoch) do
    step = %Step{type: :c0_c1, data: generate_c1_s1(epoch)}

    {step, %State{step: step}}
  end

  @spec handle_step(binary(), State.t()) ::
          {:ok | :cont, Step.t(), State.t()}
          | {:ok, State.t()}
          | {:error, {:invalid_handshake_step, Step.handshake_type_t()}}
  def handle_step(step_data, state)

  def handle_step(step_data, %State{step: %Step{type: :c0_c1} = previous_step}) do
    with {:ok, next_step} <- Step.deserialize(:s0_s1_s2, step_data),
         :ok <- Step.verify_next_step(previous_step, next_step) do
      <<s1::binary-size(@handshake_size), _s2::binary>> = next_step.data

      step = %Step{type: :c2, data: s1}

      {:ok, step, %State{step: step}}
    end
  end

  def handle_step(step_data, %State{step: %Step{type: :s0_s1_s2} = previous_step}) do
    with {:ok, next_step} <- Step.deserialize(:c2, step_data),
         :ok <- Step.verify_next_step(previous_step, next_step) do
      {:ok, %State{step: next_step}}
    end
  end

  def handle_step(step_data, %State{step: nil}) do
    with {:ok, %Step{data: c1}} <- Step.deserialize(:c0_c1, step_data) do
      <<time::32, _rest::binary>> = c1

      step = %Step{
        type: :s0_s1_s2,
        data: generate_c1_s1(time) <> c1
      }

      {:cont, step, %State{step: step}}
    end
  end

  @doc """
  Retrns how many bytes the next handshake step should consist of.
  """
  @spec expects_bytes(State.t()) :: non_neg_integer()
  def expects_bytes(%State{step: step}) do
    case step do
      # expect c0 + c1
      nil ->
        @handshake_size + 1

      # expect s0 + s1 + s2
      %Step{type: :c0_c1} ->
        2 * @handshake_size + 1

      # expect c2
      %Step{type: :s0_s1_s2} ->
        @handshake_size
    end
  end

  # generates a unique segment of the handshake's step
  # accordingly to the spec first 4 bytes are a connection epoch time,
  # followed by 4 zero bytes and 1526 random bytes 
  defp generate_c1_s1(epoch) do
    <<epoch::32, 0::32, :crypto.strong_rand_bytes(@handshake_size - 8)::binary>>
  end
end
