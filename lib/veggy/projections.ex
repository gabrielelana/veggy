defmodule Veggy.Projections do
  # TODO: this module must rule all projections

  def dispatch(%Plug.Conn{} = conn, projection_module, projection_name \\ nil) do
    case projection_module_named(projection_module) do
      {:ok, module} ->
        module.query(projection_name, conn.params)
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp projection_module_named(name) do
    try do
      name
      |> String.split("-")
      |> Enum.map_join(&Macro.camelize/1)
      |> (&[Veggy, Projection, &1]).()
      |> Module.safe_concat
      |> (&{:ok, &1}).()
    rescue
      ArgumentError -> {:error, :not_found}
    end
  end

end
