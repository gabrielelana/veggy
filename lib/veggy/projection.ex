defmodule Veggy.Projection do
  use GenServer

  @polling_interval 250

  # @type event_type :: String.t
  # @type event :: %{"event" => event_type}
  # @type record :: %{...}
  # @type offset :: integer
  # @type event_filter :: event_type | (event -> bool) | [event_fiter]
  # @type error :: {:error, reason :: any}
  #
  # defcallback init() :: {:ok, default :: record, event_filter} | error
  # defcallback identity(event) :: {:ok, record_id :: any} | error
  #
  # ### Storage dependent
  #
  # defcallback offset() :: {:ok, offset} | error
  # defcallback fetch(record_id :: any) :: {:ok, record} | error
  # defcallback store(record, offset) :: :ok | error
  # defcallback delete(record) :: :ok | error
  # defcallback query(name :: String.t, parameters :: Map.t) :: {:ok, [record]} | error
  #
  # ### Business logic
  #
  # defcallback process(event, record) ::
  #   record | {:hold, expected :: event_filter} | :skip | :delete | error

  def start_link(module) do
    GenServer.start_link(__MODULE__, %{module: module})
  end

  def init(%{module: module}) do
    {:ok, default, events} = module.init
    {:ok, offset} = module.offset
    Process.send_after(self, :process, @polling_interval)
    {:ok, %{module: module, default: default, offset: offset, filter: to_filter(events)}}
  end


  def handle_info(:process, state) do
    # IO.inspect("Poll events from EventStore after offset #{state.offset}")
    events = Veggy.EventStore.events_where({:offset_after, state.offset}, state.filter)
    # IO.inspect({:events, Enum.count(events)})
    offset = Enum.reduce(events, state.offset, &do_process(state.module, &1, &2))
    Process.send_after(self, :process, @polling_interval)
    {:noreply, %{state|offset: offset}}
  end

  defp do_process(module, %{"_offset" => offset} = event, _offset) do
    with {:ok, record_id} <- module.identity(event),
         {:ok, record} <- module.fetch(record_id) do
      # IO.inspect({:fetch, :event, event})
      # IO.inspect({:fetch, :record_id, record_id})
      # IO.inspect({:fetch, :record, record})
      case module.process(event, record) do
        :skip -> raise "unimplemented"
        :hold -> raise "unimplemented"
        :delete -> module.delete(record, offset)
        {:error, _reason} -> raise "unimplemented"
        record ->
          # IO.inspect({:after_process, record, offset})
          module.store(record, offset)
      end
      offset
    end
  end

  defp to_filter(events) when is_function(events), do: events
  defp to_filter(events) when is_binary(events), do: fn(%{"event" => ^events}) -> true; (_) -> false end
  defp to_filter(events) when is_list(events) do
    if Enum.all?(events, &is_binary/1) do
      fn(%{"event" => event}) -> event in events end
    else
      to_filter(events, [])
    end
  end
  defp to_filter([], filters), do: fn(event) -> Enum.all?(filters, fn(f) -> f.(event) end) end
  defp to_filter([event|events], filters), do: to_filter(events, [to_filter(event)|filters])
end
