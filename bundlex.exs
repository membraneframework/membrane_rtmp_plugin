defmodule Membrane.RTMP.BundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives()
    ]
  end

  defp natives() do
    [
      rtmp_sink: [
        sources: ["sink/rtmp_sink.c"],
        deps: [unifex: :unifex],
        interface: :nif,
        preprocessor: Unifex,
        os_deps: [
          ffmpeg: [
            {:precompiled, Membrane.PrecompiledDependencyProvider.get_dependency_url(:ffmpeg),
             ["libavformat", "libavutil"]},
            {:pkg_config, ["libavformat", "libavutil"]}
          ]
        ]
      ]
    ]
  end
end
