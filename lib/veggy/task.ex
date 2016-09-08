defmodule Veggy.Task do
  def extract_tags(description) do
    Regex.scan(~r/#(\w+(?:[>+]\w+)*)/, description)
    |> Enum.map(&List.last/1)
    |> Enum.map(&do_explode_tag/1)
    |> List.flatten
    |> Enum.sort
    |> Enum.uniq
  end

  defp do_explode_tag(tag) do
    cond do
      String.contains?(tag, ">") ->
        do_explode_tag(">", [], String.split(tag, ">"), [])
      String.contains?(tag, "+") ->
        do_explode_tag("+", [], String.split(tag, "+"), [])
      true ->
        tag
    end
  end

  defp do_explode_tag(_, _, [], result), do: result
  defp do_explode_tag("+", base, [tag|rest], result) do
    base = [tag|base]
    composed = base |> Enum.reverse |> Enum.join(">")
    do_explode_tag("+", base, rest, [tag,composed|result])
  end
  defp do_explode_tag(">", base, [tag|rest], result) do
    base = [tag|base]
    composed = base |> Enum.reverse |> Enum.join(">")
    do_explode_tag(">", base, rest, [composed|result])
  end

end
