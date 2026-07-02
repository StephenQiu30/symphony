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

  @type runtime :: :codex | :claude | :cursor | :antigravity

  @spec agent_runtime() :: runtime()
  @spec agent_runtime(term()) :: runtime()
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

  defp issue_label_runtime(%{labels: labels, state: state}, settings)
       when is_list(labels) and is_binary(state) do
    if Schema.normalize_issue_state(state) == "agent review" do
      reviewer_label_runtime(labels, settings) || default_reviewer_runtime(settings)
    else
      agent_label_runtime(labels, settings)
    end
  end

  defp issue_label_runtime(%{labels: labels}, settings) when is_list(labels) do
    agent_label_runtime(labels, settings)
  end

  defp issue_label_runtime(_issue, _settings), do: nil

  defp reviewer_label_runtime(labels, settings) do
    labels
    |> Enum.map(&Schema.normalize_label/1)
    |> Enum.filter(&String.starts_with?(&1, "reviewer:"))
    |> mapped_label_runtime(settings)
  end

  defp agent_label_runtime(labels, settings) do
    labels
    |> Enum.map(&Schema.normalize_label/1)
    |> Enum.filter(&String.starts_with?(&1, "agent:"))
    |> mapped_label_runtime(settings)
  end

  defp mapped_label_runtime(labels, settings) do
    label_map = settings.agent.runtime_by_label || %{}

    labels
    |> Enum.find_value(fn label ->
      case Map.get(label_map, label) do
        "codex" -> :codex
        "claude" -> :claude
        "cursor" -> :cursor

        "antigravity" -> :antigravity
        _ -> nil
      end
    end)
  end

  defp default_reviewer_runtime(settings) do
    mapped_label_runtime(["reviewer:claude"], settings)
  end

  defp default_agent_runtime(settings) do
    case settings.agent.default_runtime do
      "codex" -> :codex
      "claude" -> :claude
      "cursor" -> :cursor

      "antigravity" -> :antigravity
      _ -> :codex
    end
  end

  @spec runtime_settings(runtime()) :: map()
  def runtime_settings(:codex), do: settings!().codex
  def runtime_settings(:claude), do: settings!().claude
  def runtime_settings(:cursor), do: settings!().cursor

  def runtime_settings(:antigravity), do: settings!().antigravity

  @spec runtime_protocol(runtime()) :: String.t()
  def runtime_protocol(runtime), do: runtime_settings(runtime).protocol

  @spec agent_model(atom(), map()) :: String.t() | nil
  def agent_model(runtime, issue) do
    settings = runtime_settings(runtime)

    Enum.find_value(issue.labels, settings.model, fn label ->
      case String.split(Schema.normalize_label(label), ":", parts: 2) do
        ["model", model_name] -> String.trim(model_name)
        _ -> nil
      end
    end)
  end

  @spec codex_turn_sandbox_policy(Path.t() | nil) :: map()
  def codex_turn_sandbox_policy(workspace \\ nil) do
    case Schema.resolve_runtime_turn_sandbox_policy(settings!(), :codex, workspace) do
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

  @spec agent_app_server_settings(atom(), Path.t() | nil, keyword()) ::
          {:ok, codex_runtime_settings()} | {:error, term()}
  def agent_app_server_settings(runtime, workspace \\ nil, opts \\ []) do
    with {:ok, settings} <- settings() do
      with {:ok, turn_sandbox_policy} <-
             Schema.resolve_runtime_turn_sandbox_policy(settings, runtime, workspace, opts) do
        runtime_config = Map.get(settings, runtime)

        {:ok,
         %{
           approval_policy: runtime_config.approval_policy,
           thread_sandbox: runtime_config.thread_sandbox,
           turn_sandbox_policy: turn_sandbox_policy
         }}
      end
    end
  end

  defp validate_semantics(settings) do
    with :ok <- validate_tracker(settings),
         :ok <- validate_runtime_commands(settings) do
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

  defp validate_runtime_commands(settings) do
    settings
    |> configured_runtimes()
    |> Enum.find_value(fn runtime ->
      case runtime_command(settings, runtime) do
        command when is_binary(command) and command != "" ->
          nil

        _ ->
          {:error, {:missing_runtime_command, runtime}}
      end
    end)
    |> case do
      nil -> :ok
      error -> error
    end
  end

  defp configured_runtimes(settings) do
    label_runtimes =
      (settings.agent.runtime_by_label || %{})
      |> Map.values()
      |> Enum.map(&runtime_atom/1)
      |> Enum.reject(&is_nil/1)

    default_runtime = default_agent_runtime(settings)

    Enum.uniq([default_runtime | label_runtimes])
  end

  defp runtime_command(settings, runtime), do: Map.get(settings, runtime).command

  defp runtime_atom("codex"), do: :codex
  defp runtime_atom("claude"), do: :claude
  defp runtime_atom("cursor"), do: :cursor

  defp runtime_atom("antigravity"), do: :antigravity
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

      {:missing_runtime_command, runtime} ->
        "Missing WORKFLOW.md #{runtime} command for configured runtime"

      other ->
        "Invalid WORKFLOW.md config: #{inspect(other)}"
    end
  end
end
