defmodule ClusterEcto.Nodes do
  import Ecto.Query

  alias ClusterEcto.Nodes.Node

  def upinsert(ecto_repo, attrs) do
    insert_opts = [
      conflict_target: :node_id,
      on_conflict: {:replace, [:node_id, :timestamp, :updated_at]}
    ]

    attrs
    |> Node.changeset()
    |> ecto_repo.insert(insert_opts)
  end

  def all(ecto_repo) do
    ecto_repo.all(Node)
  end

  def delete_all(ecto_repo, nodes) do
    Node
    |> from()
    |> where([l], l.node_id in ^nodes)
    |> ecto_repo.delete_all()
  end
end
