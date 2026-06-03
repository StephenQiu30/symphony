defmodule SymphonyElixir.CursorBridgeAuthTest do
  use ExUnit.Case, async: true

  @bridge Path.expand("../../../scripts/cursor-symphony-bridge", __DIR__)

  test "uses local Cursor login before CURSOR_API_KEY" do
    with_fake_cursor("Logged in as dev@example.com\n", fn ctx ->
      env = [
        {"PATH", ctx.bin_dir <> ":" <> System.get_env("PATH", "")},
        {"CURSOR_AGENT_BIN", nil},
        {"CURSOR_API_KEY", "fallback-secret"},
        {"SYMPHONY_CURSOR_EXPECTED_ACCOUNT", "dev@example.com"},
        {"SYMP_TEST_CURSOR_TRACE", ctx.trace_file}
      ]

      assert {_, 0} = run_bridge(env)
      trace = File.read!(ctx.trace_file)

      assert trace =~ "STATUS"
      assert trace =~ "ACP:"
      refute trace =~ "--api-key"
      refute trace =~ "fallback-secret"
    end)
  end

  test "falls back to CURSOR_API_KEY when local login is missing" do
    with_fake_cursor("Not logged in\n", fn ctx ->
      env = [
        {"PATH", ctx.bin_dir <> ":" <> System.get_env("PATH", "")},
        {"CURSOR_AGENT_BIN", nil},
        {"CURSOR_API_KEY", "fallback-secret"},
        {"SYMP_TEST_CURSOR_TRACE", ctx.trace_file}
      ]

      assert {_, 0} = run_bridge(env)
      trace = File.read!(ctx.trace_file)

      assert trace =~ "STATUS"
      assert trace =~ "ACP:--api-key fallback-secret acp"
    end)
  end

  test "falls back to CURSOR_API_KEY when expected account does not match" do
    with_fake_cursor("Logged in as other@example.com\n", fn ctx ->
      env = [
        {"PATH", ctx.bin_dir <> ":" <> System.get_env("PATH", "")},
        {"CURSOR_AGENT_BIN", nil},
        {"CURSOR_API_KEY", "fallback-secret"},
        {"SYMPHONY_CURSOR_EXPECTED_ACCOUNT", "dev@example.com"},
        {"SYMP_TEST_CURSOR_TRACE", ctx.trace_file}
      ]

      assert {stderr, 0} = run_bridge(env, stderr_to_stdout: true)
      trace = File.read!(ctx.trace_file)

      assert trace =~ "ACP:--api-key fallback-secret acp"
      assert stderr =~ "using CURSOR_API_KEY fallback"
      refute stderr =~ "fallback-secret"
    end)
  end

  test "fails clearly when expected account does not match and no API key exists" do
    with_fake_cursor("Logged in as other@example.com\n", fn ctx ->
      env = [
        {"PATH", ctx.bin_dir <> ":" <> System.get_env("PATH", "")},
        {"CURSOR_AGENT_BIN", nil},
        {"CURSOR_API_KEY", nil},
        {"SYMPHONY_CURSOR_EXPECTED_ACCOUNT", "dev@example.com"},
        {"SYMP_TEST_CURSOR_TRACE", ctx.trace_file}
      ]

      assert {stderr, 1} = run_bridge(env, stderr_to_stdout: true)

      assert stderr =~ "Cursor CLI local login is not usable"
      assert stderr =~ "dev@example.com"
      assert stderr =~ "other@example.com"
    end)
  end

  test "falls back to CURSOR_API_KEY when status command fails" do
    with_fake_cursor("__FAIL_STATUS__", fn ctx ->
      env = [
        {"PATH", ctx.bin_dir <> ":" <> System.get_env("PATH", "")},
        {"CURSOR_AGENT_BIN", nil},
        {"CURSOR_API_KEY", "fallback-secret"},
        {"SYMP_TEST_CURSOR_TRACE", ctx.trace_file}
      ]

      assert {stderr, 0} = run_bridge(env, stderr_to_stdout: true)
      trace = File.read!(ctx.trace_file)

      assert trace =~ "ACP:--api-key fallback-secret acp"
      assert stderr =~ "using CURSOR_API_KEY fallback"
      refute stderr =~ "fallback-secret"
    end)
  end

  test "advertises terminal capability for Cursor service startup commands" do
    with_fake_cursor("Logged in as dev@example.com\n", fn ctx ->
      env = [
        {"PATH", ctx.bin_dir <> ":" <> System.get_env("PATH", "")},
        {"CURSOR_AGENT_BIN", nil},
        {"CURSOR_API_KEY", nil},
        {"SYMP_TEST_CURSOR_TRACE", ctx.trace_file}
      ]

      assert {_, 0} = run_bridge(env)
      trace = File.read!(ctx.trace_file)

      assert trace =~ "INIT_TERMINAL:true"
    end)
  end

  test "bridge terminal manager executes service startup commands and captures output" do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-cursor-bridge-terminal-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    try do
      script = """
      import importlib.machinery, json
      bridge = importlib.machinery.SourceFileLoader("cursor_bridge", "#{@bridge}").load_module()
      manager = bridge.TerminalManager()
      created = manager.create({
          "command": "sh",
          "args": ["-c", "printf service-ready > service.started && printf booted"],
          "cwd": "#{root}",
          "outputByteLimit": 1024,
      })
      wait = manager.wait_for_exit(created)
      output = manager.output(created)
      manager.release(created)
      print(json.dumps({"created": created, "wait": wait, "output": output}))
      """

      assert {stdout, 0} = System.cmd("python3", ["-c", script])
      result = Jason.decode!(stdout)

      assert %{"terminalId" => "term-" <> _} = result["created"]
      assert result["wait"] == %{"exitCode" => 0, "signal" => nil}
      assert result["output"]["output"] == "booted"
      assert File.read!(Path.join(root, "service.started")) == "service-ready"
    after
      File.rm_rf(root)
    end
  end

  defp with_fake_cursor(status_output, fun) do
    root =
      Path.join(
        System.tmp_dir!(),
        "symphony-cursor-bridge-auth-#{System.unique_integer([:positive])}"
      )

    bin_dir = Path.join(root, "bin")
    trace_file = Path.join(root, "cursor.trace")

    File.mkdir_p!(bin_dir)
    fake_cursor = Path.join(bin_dir, "agent")

    File.write!(fake_cursor, fake_cursor_script(status_output))
    File.chmod!(fake_cursor, 0o755)

    try do
      fun.(%{root: root, bin_dir: bin_dir, trace_file: trace_file})
    after
      File.rm_rf(root)
    end
  end

  defp run_bridge(env, opts \\ []) do
    System.cmd(
      "sh",
      ["-c", "exec \"$1\" </dev/null", "cursor-bridge-test", @bridge],
      Keyword.merge([env: env], opts)
    )
  end

  defp fake_cursor_script(status_output) do
    escaped_status = String.replace(status_output, "'", "'\"'\"'")

    """
    #!/bin/sh
    trace_file="${SYMP_TEST_CURSOR_TRACE}"

    if [ "$1" = "status" ]; then
      printf 'STATUS\\n' >> "$trace_file"
      if [ '#{escaped_status}' = '__FAIL_STATUS__' ]; then
        printf 'status failed\\n' >&2
        exit 2
      fi
      printf '%s' '#{escaped_status}'
      exit 0
    fi

    printf 'ACP:%s\\n' "$*" >> "$trace_file"

    while IFS= read -r line; do
      printf 'JSON:%s\\n' "$line" >> "$trace_file"
      case "$line" in
        *'"terminal":true'*)
          printf 'INIT_TERMINAL:true\\n' >> "$trace_file"
          ;;
        *'"terminal":false'*)
          printf 'INIT_TERMINAL:false\\n' >> "$trace_file"
          ;;
      esac

      case "$line" in
        *'"method":"initialize"'*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
          ;;
        *'"method":"authenticate"'*)
          printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"methodId":"cursor_login"}}'
          ;;
      esac
    done
    """
  end
end
