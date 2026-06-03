defmodule SymphonyElixir.ConnectionSyncTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.{ConnectionStore, ConnectionSync}

  setup do
    name = :"sync_store_#{System.unique_integer([:positive])}"
    {:ok, store} = ConnectionStore.start_link(name: name)
    on_exit(fn -> if Process.alive?(store), do: GenServer.stop(store) end)
    %{store: name}
  end

  describe "detect_drift/1" do
    test "no drift when all registered processes are alive", %{store: store} do
      alive_pid = spawn(fn -> Process.sleep(:infinity) end)
      ConnectionStore.register("ISSUE-1", alive_pid, %{state: :running}, store)

      report = ConnectionSync.detect_drift(store: store)
      assert report.phantom == []
      assert report.mismatch == []
    end

    test "detects phantom entries: registered but process dead", %{store: store} do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(50)
      ConnectionStore.register("ISSUE-1", dead_pid, %{state: :running}, store)

      report = ConnectionSync.detect_drift(store: store)
      assert length(report.phantom) == 1
      assert hd(report.phantom).issue_id == "ISSUE-1"
    end

    test "detects mismatched state when metadata state differs from expected", %{store: store} do
      alive_pid = spawn(fn -> Process.sleep(:infinity) end)
      ConnectionStore.register("ISSUE-1", alive_pid, %{state: :running}, store)

      report = ConnectionSync.detect_drift(store: store, expected_state: :completed)
      assert length(report.mismatch) == 1
      assert hd(report.mismatch).issue_id == "ISSUE-1"
      assert hd(report.mismatch).expected == :completed
      assert hd(report.mismatch).actual == :running
    end

    test "returns empty report when store is empty", %{store: store} do
      report = ConnectionSync.detect_drift(store: store)
      assert report.phantom == []
      assert report.mismatch == []
    end
  end

  describe "repair/1" do
    test "cleans phantom entries from store", %{store: store} do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(50)
      ConnectionStore.register("ISSUE-1", dead_pid, %{state: :running}, store)

      report = ConnectionSync.detect_drift(store: store)
      assert length(report.phantom) == 1

      :ok = ConnectionSync.repair(report, store: store)

      assert {:error, :not_found} = ConnectionStore.get("ISSUE-1", store)
    end

    test "repairs mismatched state by updating metadata", %{store: store} do
      alive_pid = spawn(fn -> Process.sleep(:infinity) end)
      ConnectionStore.register("ISSUE-1", alive_pid, %{state: :running}, store)

      report = ConnectionSync.detect_drift(store: store, expected_state: :completed)
      :ok = ConnectionSync.repair(report, store: store)

      {:ok, entry} = ConnectionStore.get("ISSUE-1", store)
      assert entry.metadata.state == :completed
    end

    test "returns :ok with empty report when nothing to repair" do
      assert :ok = ConnectionSync.repair(%{phantom: [], mismatch: []})
    end
  end

  describe "verify_and_repair/1" do
    test "detects and repairs drift in one call", %{store: store} do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(50)
      ConnectionStore.register("ISSUE-1", dead_pid, %{state: :running}, store)

      result = ConnectionSync.verify_and_repair(store: store)
      assert result.phantom_cleaned == 1
      assert result.mismatch_repaired == 0

      assert {:error, :not_found} = ConnectionStore.get("ISSUE-1", store)
    end

    test "returns zero counts when no drift detected", %{store: store} do
      result = ConnectionSync.verify_and_repair(store: store)
      assert result.phantom_cleaned == 0
      assert result.mismatch_repaired == 0
    end
  end
end
