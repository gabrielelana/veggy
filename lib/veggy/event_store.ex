defmodule Veggy.EventStore do
  use GenServer

  @collection "events"

  def start_link do
    offset = offset_of_last_event
    GenServer.start_link(__MODULE__, %{offset: offset, subscriptions: %{}}, name: __MODULE__)
  end
  def emit(%{event: _} = event) do
    GenServer.cast(__MODULE__, {:event, event})
  end

  def subscribe(pid, check) do
    reference = make_ref
    GenServer.cast(__MODULE__, {:subscribe, reference, check, pid})
    reference
  end

  def unsubscribe(reference) do
    GenServer.cast(__MODULE__, {:unsubscribe, reference})
  end

  def handle_cast({:event, event}, %{subscriptions: subscriptions, offset: offset} = state) do
    event
    |> enrich(offset)
    |> store
    |> dispatch(subscriptions)

    {:noreply, %{state | offset: offset + 1}}
  end
  def handle_cast({:subscribe, reference, check, pid}, %{subscriptions: subscriptions} = state) do
    {:noreply, %{state | subscriptions: Map.put(subscriptions, reference, {check, pid})}}
  end
  def handle_cast({:unsubscribe, reference}, %{subscriptions: subscriptions} = state) do
    {:noreply, %{state | subscriptions: Map.delete(subscriptions, reference)}}
  end

  defp enrich(event, offset) do
    event
    |> Map.put(:received_at, Veggy.MongoDB.DateTime.utc_now)
    |> Map.put(:offset, offset)
  end

  defp store(event) do
    event
    |> Map.put(:_id, event.id)
    |> Map.delete(:id)
    |> (&Mongo.save_one(Veggy.MongoDB, @collection, &1)).()
    event
  end

  defp dispatch(event, subscriptions) do
    for {_, {check, pid}} <- subscriptions, check.(event) do
      send(pid, {:event, event})
    end
  end

  defp offset_of_last_event do
    last_event = Mongo.find(Veggy.MongoDB, @collection, %{}, sort: [offset: -1], limit: 1) |> Enum.to_list
    case last_event do
      [event] -> event["offset"]
      _ -> 0
    end
  end
end
