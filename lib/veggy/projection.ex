defmodule Veggy.Projection do
  use GenServer

  @polling_interval 250

  # defcallback init() :: {:ok, offset :: integer, filter :: [String.t] | (event -> bool)} | {:error, reason :: any}
  # defcallback fetch(event :: Map.t) :: record :: Map.t
  # defcallback store(record :: Map.t, offset :: integer) :: :ok | {:error, reason :: any}
  # defcallback delete(record :: Map.t) :: :ok | {:error, reason :: any}
  # defcallback process(event :: Map.t, record :: Map.t) :: record :: Map.t | :skip | :hold | :delete | {:error, reason :: any}
  # defcallback query(report_name :: String.t, query :: Map.t) :: report :: [record :: Map.t]

  def start_link(module) do
    GenServer.start_link(__MODULE__, %{module: module})
  end

  def init(%{module: module}) do
    {:ok, offset, filter} = module.init
    # IO.inspect("Starting at offset #{offset}")
    Process.send_after(self, :process, @polling_interval)
    {:ok, %{module: module, offset: offset, filter: filter(filter)}}
  end

  def handle_info(:process, state) do
    # IO.inspect("Poll events from EventStore after offset #{state.offset}")
    events = Veggy.EventStore.after_offset(state.offset, state.filter)
    # IO.inspect({:events, events})
    offset = Enum.reduce(events, state.offset, &process(state.module, &1, &2))
    Process.send_after(self, :process, @polling_interval)
    {:noreply, %{state|offset: offset}}
  end

  defp process(module, %{"offset" => offset} = event, _offset) do
    # IO.inspect({:process, event, offset})
    record = module.fetch(event)
    # IO.inspect({:fetch, :record, record})
    case module.process(event, record) do
      :skip -> raise "unimplemented"
      :hold -> raise "unimplemented"
      :delete -> module.delete(record, offset)
      {:error, _reason} -> raise "unimplemented"
      record ->
        # IO.inspect({:after_process, :record, record})
        # IO.inspect({:after_process, :offset, offset})
        module.store(record, offset)
    end
    offset
  end

  defp filter(events) when is_function(events), do: events
  defp filter(events) when is_binary(events), do: fn(%{"event" => ^events}) -> true; (_) -> false end
  defp filter(events) when is_list(events) do
    if Enum.all?(events, &is_binary/1) do
      fn(%{"event" => event}) -> event in events end
    else
      filter(events, [])
    end
  end
  defp filter([], filters), do: fn(event) -> Enum.all?(filters, fn(f) -> f.(event) end) end
  defp filter([event|events], filters), do: filter(events, [filter(event)|filters])
end
