defmodule Membrane.RTMP.Mixfile do
  use Mix.Project

  @version "0.28.1"
  @github_url "https://github.com/membraneframework/membrane_rtmp_plugin"

  def project do
    [
      app: :membrane_rtmp_plugin,
      version: @version,
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:unifex, :bundlex] ++ Mix.compilers() ++ maybe_add_rambo(),
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
      extra_applications: [:ssl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 1.0"},
      {:unifex, "~> 1.2"},
      {:membrane_precompiled_dependency_provider, "~> 0.1.0"},
      {:membrane_h26x_plugin, "~> 0.10.0"},
      {:membrane_h264_format, "~> 0.6.1"},
      {:membrane_aac_plugin, "~> 0.19.0"},
      {:membrane_flv_plugin, "~> 0.12.0"},
      {:membrane_file_plugin, "~> 0.17.0"},
      {:membrane_funnel_plugin, "~> 0.9.0"},
      # testing
      {:membrane_hackney_plugin, "~> 0.11.0", only: :test},
      {:ffmpex, "~> 0.11.0", only: :test},
      {:membrane_stream_plugin, "~> 0.4.0", only: :test},
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

  # for Mac M1 it is necessary to include rambo compiler (used by :ffmpex)
  def maybe_add_rambo() do
    if Mix.env() == :test, do: [:rambo], else: []
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
