defmodule Veggy.Projection do
  use GenServer

  # defcallback init() :: {events :: [String.t], offset :: integer}
  # defcallback fetch(event :: Map.t) :: record :: Map.t
  # defcallback store(record :: Map.t, offset :: integer) :: :ok | {:error, reason :: String.t}
  # defcallback delete(record :: Map.t) :: :ok | {:error, reason :: String.t}
  # defcallback process(event :: Map.t, record :: Map.t) :: record :: Map.t | :skip | :hold | :delete | {:error, reason :: String.t}
  # defcallback query(report_name :: String.t, query :: Map.t) :: report :: [record :: Map.t]

  def start_link(module) do
    GenServer.start_link(__MODULE__, %{module: module})
  end

  def init(%{module: module}) do
    module.init
    {:ok, %{module: module}}
  end

  def handle_info({:event, event}, state) do
    record = state.module.fetch(event)
    case state.module.process(event, record) do
      :skip -> raise "unimplemented"
      :hold -> raise "unimplemented"
      :delete -> state.module.delete(record)
      {:error, _reason} -> raise "unimplemented"
      record -> state.module.store(record)
    end
    {:noreply, state}
  end
end
