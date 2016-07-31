defmodule Veggy.UUID do
  def new do
    Mongo.IdServer.new
  end
end

defimpl String.Chars, for: BSON.ObjectId do
  def to_string(%BSON.ObjectId{value: value}) do
    Base.encode16(value, case: :lower)
  end
end

defimpl Poison.Encoder, for: BSON.ObjectId do
  def encode(%BSON.ObjectId{} = oid, options) do
    Poison.Encoder.BitString.encode(String.Chars.to_string(oid), options)
  end
end
