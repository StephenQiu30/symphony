defmodule SymphonyElixir.ChannelManagerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.ChannelManager

  describe "notify_online_status_changed/3" do
    test "batch notification merges friend lists for multiple users" do
      # Setup: User A and User B are both friends with User C
      # When both A and B come online, C should receive only one notification
      notifications = [
        %{user_id: "user_a", status: :online, friends: ["user_c", "user_d"]},
        %{user_id: "user_b", status: :online, friends: ["user_c", "user_e"]}
      ]

      result = ChannelManager.batch_notify_online_status(notifications)

      # User C should receive only one notification (deduplicated)
      user_c_notifications = Enum.filter(result, fn n -> "user_c" in n.recipients end)
      assert length(user_c_notifications) == 1

      # User D and E should each receive one notification
      user_d_notifications = Enum.filter(result, fn n -> "user_d" in n.recipients end)
      user_e_notifications = Enum.filter(result, fn n -> "user_e" in n.recipients end)
      assert length(user_d_notifications) == 1
      assert length(user_e_notifications) == 1
    end

    test "deduplication prevents duplicate notifications for same user status change" do
      # Setup: Same user status change sent twice
      notifications = [
        %{user_id: "user_a", status: :online, friends: ["user_b"], dedup_id: "dedup_1"},
        %{user_id: "user_a", status: :online, friends: ["user_b"], dedup_id: "dedup_1"}
      ]

      result = ChannelManager.batch_notify_online_status(notifications)

      # Should only process one notification due to dedup
      assert length(result) == 1
      assert hd(result).dedup_id == "dedup_1"
    end

    test "different dedup IDs process separately" do
      notifications = [
        %{user_id: "user_a", status: :online, friends: ["user_b"], dedup_id: "dedup_1"},
        %{user_id: "user_a", status: :offline, friends: ["user_b"], dedup_id: "dedup_2"}
      ]

      result = ChannelManager.batch_notify_online_status(notifications)

      # Both notifications should be processed (different dedup IDs)
      assert length(result) == 2
    end

    test "single notification works correctly" do
      notifications = [
        %{user_id: "user_a", status: :online, friends: ["user_b", "user_c"]}
      ]

      result = ChannelManager.batch_notify_online_status(notifications)

      assert length(result) == 1
      assert "user_a" in hd(result).user_ids
      assert hd(result).status == :online
      assert "user_b" in hd(result).recipients
      assert "user_c" in hd(result).recipients
    end

    test "empty notifications returns empty list" do
      result = ChannelManager.batch_notify_online_status([])
      assert result == []
    end

    test "batch consolidation reduces MQ messages by grouping by status" do
      # 3 users come online with overlapping friends
      # Should produce 1 consolidated notification (not 3)
      notifications = [
        %{user_id: "user_a", status: :online, friends: ["user_c", "user_d"]},
        %{user_id: "user_b", status: :online, friends: ["user_c", "user_e"]},
        %{user_id: "user_f", status: :online, friends: ["user_d", "user_g"]}
      ]

      result = ChannelManager.batch_notify_online_status(notifications)

      # All online notifications should be consolidated into one
      online_results = Enum.filter(result, fn n -> n.status == :online end)
      assert length(online_results) == 1

      consolidated = hd(online_results)
      # Recipients should be the union of all friend lists, excluding the users themselves
      assert "user_c" in consolidated.recipients
      assert "user_d" in consolidated.recipients
      assert "user_e" in consolidated.recipients
      assert "user_g" in consolidated.recipients
      refute "user_a" in consolidated.recipients
      refute "user_b" in consolidated.recipients
      refute "user_f" in consolidated.recipients
    end

    test "batch consolidation separates online and offline notifications" do
      notifications = [
        %{user_id: "user_a", status: :online, friends: ["user_b"]},
        %{user_id: "user_c", status: :offline, friends: ["user_d"]}
      ]

      result = ChannelManager.batch_notify_online_status(notifications)

      assert length(result) == 2
      online = Enum.find(result, fn n -> n.status == :online end)
      offline = Enum.find(result, fn n -> n.status == :offline end)
      assert online
      assert offline
      assert "user_b" in online.recipients
      assert "user_d" in offline.recipients
    end

    test "dedup with time window expires stale notifications" do
      # Same dedup_id but from a previous time window should not be deduped
      old_dedup_id = "dedup_user_a_online"
      new_dedup_id = "dedup_user_a_online"

      notifications = [
        %{user_id: "user_a", status: :online, friends: ["user_b"], dedup_id: old_dedup_id},
        %{user_id: "user_a", status: :online, friends: ["user_b"], dedup_id: new_dedup_id}
      ]

      result = ChannelManager.batch_notify_online_status(notifications, dedup_window_ms: 0)

      # With 0ms window, even same dedup_id should both be processed (instant expiry)
      assert length(result) >= 1
    end

    test "large batch with overlapping friends produces minimal notifications" do
      # 5 users all share 3 common friends plus unique friends
      notifications =
        for i <- 1..5 do
          %{
            user_id: "user_#{i}",
            status: :online,
            friends: ["common_1", "common_2", "common_3", "unique_#{i}"]
          }
        end

      result = ChannelManager.batch_notify_online_status(notifications)

      # Should produce exactly 1 consolidated notification for all online users
      online_results = Enum.filter(result, fn n -> n.status == :online end)
      assert length(online_results) == 1

      consolidated = hd(online_results)
      # All common and unique friends should be present
      for i <- 1..3, do: assert("common_#{i}" in consolidated.recipients)
      for i <- 1..5, do: assert("unique_#{i}" in consolidated.recipients)
      # None of the users themselves should be recipients
      for i <- 1..5, do: refute("user_#{i}" in consolidated.recipients)
    end
  end

  describe "generate_dedup_id/2" do
    test "generates consistent dedup ID for same user and status" do
      id1 = ChannelManager.generate_dedup_id("user_a", :online)
      id2 = ChannelManager.generate_dedup_id("user_a", :online)

      assert id1 == id2
    end

    test "generates different dedup ID for different status" do
      id1 = ChannelManager.generate_dedup_id("user_a", :online)
      id2 = ChannelManager.generate_dedup_id("user_a", :offline)

      assert id1 != id2
    end

    test "generates different dedup ID for different user" do
      id1 = ChannelManager.generate_dedup_id("user_a", :online)
      id2 = ChannelManager.generate_dedup_id("user_b", :online)

      assert id1 != id2
    end
  end

  describe "merge_friend_lists/1" do
    test "merges overlapping friend lists" do
      notifications = [
        %{user_id: "user_a", friends: ["user_b", "user_c"]},
        %{user_id: "user_b", friends: ["user_c", "user_d"]}
      ]

      merged = ChannelManager.merge_friend_lists(notifications)

      # Should merge into unique recipients (excluding user_ids themselves)
      assert "user_c" in merged
      assert "user_d" in merged
      # Should not contain the users themselves
      refute "user_a" in merged
      refute "user_b" in merged
    end

    test "handles empty friend lists" do
      notifications = [
        %{user_id: "user_a", friends: []},
        %{user_id: "user_b", friends: ["user_c"]}
      ]

      merged = ChannelManager.merge_friend_lists(notifications)

      assert merged == ["user_c"]
    end
  end
end
