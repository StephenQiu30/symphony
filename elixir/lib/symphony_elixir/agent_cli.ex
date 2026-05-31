defmodule SymphonyElixir.AgentCli do
  @moduledoc """
  Runs a single CLI-based agent turn for workflows that declare a CLI runtime.
  """

  require Logger
  alias SymphonyElixir.{Config, SSH}

  @port_line_bytes 1_048_576

  @type runtime :: :claude | :cursor
  @type worker_host :: String.t() | nil

  @spec run(runtime(), Path.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(runtime, workspace, prompt, issue, opts \\ []) when runtime in [:claude, :cursor] do
    worker_host = Keyword.get(opts, :worker_host)
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    session_id = "#{runtime}-#{System.unique_integer([:positive])}"
    metadata = %{cli_agent_runtime: to_string(runtime), cli_agent_session_id: session_id}

    emit_message(
      on_message,
      :session_started,
      %{
        session_id: session_id,
        thread_id: session_id,
        turn_id: "turn-1"
      },
      metadata
    )

    Logger.info("#{runtime} CLI session started for #{issue_context(issue)} session_id=#{session_id}")

    case start_port(runtime, workspace, prompt, worker_host) do
      {:ok, port} ->
        try do
          await_completion(runtime, port, on_message, session_id, metadata)
        after
          stop_port(port)
        end

      {:error, reason} ->
        emit_message(on_message, :startup_failed, %{reason: reason}, metadata)
        {:error, reason}
    end
  end

  defp start_port(runtime, workspace, prompt, nil) do
    executable = System.find_executable("bash")

    if is_nil(executable) do
      {:error, :bash_not_found}
    else
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(executable)},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: [~c"-c", String.to_charlist(shell_script(runtime, workspace, prompt))],
            cd: String.to_charlist(workspace),
            line: @port_line_bytes
          ]
        )

      {:ok, port}
    end
  end

  defp start_port(runtime, workspace, prompt, worker_host) when is_binary(worker_host) do
    SSH.start_port(worker_host, shell_script(runtime, workspace, prompt), line: @port_line_bytes)
  end

  defp shell_script(runtime, workspace, prompt) do
    settings = Config.cli_agent_settings(runtime)
    encoded_prompt = Base.encode64(prompt)

    [
      "set -eu",
      "cd #{shell_escape(workspace)}",
      "prompt_file=$(mktemp .symphony-#{runtime}-prompt.XXXXXX)",
      "trap 'rm -f \"$prompt_file\"' EXIT",
      "base64 -d > \"$prompt_file\" <<'__SYMPHONY_AGENT_PROMPT__'",
      encoded_prompt,
      "__SYMPHONY_AGENT_PROMPT__",
      launch_command(runtime, settings)
    ]
    |> Enum.join("\n")
  end

  defp launch_command(runtime, %{command: command, prompt_mode: "argument"}) do
    "#{headless_command(runtime, command)} \"$(cat \"$prompt_file\")\""
  end

  defp launch_command(runtime, %{command: command}) do
    "#{headless_command(runtime, command)} < \"$prompt_file\""
  end

  defp headless_command(:claude, command) when is_binary(command) do
    command
    |> ensure_flag(~r/(^|\s)(-p|--print)(\s|$)/, "-p")
    |> ensure_claude_streaming_output()
    |> ensure_flag(~r/(^|\s)--verbose(\s|$)/, "--verbose")
  end

  defp headless_command(:cursor, command) when is_binary(command) do
    ensure_flag(command, ~r/(^|\s)(-p|--print)(\s|$)/, "-p")
  end

  defp ensure_flag(command, pattern, flag) when is_binary(command) and is_binary(flag) do
    if Regex.match?(pattern, command) do
      command
    else
      command <> " " <> flag
    end
  end

  defp ensure_claude_streaming_output(command) when is_binary(command) do
    cond do
      Regex.match?(~r/(^|\s)--output-format[=\s]stream-json(\s|$)/, command) ->
        ensure_flag(command, ~r/(^|\s)--include-partial-messages(\s|$)/, "--include-partial-messages")

      Regex.match?(~r/(^|\s)--output-format(\s|=)/, command) ->
        command

      true ->
        command <> " --output-format stream-json --include-partial-messages"
    end
  end

  defp await_completion(runtime, port, on_message, session_id, metadata) do
    receive_loop(
      runtime,
      port,
      on_message,
      session_id,
      metadata,
      Config.cli_agent_settings(runtime).turn_timeout_ms,
      ""
    )
  end

  defp receive_loop(runtime, port, on_message, session_id, metadata, timeout_ms, pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        line = pending_line <> to_string(chunk)
        emit_cli_line(runtime, on_message, line, metadata)
        receive_loop(runtime, port, on_message, session_id, metadata, timeout_ms, "")

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(runtime, port, on_message, session_id, metadata, timeout_ms, pending_line <> to_string(chunk))

      {^port, {:exit_status, 0}} ->
        if pending_line != "" do
          emit_message(on_message, :notification, %{payload: pending_line, raw: pending_line}, metadata)
        end

        emit_message(on_message, :turn_completed, %{session_id: session_id}, metadata)
        {:ok, %{result: :turn_completed, session_id: session_id, thread_id: session_id, turn_id: "turn-1"}}

      {^port, {:exit_status, status}} ->
        {:error, {:cli_agent_exit, runtime, status}}
    after
      timeout_ms ->
        {:error, :turn_timeout}
    end
  end

  defp emit_message(on_message, event, payload, metadata) do
    message =
      metadata
      |> Map.merge(%{event: event, timestamp: DateTime.utc_now()})
      |> Map.merge(payload)

    on_message.(message)
  end

  defp emit_cli_line(:claude, on_message, line, metadata) do
    case Jason.decode(line) do
      {:ok, payload} -> emit_message(on_message, :notification, %{payload: payload, raw: line}, metadata)
      {:error, _reason} -> emit_message(on_message, :notification, %{payload: line, raw: line}, metadata)
    end
  end

  defp emit_cli_line(_runtime, on_message, line, metadata) do
    emit_message(on_message, :notification, %{payload: line, raw: line}, metadata)
  end

  defp stop_port(port) when is_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp default_on_message(_message), do: :ok

  defp issue_context(%{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
