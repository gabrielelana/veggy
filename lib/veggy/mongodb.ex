defmodule Veggy.MongoDB do
  use Mongo.Pool, name: __MODULE__, adapter: Mongo.Pool.Poolboy

  def child_spec do
    Supervisor.Spec.worker(__MODULE__,
      [[hostname: System.get_env("MONGODB_HOST") || "localhost",
        database: System.get_env("MONGODB_DBNAME") || dbname,
        username: System.get_env("MONGODB_USERNAME"),
        password: System.get_env("MONGODB_PASSWORD"),
       ]])
  end

  defmodule ObjectId do
    def from_string(object_id) when is_binary(object_id) do
      %BSON.ObjectId{value: Base.decode16!(object_id, case: :lower)}
    end
  end

  defmodule DateTime do
    def utc_now, do: from_datetime(Elixir.DateTime.utc_now)

    def from_datetime(dt) do
      BSON.DateTime.from_datetime(
        {{dt.year, dt.month, dt.day},
         {dt.hour, dt.minute, dt.second, 0}})
    end

    def to_datetime(%BSON.DateTime{utc: milliseconds}) do
      {:ok, dt} = Elixir.DateTime.from_unix(milliseconds, :milliseconds)
      dt
    end
  end

  defmodule Aggregate do
    defmacro __using__(opts) do
      collection = Keyword.get(opts, :collection);

      quote do
        if unquote(collection) do
          @collection unquote(collection)
        else
          @collection Veggy.MongoDB.Aggregate.collection_name(__MODULE__)
        end

        def fetch(id, initial) do
          case Mongo.find(Veggy.MongoDB, @collection, %{"_id" => id}) |> Enum.to_list do
            [d] -> d |> Map.put("id", d["_id"]) |> Map.delete("_id")
            _ -> initial
          end
        end

        def store(aggregate) do
          aggregate = aggregate |> Map.put("_id", aggregate["id"]) |> Map.delete("id")
          {:ok, _} = Mongo.update_one(
            Veggy.MongoDB,
            @collection,
            %{"_id" => aggregate["_id"]},
            %{"$set" => aggregate},
            upsert: true)
        end

        defoverridable [fetch: 2, store: 1]
      end
    end

    def collection_name(module_name) do
      # TODO: pluralize with { :inflex, "~> 1.7.0" }
      module_name
      |> Module.split
      |> List.last
      |> String.downcase
      |> Inflex.pluralize
      |> (&"aggregate.#{&1}").()
    end
  end

  defp dbname do
    case Mix.env do
      :prod -> "veggy"
      env -> "veggy_#{env}"
    end
  end
end
