defmodule SymphonyElixir.EnvFile do
  @moduledoc false

  @spec load_for_workflow(Path.t()) :: :ok
  def load_for_workflow(workflow_path) when is_binary(workflow_path) do
    workflow_dir = workflow_path |> Path.expand() |> Path.dirname()

    [Path.join(File.cwd!(), ".env"), Path.join(workflow_dir, ".env")]
    |> Enum.uniq()
    |> Enum.each(&load/1)
  end

  @spec load(Path.t()) :: :ok
  def load(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split(~r/\R/, trim: false)
        |> Enum.each(&put_line/1)

      {:error, _reason} ->
        :ok
    end
  end

  defp put_line(line) do
    line = String.trim(line)

    cond do
      line == "" ->
        :ok

      String.starts_with?(line, "#") ->
        :ok

      true ->
        line
        |> strip_export()
        |> split_assignment()
        |> put_env()
    end
  end

  defp strip_export("export " <> rest), do: String.trim_leading(rest)
  defp strip_export(line), do: line

  defp split_assignment(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] -> {String.trim(key), normalize_value(value)}
      _ -> :skip
    end
  end

  defp normalize_value(value) do
    value
    |> String.trim()
    |> strip_inline_comment()
    |> strip_quotes()
  end

  defp strip_inline_comment(value) do
    case Regex.run(~r/\s+#/, value, return: :index) do
      [{index, _length}] -> value |> binary_part(0, index) |> String.trim_trailing()
      nil -> value
    end
  end

  defp strip_quotes("\"" <> rest) do
    if String.ends_with?(rest, "\"") do
      rest
      |> remove_last_byte()
      |> String.replace("\\\"", "\"")
    else
      "\"" <> rest
    end
  end

  defp strip_quotes("'" <> rest) do
    if String.ends_with?(rest, "'") do
      remove_last_byte(rest)
    else
      "'" <> rest
    end
  end

  defp strip_quotes(value), do: value

  defp remove_last_byte(value), do: binary_part(value, 0, byte_size(value) - 1)

  defp put_env({key, value}) do
    if valid_key?(key) and is_nil(System.get_env(key)) do
      System.put_env(key, value)
    end

    :ok
  end

  defp put_env(:skip), do: :ok

  defp valid_key?(key), do: String.match?(key, ~r/^[A-Za-z_][A-Za-z0-9_]*$/)
end
