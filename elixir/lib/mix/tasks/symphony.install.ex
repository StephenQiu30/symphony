defmodule Mix.Tasks.Symphony.Install do
  @shortdoc "Install Symphony helper scripts into ~/.local/bin"
  @moduledoc """
  Symlinks executable scripts from the repository `scripts/` directory into
  `~/.local/bin` so workflow configs can reference stable command names such as
  `cursor-symphony-bridge` without machine-specific absolute paths.

      $ mix symphony.install

  The task is idempotent. Existing symlinks are updated when they point
  elsewhere; regular files are left untouched.
  """

  use Mix.Task

  @install_dir Path.expand("~/.local/bin")

  @impl Mix.Task
  def run(_args) do
    scripts_dir =
      __DIR__
      |> Path.join("../../../../scripts")
      |> Path.expand()

    unless File.dir?(scripts_dir) do
      Mix.raise("scripts/ directory not found at #{scripts_dir}")
    end

    File.mkdir_p!(@install_dir)

    scripts_dir
    |> File.ls!()
    |> Enum.filter(fn name ->
      path = Path.join(scripts_dir, name)
      File.regular?(path) and not String.starts_with?(name, ".")
    end)
    |> Enum.each(&install_script(scripts_dir, &1))

    Mix.shell().info("\nSymphony scripts installed to #{@install_dir}")
  end

  defp install_script(scripts_dir, name) do
    source = Path.join(scripts_dir, name)
    target = Path.join(@install_dir, name)

    case File.read_link(target) do
      {:ok, ^source} ->
        Mix.shell().info("  already linked: #{name}")

      {:ok, _old_source} ->
        File.rm!(target)
        File.ln_s!(source, target)
        Mix.shell().info("  updated link:   #{name} -> #{source}")

      {:error, _reason} ->
        link_new_script(name, source, target)
    end
  end

  defp link_new_script(name, source, target) do
    if File.exists?(target) do
      Mix.shell().error("  skipped:        #{name} (#{target} exists and is not a symlink)")
    else
      File.ln_s!(source, target)
      Mix.shell().info("  linked:         #{name} -> #{source}")
    end
  end
end
