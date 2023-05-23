# LibclusterEcto

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `libcluster_ecto` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:libcluster_ecto, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/libcluster_ecto>.


# LibclusterEcto

Automatic cluster formation/healing for Elixir applications using database heartbeat.

This is a database heartbeat strategy for [libcluster](https://hexdocs.pm/libcluster/). It currently supports identifying nodes based on Mongodb.

## Installation

```elixir
def application do
  [
    applications: [
      :libcluster_ecto,
      ...
    ],
  ...
  ]

def deps do
  [{:libcluster_ecto, github: "robertov8/libcluster_ecto", branch: "main"}]
end
```

## An example configuration

The configuration for libcluster_ecto can also be described as a spec for the clustering topologies and strategies which will be used. (Now only Ecto heartbeat implementation.)

### Ecto
Ecto heartbeat implementation. We support this format to get the setting values from environment variables.

```elixir
config :libcluster,
  topologies: [
    example: [
      strategy: ClusterEcto.Strategy.Ecto,
      ecto_repo: Example.Repo,
      interval: 5000, 
      delay_tolerance: 1000
    ]
  ]
```

```elixir
# mix ecto.gen.migration create_libcluster_nodes

defmodule Example.Repo.Migrations.CreateLibclusterNodes do
  use Ecto.Migration

  def change do
    create table(:libcluster_nodes) do
      add :node_id, :string
      add :timestamp, :bigint

      timestamps()
    end

    create unique_index(:libcluster_nodes, [:node_id])
  end
end
```

fork [project](https://github.com/exosite/libcluster_db/blob/master/README.md)
