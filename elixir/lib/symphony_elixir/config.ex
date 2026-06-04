defmodule SymphonyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.
  """

  alias SymphonyElixir.Config.Schema
  alias SymphonyElixir.Workflow

  @default_prompt_template """
  You are working on a Linear issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @type codex_runtime_settings :: %{
          approval_policy: String.t() | map(),
          thread_sandbox: String.t(),
          turn_sandbox_policy: map()
        }

  @spec settings() :: {:ok, Schema.t()} | {:error, term()}
  def settings do
    case Workflow.current() do
      {:ok, %{config: config}} when is_map(config) ->
        Schema.parse(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec settings!() :: Schema.t()
  def settings! do
    case settings() do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        raise ArgumentError, message: format_config_error(reason)
    end
  end

  @spec max_concurrent_agents_for_state(term()) :: pos_integer()
  def max_concurrent_agents_for_state(state_name) when is_binary(state_name) do
    config = settings!()

    Map.get(
      config.agent.max_concurrent_agents_by_state,
      Schema.normalize_issue_state(state_name),
      config.agent.max_concurrent_agents
    )
  end

  def max_concurrent_agents_for_state(_state_name), do: settings!().agent.max_concurrent_agents

  @spec agent_runtime() :: :codex | :claude | :cursor | :gemini
  @spec agent_runtime(term()) :: :codex | :claude | :cursor | :gemini
  def agent_runtime(issue \\ nil) do
    settings = settings!()

    issue
    |> issue_label_runtime(settings)
    |> case do
      nil -> default_agent_runtime(settings)
      runtime -> runtime
    end
  end

  defp issue_label_runtime(nil, _settings), do: nil

  defp issue_label_runtime(%{labels: labels}, settings) when is_list(labels) do
    label_map = settings.agent.runtime_by_label || %{}

    labels
    |> Enum.map(&Schema.normalize_label/1)
    |> Enum.find_value(fn label ->
      case Map.get(label_map, label) do
        "codex" -> :codex
        "claude" -> :claude
        "cursor" -> :cursor
        "gemini" -> :gemini
        _ -> nil
      end
    end)
  end

  defp issue_label_runtime(_issue, _settings), do: nil

  defp default_agent_runtime(settings) do
    case settings.agent.default_runtime do
      "codex" -> :codex
      "claude" -> :claude
      "cursor" -> :cursor
      "gemini" -> :gemini
      _ -> :codex
    end
  end

  @spec cli_agent_settings(:claude | :cursor | :gemini) :: map()
  def cli_agent_settings(:claude), do: settings!().claude
  def cli_agent_settings(:cursor), do: settings!().cursor
  def cli_agent_settings(:gemini), do: settings!().gemini

  @spec codex_turn_sandbox_policy(Path.t() | nil) :: map()
  def codex_turn_sandbox_policy(workspace \\ nil) do
    case Schema.resolve_runtime_turn_sandbox_policy(settings!(), workspace) do
      {:ok, policy} ->
        policy

      {:error, reason} ->
        raise ArgumentError, message: "Invalid codex turn sandbox policy: #{inspect(reason)}"
    end
  end

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case Workflow.current() do
      {:ok, %{prompt_template: prompt}} ->
        if String.trim(prompt) == "", do: @default_prompt_template, else: prompt

      _ ->
        @default_prompt_template
    end
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    case Application.get_env(:symphony_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 -> port
      _ -> settings!().server.port
    end
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate! do
    with {:ok, settings} <- settings() do
      validate_semantics(settings)
    end
  end

  @spec codex_runtime_settings(Path.t() | nil, keyword()) ::
          {:ok, codex_runtime_settings()} | {:error, term()}
  def codex_runtime_settings(workspace \\ nil, opts \\ []) do
    agent_app_server_settings(:codex, workspace, opts)
  end

  @spec agent_app_server_settings(:codex, Path.t() | nil, keyword()) ::
          {:ok, codex_runtime_settings()} | {:error, term()}
  def agent_app_server_settings(:codex, workspace \\ nil, opts \\ []) do
    with {:ok, settings} <- settings() do
      with {:ok, turn_sandbox_policy} <-
             Schema.resolve_runtime_turn_sandbox_policy(settings, workspace, opts) do
        {:ok,
         %{
           approval_policy: settings.codex.approval_policy,
           thread_sandbox: settings.codex.thread_sandbox,
           turn_sandbox_policy: turn_sandbox_policy
         }}
      end
    end
  end

  defp validate_semantics(settings) do
    with :ok <- validate_tracker(settings),
         :ok <- validate_cli_runtime_commands(settings) do
      :ok
    end
  end

  defp validate_tracker(settings) do
    cond do
      is_nil(settings.tracker.kind) ->
        {:error, :missing_tracker_kind}

      settings.tracker.kind not in ["linear", "memory"] ->
        {:error, {:unsupported_tracker_kind, settings.tracker.kind}}

      settings.tracker.kind == "linear" and not is_binary(settings.tracker.api_key) ->
        {:error, :missing_linear_api_token}

      settings.tracker.kind == "linear" and not is_binary(settings.tracker.project_slug) ->
        {:error, :missing_linear_project_slug}

      true ->
        :ok
    end
  end

  defp validate_cli_runtime_commands(settings) do
    settings
    |> configured_cli_runtimes()
    |> Enum.find_value(fn runtime ->
      case cli_runtime_command(settings, runtime) do
        command when is_binary(command) and command != "" ->
          nil

        _ ->
          {:error, {:missing_cli_runtime_command, runtime}}
      end
    end)
    |> case do
      nil -> :ok
      error -> error
    end
  end

  defp configured_cli_runtimes(settings) do
    label_runtimes =
      (settings.agent.runtime_by_label || %{})
      |> Map.values()
      |> Enum.map(&runtime_atom/1)
      |> Enum.filter(&(&1 in [:claude, :cursor, :gemini]))

    default_runtime = default_agent_runtime(settings)

    if default_runtime in [:claude, :cursor, :gemini] do
      Enum.uniq([default_runtime | label_runtimes])
    else
      Enum.uniq(label_runtimes)
    end
  end

  defp cli_runtime_command(settings, :claude), do: settings.claude.command
  defp cli_runtime_command(settings, :cursor), do: settings.cursor.command
  defp cli_runtime_command(settings, :gemini), do: settings.gemini.command

  defp runtime_atom("codex"), do: :codex
  defp runtime_atom("claude"), do: :claude
  defp runtime_atom("cursor"), do: :cursor
  defp runtime_atom("gemini"), do: :gemini
  defp runtime_atom(_), do: nil

  defp format_config_error(reason) do
    case reason do
      {:invalid_workflow_config, message} ->
        "Invalid WORKFLOW.md config: #{message}"

      {:missing_workflow_file, path, raw_reason} ->
        "Missing WORKFLOW.md at #{path}: #{inspect(raw_reason)}"

      {:workflow_parse_error, raw_reason} ->
        "Failed to parse WORKFLOW.md: #{inspect(raw_reason)}"

      :workflow_front_matter_not_a_map ->
        "Failed to parse WORKFLOW.md: workflow front matter must decode to a map"

      {:missing_cli_runtime_command, runtime} ->
        "Missing WORKFLOW.md #{runtime} command for configured CLI runtime"

      other ->
        "Invalid WORKFLOW.md config: #{inspect(other)}"
    end
  end
end
