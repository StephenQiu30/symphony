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
    |> ensure_flag(~r/(^|\s)--dangerously-skip-permissions(\s|$)/, "--dangerously-skip-permissions")
    |> ensure_claude_streaming_output()
    |> ensure_flag(~r/(^|\s)--verbose(\s|$)/, "--verbose")
  end

  defp headless_command(:cursor, command) when is_binary(command) do
    command
    |> ensure_flag(~r/(^|\s)(-p|--print)(\s|$)/, "-p")
    |> ensure_flag(~r/(^|\s)(-f|--force)(\s|$)/, "--force")
    |> ensure_flag(~r/(^|\s)--sandbox(\s|=)/, "--sandbox disabled")
    |> ensure_cursor_streaming_output()
    |> ensure_flag(~r/(^|\s)--stream-partial-output(\s|$)/, "--stream-partial-output")
    |> ensure_flag(~r/(^|\s)--approve-mcps(\s|$)/, "--approve-mcps")
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

  defp ensure_cursor_streaming_output(command) when is_binary(command) do
    cond do
      Regex.match?(~r/(^|\s)--output-format[=\s]stream-json(\s|$)/, command) ->
        command

      Regex.match?(~r/(^|\s)--output-format(\s|=)/, command) ->
        command

      true ->
        command <> " --output-format stream-json"
    end
  end

  defp await_completion(runtime, port, on_message, session_id, metadata) do
    receive_loop(
      runtime,
      port,
      on_message,
      metadata,
      Config.cli_agent_settings(runtime).turn_timeout_ms,
      "",
      %{
        session_id: session_id,
        result_payload: nil,
        failed_payload: nil
      }
    )
  end

  defp receive_loop(runtime, port, on_message, metadata, timeout_ms, pending_line, state) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        line = pending_line <> to_string(chunk)
        state = emit_cli_line(runtime, on_message, line, metadata, state)
        receive_loop(runtime, port, on_message, metadata, timeout_ms, "", state)

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(runtime, port, on_message, metadata, timeout_ms, pending_line <> to_string(chunk), state)

      {^port, {:exit_status, 0}} ->
        state =
          if pending_line != "" do
            emit_cli_line(runtime, on_message, pending_line, metadata, state)
          else
            state
          end

        complete_cli_turn(runtime, on_message, metadata, state)

      {^port, {:exit_status, status}} ->
        reason = {:cli_agent_exit, runtime, status}
        emit_message(on_message, :turn_ended_with_error, %{session_id: state.session_id, reason: reason}, metadata)
        {:error, reason}
    after
      timeout_ms ->
        emit_message(
          on_message,
          :turn_ended_with_error,
          %{session_id: state.session_id, reason: :turn_timeout},
          metadata
        )

        {:error, :turn_timeout}
    end
  end

  defp complete_cli_turn(runtime, on_message, metadata, %{failed_payload: failed_payload} = state)
       when is_map(failed_payload) do
    reason = {:cli_agent_failed, runtime, failed_payload}

    emit_message(
      on_message,
      :turn_failed,
      %{session_id: state.session_id, payload: failed_payload, reason: reason},
      metadata
    )

    {:error, reason}
  end

  defp complete_cli_turn(_runtime, on_message, metadata, state) do
    payload = state.result_payload || %{}

    completion_payload =
      payload
      |> Map.put_new("type", "result")
      |> Map.put_new("subtype", "success")
      |> Map.put("session_id", state.session_id)

    emit_message(on_message, :turn_completed, %{session_id: state.session_id, payload: completion_payload}, metadata)
    {:ok, %{result: :turn_completed, session_id: state.session_id, thread_id: state.session_id, turn_id: "turn-1"}}
  end

  defp emit_message(on_message, event, payload, metadata) do
    message =
      metadata
      |> Map.merge(%{event: event, timestamp: DateTime.utc_now()})
      |> Map.merge(payload)

    on_message.(message)
  end

  defp emit_cli_line(runtime, on_message, line, metadata, state) when runtime in [:claude, :cursor] do
    case Jason.decode(line) do
      {:ok, payload} ->
        emit_message(on_message, :notification, %{payload: payload, raw: line}, metadata)
        update_cli_state_from_payload(state, payload)

      {:error, _reason} ->
        emit_message(on_message, :notification, %{payload: line, raw: line}, metadata)
        state
    end
  end

  defp emit_cli_line(_runtime, on_message, line, metadata, state) do
    emit_message(on_message, :notification, %{payload: line, raw: line}, metadata)
    state
  end

  defp update_cli_state_from_payload(state, %{} = payload) do
    state
    |> maybe_update_cli_session_id(payload)
    |> maybe_record_cli_result(payload)
  end

  defp maybe_update_cli_session_id(state, payload) do
    case map_value(payload, ["session_id", :session_id]) do
      session_id when is_binary(session_id) and session_id != "" -> %{state | session_id: session_id}
      _ -> state
    end
  end

  defp maybe_record_cli_result(state, payload) do
    if cli_result_payload?(payload) do
      state = %{state | result_payload: payload}

      if cli_failed_result?(payload) do
        %{state | failed_payload: payload}
      else
        state
      end
    else
      state
    end
  end

  defp cli_result_payload?(payload) do
    map_value(payload, ["type", :type]) == "result"
  end

  defp cli_failed_result?(payload) do
    subtype = map_value(payload, ["subtype", :subtype])
    is_error = map_value(payload, ["is_error", :is_error])

    is_error == true or (is_binary(subtype) and subtype not in ["success", ""])
  end

  defp map_value(%{} = map, keys) when is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
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
