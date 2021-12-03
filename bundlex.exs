defmodule Membrane.RTMP.BundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives(Bundlex.platform())
    ]
  end

  defp natives(_platform) do
    [
      rtmp_source: [
        sources: ["source/rtmp_source.c"],
        deps: [unifex: :unifex],
        interface: [:nif],
        preprocessor: Unifex,
        pkg_configs: ["libavformat", "libavutil"]
      ],
      rtmp_sink: [
        sources: ["sink/rtmp_sink.c"],
        deps: [unifex: :unifex],
        interface: [:nif],
        preprocessor: Unifex,
        pkg_configs: ["libavformat", "libavutil"]
      ]
    ]
  end
end
