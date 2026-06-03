defmodule SymphonyElixir.EnvFile do
  @moduledoc false

  @spec load(Path.t()) :: :ok
  def load(workflow_path) when is_binary(workflow_path) do
    workflow_path
    |> env_file_candidates()
    |> Enum.find(&File.regular?/1)
    |> case do
      nil -> :ok
      path -> load_file(path)
    end
  end

  defp env_file_candidates(workflow_path) do
    [
      Path.join(Path.dirname(workflow_path), ".env"),
      Path.join(Path.dirname(Path.dirname(workflow_path)), ".env"),
      Path.join(File.cwd!(), ".env")
    ]
    |> Enum.uniq()
  end

  defp load_file(path) do
    path
    |> File.stream!([], :line)
    |> Enum.each(&load_line/1)
  end

  defp load_line(line) do
    line = String.trim(line)

    cond do
      line == "" or String.starts_with?(line, "#") ->
        :ok

      true ->
        with [key, value] <- String.split(line, "=", parts: 2),
             key <- String.trim(key),
             true <- String.match?(key, ~r/^[A-Za-z_][A-Za-z0-9_]*$/),
             nil <- System.get_env(key) do
          System.put_env(key, parse_value(value))
        else
          _ -> :ok
        end
    end
  end

  defp parse_value(value) do
    value
    |> String.trim()
    |> strip_matching_quotes()
  end

  defp strip_matching_quotes("\"" <> value) do
    if String.ends_with?(value, "\""), do: String.slice(value, 0..-2//1), else: "\"" <> value
  end

  defp strip_matching_quotes("'" <> value) do
    if String.ends_with?(value, "'"), do: String.slice(value, 0..-2//1), else: "'" <> value
  end

  defp strip_matching_quotes(value), do: value
end
