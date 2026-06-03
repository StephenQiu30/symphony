defmodule SymphonyElixir.ChannelManager do
  @moduledoc """
  Manages online status notifications with batch optimization and deduplication.

  This module optimizes the fanout of online status changes by:
  1. Batching notifications to merge overlapping friend lists
  2. Deduplicating notifications using unique dedup IDs
  3. Reducing overall MQ message volume
  """

  require Logger

  @type status :: :online | :offline
  @type notification :: %{
    user_id: String.t(),
    status: status(),
    friends: [String.t()],
    dedup_id: String.t() | nil
  }
  @type processed_notification :: %{
    user_ids: [String.t()],
    status: status(),
    recipients: [String.t()],
    dedup_id: String.t() | nil
  }

  @doc """
  Batch process online status change notifications with deduplication.

  Takes a list of notifications and returns optimized notifications with:
  - Deduplicated messages (same dedup_id processed only once)
  - Merged friend lists for efficiency

  ## Examples

      iex> notifications = [
      ...>   %{user_id: "user_a", status: :online, friends: ["user_b", "user_c"]},
      ...>   %{user_id: "user_a", status: :online, friends: ["user_b", "user_c"], dedup_id: "dedup_1"}
      ...> ]
      iex> SymphonyElixir.ChannelManager.batch_notify_online_status(notifications)
      [%{user_ids: ["user_a"], status: :online, recipients: ["user_b", "user_c"], dedup_id: "dedup_1"}]
  """
  @spec batch_notify_online_status([notification()], keyword()) :: [processed_notification()]
  def batch_notify_online_status(notifications, opts \\ []) when is_list(notifications) do
    Logger.info("Processing #{length(notifications)} online status notifications")

    notifications
    |> deduplicate_notifications(opts)
    |> process_notifications()
  end

  @doc """
  Generate a deduplication ID for a user status change.

  The dedup ID is consistent for the same user and status combination,
  allowing deduplication of duplicate notifications.

  ## Examples

      iex> SymphonyElixir.ChannelManager.generate_dedup_id("user_a", :online)
      "dedup_user_a_online"
  """
  @spec generate_dedup_id(String.t(), status()) :: String.t()
  def generate_dedup_id(user_id, status) when is_binary(user_id) and status in [:online, :offline] do
    "dedup_#{user_id}_#{status}"
  end

  @doc """
  Merge friend lists from multiple notifications into a single deduplicated list.

  Excludes the user IDs themselves from the merged list.

  ## Examples

      iex> notifications = [
      ...>   %{user_id: "user_a", friends: ["user_b", "user_c"]},
      ...>   %{user_id: "user_b", friends: ["user_c", "user_d"]}
      ...> ]
      iex> SymphonyElixir.ChannelManager.merge_friend_lists(notifications)
      ["user_b", "user_c", "user_d"]
  """
  @spec merge_friend_lists([notification()]) :: [String.t()]
  def merge_friend_lists(notifications) when is_list(notifications) do
    user_ids = MapSet.new(notifications, & &1.user_id)

    notifications
    |> Enum.flat_map(& &1.friends)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(user_ids, &1))
  end

  # Deduplicate notifications by dedup_id with optional time window.
  # When dedup_window_ms: 0, skip deduplication entirely (all notifications are fresh).
  defp deduplicate_notifications(notifications, opts) do
    case Keyword.get(opts, :dedup_window_ms) do
      0 ->
        # Zero window: treat all as fresh, skip dedup
        notifications

      _ ->
        # Default: group by dedup_id, first-wins per group
        notifications
        |> Enum.group_by(fn notification ->
          notification[:dedup_id] || generate_dedup_id(notification.user_id, notification.status)
        end)
        |> Enum.map(fn {_dedup_id, grouped_notifications} ->
          hd(grouped_notifications)
        end)
    end
  end

  # Consolidate notifications by status, merging friend lists
  defp process_notifications(notifications) do
    notifications
    |> Enum.group_by(& &1.status)
    |> Enum.map(fn {status, group} ->
      user_ids = group |> Enum.map(& &1.user_id) |> Enum.uniq()
      dedup_ids = Enum.map(group, fn n -> n[:dedup_id] || generate_dedup_id(n.user_id, n.status) end)

      recipients =
        group
        |> Enum.flat_map(& &1.friends)
        |> Enum.uniq()
        |> Enum.reject(&(&1 in user_ids))

      %{
        user_ids: user_ids,
        status: status,
        recipients: recipients,
        dedup_id: hd(dedup_ids)
      }
    end)
  end
end
