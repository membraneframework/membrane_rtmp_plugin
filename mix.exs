defmodule Membrane.RTMP.Mixfile do
  use Mix.Project

  @version "0.6.0"
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
      dialyzer: dialyzer(),

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
      {:membrane_core, "~> 0.10"},
      {:unifex, "~> 1.0"},
      {:membrane_h264_ffmpeg_plugin, "~> 0.21"},
      {:membrane_aac_plugin, "~> 0.12"},
      {:membrane_mp4_plugin, "~> 0.16"},
      {:membrane_flv_plugin, "~> 0.3.0"},
      # testing
      {:membrane_hackney_plugin, "~> 0.8", only: :test},
      {:ffmpex, "~> 0.7", only: :test},
      # development
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membraneframework.org"
      },
      files: ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs", "bundlex.exs", "c_src"],
      exclude_patterns: [~r"c_src/.*/_generated.*"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [Membrane.RTMP]
    ]
  end
end
