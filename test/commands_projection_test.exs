defmodule Veggy.CommandsProjectionTest do
  use ExUnit.Case, async: true

  test "process CommandReceived" do
    command = %{"command" => "DoSomething", "id" => 1}
    event = %{"event" => "CommandReceived",
              "received_at" => DateTime.utc_now,
              "command" => command,
              "command_id" => command["id"],
             }
    record = Veggy.Projection.Commands.process(event, %{})

    assert record["status"] == "received"
    assert record["received_at"] == event["received_at"]
    assert record["command"] == command
    assert record["command_id"] == command["id"]
  end

  test "process CommandSucceeded" do
    received_at = Timex.now
    succeeded_at = Timex.add(received_at, Timex.Duration.from_milliseconds(10))
    command = %{"command" => "DoSomething", "id" => 1}
    event = %{"event" => "CommandSucceeded",
              "received_at" => Veggy.MongoDB.DateTime.from_datetime(succeeded_at),
              "command_id" => command["id"],
              "commands" => [2,3],
              "events" => [4],
             }
    record = %{"received_at" => Veggy.MongoDB.DateTime.from_datetime(received_at)}
    record = Veggy.Projection.Commands.process(event, record)

    assert record["status"] == "succeeded"
    assert record["succeeded_at"] == event["received_at"]
    assert record["commands"] == event["commands"]
    assert record["events"] == event["events"]
    assert record["elapsed"] == 10
  end

  test "process CommandFailed" do
    received_at = Timex.now
    failed_at = Timex.add(received_at, Timex.Duration.from_milliseconds(10))
    command = %{"command" => "DoSomething", "id" => 1}
    event = %{"event" => "CommandFailed",
              "received_at" => Veggy.MongoDB.DateTime.from_datetime(failed_at),
              "command_id" => command["id"],
              "commands" => [],
              "events" => [2],
             }
    record = %{"received_at" => Veggy.MongoDB.DateTime.from_datetime(received_at)}
    record = Veggy.Projection.Commands.process(event, record)

    assert record["status"] == "failed"
    assert record["failed_at"] == event["received_at"]
    assert record["commands"] == event["commands"]
    assert record["events"] == event["events"]
    assert record["elapsed"] == 10
  end

  test "process CommandHandedOver" do
    command = %{"command" => "DoSomething", "id" => 1}
    event = %{"event" => "CommandHandedOver",
              "received_at" => Veggy.MongoDB.DateTime.from_datetime(Timex.now),
              "command_id" => command["id"],
              "commands" => [2],
              "events" => [3],
             }
    record = Veggy.Projection.Commands.process(event, %{})

    assert record["status"] == "working"
    assert record["commands"] == event["commands"]
    assert record["events"] == event["events"]
  end

  test "process CommandRolledBack" do
    received_at = Timex.now
    rolledback_at = Timex.add(received_at, Timex.Duration.from_milliseconds(10))
    command = %{"command" => "DoSomething", "id" => 1}
    event = %{"event" => "CommandRolledBack",
              "received_at" => Veggy.MongoDB.DateTime.from_datetime(rolledback_at),
              "command_id" => command["id"],
              "commands" => [4],
              "events" => [5],
             }
    record = %{"status" => "succeeded",
               "received_at" => Veggy.MongoDB.DateTime.from_datetime(received_at),
               "commands" => [2],
               "events" => [3]}
    record = Veggy.Projection.Commands.process(event, record)

    assert record["status"] == "rolledback"
    assert record["rolledback_at"] == event["received_at"]
    assert record["commands"] == [2, 4]
    assert record["events"] == [3, 5]
    assert record["elapsed"] == 10
  end

  test "keep track of every event related to a command" do
    event = %{"id" => 3}
    record = %{"events" => [1, 2]}
    record = Veggy.Projection.Commands.process(event, record)
    assert record["events"] == [1, 2, 3]

    event = %{"id" => 3}
    record = %{"events" => [1, 2, 3]}
    record = Veggy.Projection.Commands.process(event, record)
    assert record["events"] == [1, 2, 3]
  end
end