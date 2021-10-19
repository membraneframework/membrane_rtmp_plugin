defmodule Membrane.RTMP.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/membraneframework/membrane_rtmp_plugin"

  def project do
    [
      app: :membrane_rtmp_plugin,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # hex
      description: "RTMP Plugin for Membrane Multimedia Framework",
      package: package(),

      # docs
      name: "Membrane RTMP plugin",
      source_url: @github_url,
      homepage_url: "https://membraneframework.org",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 0.7.0"},
      {:unifex, "~> 0.7.0"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.5", runtime: false},
      {:membrane_file_plugin, "~> 0.6"},
      {:membrane_aac_format, "~> 0.3"},
      {:membrane_element_fake, "~> 0.5"},
      {:membrane_h264_ffmpeg_plugin,
       github: "membraneframework/membrane_h264_ffmpeg_plugin", override: true},
      {:membrane_aac_plugin,
       github: "membraneframework/membrane_aac_plugin", branch: "support-none-encapsulation"},
      {:ffmpex, "~> 0.7", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache 2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.Template]
    ]
  end
end
