defmodule Membrane.RTMP.Handshake do
  @moduledoc false

  alias Membrane.RTMP.Handshake.Step

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
  Initializes handshake process on a server side.
  """
  @spec init_server() :: State.t()
  def init_server() do
    %State{step: nil}
  end

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
  Returns how many bytes the next handshake step should consist of.
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
