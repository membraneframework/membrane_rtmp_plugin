defmodule Membrane.AVC.Configuration do
  def parse(
        <<1::8, avc_profile_indication::8, profile_compatibility::8, avc_level::8, 0b111111::6,
          length_size::2, 0b111::3, rest::bitstring>>
      ) do
    {sps, rest} = parse_sps(rest)
    {pps, _rest} = parse_pps(rest)

    %{
      sps: sps,
      pps: pps,
      avc_profile_indication: avc_profile_indication,
      profile_compatibility: profile_compatibility,
      avc_level: avc_level,
      length_size: length_size
    }
  end

  def parse(data), do: {:error, data}

  defp parse_sps(<<num_of_sps::5, rest::bitstring>>) do
    do_parse_array(num_of_sps, rest)
  end

  defp parse_pps(<<num_of_pps::8, rest::bitstring>>), do: do_parse_array(num_of_pps, rest)

  defp do_parse_array(0, anything), do: {[], anything}

  defp do_parse_array(remaining, <<size::16, data::binary-size(size), rest::bitstring>>) do
    {pps, rest} = do_parse_array(remaining - 1, rest)
    {[data | pps], rest}
  end
end
