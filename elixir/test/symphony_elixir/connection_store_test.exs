defmodule SymphonyElixir.ConnectionStoreTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ConnectionStore

  setup do
    name = :"store_#{System.unique_integer([:positive])}"
    {:ok, pid} = ConnectionStore.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{store: name}
  end

  describe "register/3" do
    test "registers a new connection and returns :ok", %{store: store} do
      assert :ok = ConnectionStore.register("ISSUE-1", self(), %{state: :running}, store)
    end

    test "overwrites an existing connection for the same issue_id", %{store: store} do
      :ok = ConnectionStore.register("ISSUE-1", self(), %{state: :running}, store)
      other_pid = spawn(fn -> Process.sleep(:infinity) end)
      :ok = ConnectionStore.register("ISSUE-1", other_pid, %{state: :completed}, store)

      {:ok, entry} = ConnectionStore.get("ISSUE-1", store)
      assert entry.pid == other_pid
      assert entry.metadata.state == :completed
    end
  end

  describe "unregister/1" do
    test "removes a registered connection", %{store: store} do
      :ok = ConnectionStore.register("ISSUE-1", self(), %{state: :running}, store)
      assert :ok = ConnectionStore.unregister("ISSUE-1", store)
      assert {:error, :not_found} = ConnectionStore.get("ISSUE-1", store)
    end

    test "returns :ok even if the connection does not exist", %{store: store} do
      assert :ok = ConnectionStore.unregister("NONEXISTENT", store)
    end
  end

  describe "get/1" do
    test "returns the connection entry for a registered issue", %{store: store} do
      :ok = ConnectionStore.register("ISSUE-1", self(), %{state: :running}, store)
      assert {:ok, entry} = ConnectionStore.get("ISSUE-1", store)
      assert entry.issue_id == "ISSUE-1"
      assert entry.pid == self()
      assert entry.metadata == %{state: :running}
      assert %DateTime{} = entry.registered_at
      assert %DateTime{} = entry.last_heartbeat
    end

    test "returns {:error, :not_found} for unregistered issue", %{store: store} do
      assert {:error, :not_found} = ConnectionStore.get("UNKNOWN", store)
    end
  end

  describe "list/0" do
    test "returns all registered connections", %{store: store} do
      :ok = ConnectionStore.register("ISSUE-1", self(), %{state: :running}, store)
      :ok = ConnectionStore.register("ISSUE-2", self(), %{state: :running}, store)

      entries = ConnectionStore.list(store)
      assert length(entries) == 2
      issue_ids = Enum.map(entries, & &1.issue_id)
      assert "ISSUE-1" in issue_ids
      assert "ISSUE-2" in issue_ids
    end

    test "returns empty list when no connections registered", %{store: store} do
      assert [] = ConnectionStore.list(store)
    end
  end

  describe "heartbeat/1" do
    test "refreshes the last_heartbeat timestamp", %{store: store} do
      :ok = ConnectionStore.register("ISSUE-1", self(), %{state: :running}, store)
      {:ok, before_entry} = ConnectionStore.get("ISSUE-1", store)

      Process.sleep(10)
      :ok = ConnectionStore.heartbeat("ISSUE-1", store)

      {:ok, after_entry} = ConnectionStore.get("ISSUE-1", store)
      assert DateTime.after?(after_entry.last_heartbeat, before_entry.last_heartbeat)
    end

    test "returns {:error, :not_found} for unregistered issue", %{store: store} do
      assert {:error, :not_found} = ConnectionStore.heartbeat("UNKNOWN", store)
    end
  end

  describe "update_metadata/2" do
    test "merges metadata into existing connection", %{store: store} do
      :ok = ConnectionStore.register("ISSUE-1", self(), %{state: :running, turn_count: 0}, store)
      :ok = ConnectionStore.update_metadata("ISSUE-1", %{turn_count: 1}, store)

      {:ok, entry} = ConnectionStore.get("ISSUE-1", store)
      assert entry.metadata == %{state: :running, turn_count: 1}
    end

    test "returns {:error, :not_found} for unregistered issue", %{store: store} do
      assert {:error, :not_found} = ConnectionStore.update_metadata("UNKNOWN", %{foo: 1}, store)
    end
  end
end
