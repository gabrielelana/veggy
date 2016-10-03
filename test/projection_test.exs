defmodule Veggy.ProjectionTest do
  use ExUnit.Case, async: true

  defmodule Projection do
    def init, do: {:ok, %{"counter" => 0}, []}

    def identity(event), do: {:ok, event["correlation_id"]}

    def process(%{"event" => "E1"}, %{"counter" => 0} = record) do
      %{record | "counter" => 1}
    end
    def process(%{"event" => "E2"}, %{"counter" => 1} = record) do
      %{record | "counter" => 2}
    end
    def process(%{"event" => "E3"}, %{"counter" => 2} = record) do
      %{record | "counter" => 3}
    end
  end

  test "one record straight" do
    assert [%{"_id" => 1, "counter" => 1}] == Veggy.Projection.process(Projection,
      [%{"event" => "E1", "correlation_id" => 1, "_offset" => 1}])

    assert [%{"_id" => 1, "counter" => 2}] == Veggy.Projection.process(Projection,
      [%{"event" => "E1", "correlation_id" => 1, "_offset" => 1},
       %{"event" => "E2", "correlation_id" => 1, "_offset" => 2}])

    assert [%{"_id" => 1, "counter" => 3}] == Veggy.Projection.process(Projection,
      [%{"event" => "E1", "correlation_id" => 1, "_offset" => 1},
       %{"event" => "E2", "correlation_id" => 1, "_offset" => 2},
       %{"event" => "E3", "correlation_id" => 1, "_offset" => 3}])
  end

  test "multiple records" do
    assert [%{"_id" => 1, "counter" => 1},
            %{"_id" => 2, "counter" => 1}] ==
      Veggy.Projection.process(Projection,
        [%{"event" => "E1", "correlation_id" => 1, "_offset" => 1},
         %{"event" => "E1", "correlation_id" => 2, "_offset" => 2}])

  end

  test "out of order events are ignored" do
    assert [%{"_id" => 2, "counter" => 1}] == Veggy.Projection.process(Projection,
      [%{"event" => "E2", "correlation_id" => 1, "_offset" => 1},
       %{"event" => "E1", "correlation_id" => 2, "_offset" => 2}])
  end
end
