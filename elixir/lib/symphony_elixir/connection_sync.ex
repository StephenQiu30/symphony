defmodule SymphonyElixir.ConnectionSync do
  @moduledoc """
  Detects and repairs drift between the connection store and actual process liveness.
  """

  require Logger
  alias SymphonyElixir.ConnectionStore

  @type drift_report :: %{
          phantom: [ConnectionStore.entry()],
          mismatch: [mismatch_entry()]
        }

  @type mismatch_entry :: %{
          issue_id: String.t(),
          expected: term(),
          actual: term()
        }

  @type repair_result :: %{
          phantom_cleaned: non_neg_integer(),
          mismatch_repaired: non_neg_integer()
        }

  @spec detect_drift(keyword()) :: drift_report()
  def detect_drift(opts \\ []) do
    store = Keyword.get(opts, :store, ConnectionStore)
    expected_state = Keyword.get(opts, :expected_state)
    entries = ConnectionStore.list(store)

    phantom = Enum.filter(entries, fn entry -> not process_alive?(entry.pid) end)

    mismatch =
      if expected_state do
        entries
        |> Enum.reject(fn entry -> entry in phantom end)
        |> Enum.filter(fn entry -> entry.metadata[:state] != expected_state end)
        |> Enum.map(fn entry ->
          %{issue_id: entry.issue_id, expected: expected_state, actual: entry.metadata[:state]}
        end)
      else
        []
      end

    %{phantom: phantom, mismatch: mismatch}
  end

  @spec repair(drift_report(), keyword()) :: :ok
  def repair(%{phantom: phantom, mismatch: mismatch}, opts \\ []) do
    store = Keyword.get(opts, :store, ConnectionStore)

    Enum.each(phantom, fn entry ->
      Logger.info("ConnectionSync: cleaning phantom #{entry.issue_id}")
      ConnectionStore.unregister(entry.issue_id, store)
    end)

    Enum.each(mismatch, fn m ->
      Logger.info("ConnectionSync: repairing mismatch #{m.issue_id} #{m.actual} -> #{m.expected}")
      ConnectionStore.update_metadata(m.issue_id, %{state: m.expected}, store)
    end)

    :ok
  end

  @spec verify_and_repair(keyword()) :: repair_result()
  def verify_and_repair(opts \\ []) do
    report = detect_drift(opts)
    :ok = repair(report, opts)

    %{phantom_cleaned: length(report.phantom), mismatch_repaired: length(report.mismatch)}
  end

  defp process_alive?(pid), do: Process.alive?(pid)
end
