defmodule Membrane.RTMP.BundlexProject do
  use Bundlex.Project

  defp get_ffmpeg_url() do
    membrane_precompiled_url_prefix =
      "https://github.com/membraneframework-precompiled/precompiled_ffmpeg/releases/latest/download/ffmpeg"

    case Bundlex.get_target() do
      %{os: "linux"} ->
        {:precompiled,
         "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n6.0-latest-linux64-gpl-shared-6.0.tar.xz"}

      %{architecture: "x86_64", os: "darwin" <> _rest_of_os_name} ->
        {:precompiled, "#{membrane_precompiled_url_prefix}_macos_intel.tar.gz"}

      %{architecture: "aarch64", os: "darwin" <> _rest_of_os_name} ->
        {:precompiled, "#{membrane_precompiled_url_prefix}_macos_arm.tar.gz"}

      _other ->
        nil
    end
  end

  def project do
    [
      natives: natives(Bundlex.platform())
    ]
  end

  defp natives(_platform) do
    [
      rtmp_sink: [
        sources: ["sink/rtmp_sink.c"],
        deps: [unifex: :unifex],
        interface: [:nif],
        preprocessor: Unifex,
        os_deps: [{[get_ffmpeg_url(), :pkg_config], ["libavformat", "libavutil"]}]
      ]
    ]
  end
end
