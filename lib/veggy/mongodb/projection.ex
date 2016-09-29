defmodule Veggy.MongoDB.Projection do
  defmacro __using__(opts) do
    collection = Keyword.get(opts, :collection)
    indexes = Keyword.get(opts, :indexes, [])
    events = Keyword.get(opts, :events, [])
    field = Keyword.get(opts, :field)

    quote do
      if unquote(collection) do
        @collection unquote(collection)
      else
        @collection "aggregate.#{Veggy.MongoDB.collection_name(__MODULE__)}"
      end

      def init do
        Enum.each([%{"_offset" => 1} | unquote(indexes)], &Veggy.MongoDB.create_index(@collection, &1))
        {:ok, offset, unquote(events)}
      end

      def fetch(event) do
        field_value = Map.fetch!(event, unquote(field))
        case Mongo.find(Veggy.MongoDB, @collection, %{unquote(field) => field_value}) |> Enum.to_list do
          [] -> %{}
          [d] -> d
        end
      end

      def store(record, offset) do
        Mongo.save_one(Veggy.MongoDB, @collection, record |> Map.put("_offset", offset))
      end

      def delete(record, offset) do
        Mongo.delete_one(Veggy.MongoDB, @collection, %{"_id" => record["_id"]})
        Mongo.save_one(Veggy.MongoDB, @collection, %{"_id" => "_offset", "_offset" => offset})
      end

      defoverridable [init: 0, fetch: 1, store: 2, delete: 2]

      def find(query, options \\ []) do
        {:ok, Mongo.find(Veggy.MongoDB, @collection, query, options) |> Enum.to_list}
      end

      def find_one(query, options \\ []) do
        case Mongo.find(Veggy.MongoDB, @collection, query) |> Enum.to_list do
          [d] -> {:ok, d}
          _ -> {:not_found, :record}
        end
      end

      defp offset do
        options = [sort: %{"_offset" => -1}, projection: %{"_offset" => 1, "_id" => 0}, limit: 1]
        case Mongo.find(Veggy.MongoDB, @collection, %{}, options) |> Enum.to_list do
          [] -> -1
          [%{"_offset" => offset}] -> offset
        end
      end
    end
  end
end
