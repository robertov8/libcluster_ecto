defmodule ClusterEcto.Nodes.Node do
  use Ecto.Schema

  import Ecto.Changeset

  @required_fields ~w(node_id timestamp)a

  schema "libcluster_nodes" do
    field(:node_id, :string)
    field(:timestamp, :integer)

    timestamps()
  end

  def changeset(attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end
