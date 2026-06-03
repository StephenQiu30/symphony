defmodule SymphonyElixir.ConnectionStore do
  @moduledoc """
  ETS-backed store for tracking active worker connections.
  """

  use GenServer
  require Logger

  defstruct [:table]

  @type entry :: %{
          issue_id: String.t(),
          pid: pid(),
          metadata: map(),
          registered_at: DateTime.t(),
          last_heartbeat: DateTime.t()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec register(String.t(), pid(), map(), GenServer.server()) :: :ok
  def register(issue_id, pid, metadata \\ %{}, server \\ __MODULE__)
      when is_binary(issue_id) and is_pid(pid) do
    GenServer.call(server, {:register, issue_id, pid, metadata})
  end

  @spec unregister(String.t(), GenServer.server()) :: :ok
  def unregister(issue_id, server \\ __MODULE__) when is_binary(issue_id) do
    GenServer.call(server, {:unregister, issue_id})
  end

  @spec get(String.t(), GenServer.server()) :: {:ok, entry()} | {:error, :not_found}
  def get(issue_id, server \\ __MODULE__) when is_binary(issue_id) do
    GenServer.call(server, {:get, issue_id})
  end

  @spec list(GenServer.server()) :: [entry()]
  def list(server \\ __MODULE__) do
    GenServer.call(server, :list)
  end

  @spec heartbeat(String.t(), GenServer.server()) :: :ok | {:error, :not_found}
  def heartbeat(issue_id, server \\ __MODULE__) when is_binary(issue_id) do
    GenServer.call(server, {:heartbeat, issue_id})
  end

  @spec update_metadata(String.t(), map(), GenServer.server()) :: :ok | {:error, :not_found}
  def update_metadata(issue_id, metadata, server \\ __MODULE__)
      when is_binary(issue_id) and is_map(metadata) do
    GenServer.call(server, {:update_metadata, issue_id, metadata})
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    table_name = Module.concat(name, Table)

    table = :ets.new(table_name, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])

    {:ok, %__MODULE__{table: table}}
  end

  @impl true
  def handle_call({:register, issue_id, pid, metadata}, _from, state) do
    now = DateTime.utc_now()

    entry = %{
      issue_id: issue_id,
      pid: pid,
      metadata: metadata,
      registered_at: now,
      last_heartbeat: now
    }

    :ets.insert(state.table, {issue_id, entry})
    {:reply, :ok, state}
  end

  def handle_call({:unregister, issue_id}, _from, state) do
    :ets.delete(state.table, issue_id)
    {:reply, :ok, state}
  end

  def handle_call({:get, issue_id}, _from, state) do
    case :ets.lookup(state.table, issue_id) do
      [{^issue_id, entry}] -> {:reply, {:ok, entry}, state}
      [] -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:list, _from, state) do
    entries = :ets.tab2list(state.table) |> Enum.map(fn {_key, entry} -> entry end)
    {:reply, entries, state}
  end

  def handle_call({:heartbeat, issue_id}, _from, state) do
    case :ets.lookup(state.table, issue_id) do
      [{^issue_id, entry}] ->
        updated = %{entry | last_heartbeat: DateTime.utc_now()}
        :ets.insert(state.table, {issue_id, updated})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:update_metadata, issue_id, metadata}, _from, state) do
    case :ets.lookup(state.table, issue_id) do
      [{^issue_id, entry}] ->
        updated = %{entry | metadata: Map.merge(entry.metadata, metadata)}
        :ets.insert(state.table, {issue_id, updated})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
end
