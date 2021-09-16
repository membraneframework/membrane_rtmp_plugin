defmodule Membrane.RTMP.BundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives(Bundlex.platform())
    ]
  end

  defp natives(_platform) do
    [
      rtmp: [
        sources: ["rtmp.c"],
        deps: [unifex: :unifex],
        interface: [:nif],
        preprocessor: Unifex,
        libs: ["avformat", "avutil"]
      ]
    ]
  end
end
