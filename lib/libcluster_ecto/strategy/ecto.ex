defmodule ClusterEcto.Strategy.Ecto do
  use GenServer
  use Cluster.Strategy

  alias Cluster.Strategy.State
  alias ClusterEcto.Nodes

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init([%State{} = state] = _opts) do
    Process.flag(:trap_exit, true)

    ecto_repo = Keyword.get(state.config, :ecto_repo)
    interval = Keyword.get(state.config, :interval, 5000)
    delay_tolerance = Keyword.get(state.config, :delay_tolerance, 1000)

    state =
      Map.put(state, :meta, %{
        ecto_repo: ecto_repo,
        last_timestamp: timestamp(),
        max_heartbeat_age: (interval + delay_tolerance) * 1000,
        nodes_scan_job: nil,
        node_id: node(),
        interval: interval,
        last_nodes: MapSet.new([])
      })

    Process.send_after(self(), :heartbeat, interval)

    {:ok, state}
  end

  @impl GenServer
  def handle_info(
        :heartbeat,
        %State{
          meta: %{
            ecto_repo: ecto_repo,
            last_timestamp: last_timestamp,
            max_heartbeat_age: max_heartbeat_age,
            nodes_scan_job: nodes_scan_job,
            node_id: node_id,
            interval: interval
          }
        } = state
      ) do
    case timestamp() do
      timestamp when timestamp < last_timestamp + max_heartbeat_age ->
        Process.send_after(self(), :heartbeat, interval)

        node_opts = %{
          node_id: Atom.to_string(node_id),
          timestamp: timestamp
        }

        ecto_repo
        |> Nodes.upinsert(node_opts)
        |> case do
          {:ok, _node} ->
            update_state_scan_nodes(nodes_scan_job, state, timestamp, max_heartbeat_age)

          {:error, _error} ->
            Cluster.Logger.error(" Heartbeat failure", "")
            {:noreply, state}
        end

      timestamp ->
        Cluster.Logger.error(
          " Heartbeat lagging by #{div(timestamp - last_timestamp, 1_000_000)}s",
          ""
        )

        {:noreply, state}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, pid, scan_result},
        %{meta: %{nodes_scan_job: {pid, ref}}} = state
      ) do
    case scan_result do
      {:ok, good_nodes_map} ->
        {:noreply, load(good_nodes_map, state)}

      error ->
        Cluster.Logger.error(" Nodes scan job failed: #{inspect(error)}", "")
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Cluster.Logger.warn("msg: #{inspect(msg)}, state: #{inspect(state)}", "Unknown msg")
    {:noreply, state}
  end

  defp update_state_scan_nodes(
         nodes_scan_job,
         %State{meta: meta} = state,
         timestamp,
         max_heartbeat_age
       ) do
    case nodes_scan_job do
      nil ->
        nodes_scan_job =
          spawn_monitor(fn ->
            reason = scan_nodes(meta, timestamp, max_heartbeat_age)
            Process.exit(self(), reason)
          end)

        meta = %{meta | last_timestamp: timestamp, nodes_scan_job: nodes_scan_job}
        {:noreply, %{state | meta: meta}}

      _ ->
        {:noreply, %{state | meta: %{meta | last_timestamp: timestamp}}}
    end
  end

  defp scan_nodes(meta, timestamp, max_heartbeat_age) do
    initial_value = {MapSet.new(), MapSet.new()}

    meta.ecto_repo
    |> Nodes.all()
    |> Enum.reduce(initial_value, &get_good_and_bad_nodes(&1, &2, timestamp, max_heartbeat_age))
    |> do_scan_nodes(meta)
  end

  def do_scan_nodes({good_nodes_map, bad_nodes_map}, meta) do
    bad_nodes_map
    |> MapSet.to_list()
    |> remove_dead_node(meta)
    |> case do
      :ok -> {:ok, good_nodes_map}
      :error -> :error
    end
  end

  defp get_good_and_bad_nodes(
         %{timestamp: node_timestamp} = node,
         {good_acc, bad_acc},
         timestamp,
         max_heartbeat_age
       )
       when node_timestamp < timestamp - max_heartbeat_age do
    {good_acc, MapSet.put(bad_acc, node.node_id)}
  end

  defp get_good_and_bad_nodes(
         %{node_id: node_id},
         {good_acc, bad_acc},
         _timestamp,
         _max_heartbeat_age
       ) do
    {MapSet.put(good_acc, String.to_atom(node_id)), bad_acc}
  end

  defp remove_dead_node([], _meta), do: :ok

  defp remove_dead_node(dead_nodes, %{ecto_repo: ecto_repo}) do
    ecto_repo
    |> Nodes.delete_all(dead_nodes)
    |> case do
      {_, nil} ->
        :ok

      reason ->
        Cluster.Logger.error(" remove_dead_nodes error: #{inspect(reason)}", "")
        :error
    end
  end

  defp load(good_nodes_map, %State{meta: %{last_nodes: last_nodes_map} = meta} = state) do
    new_nodelist = good_nodes_map
    added = MapSet.difference(good_nodes_map, last_nodes_map)
    removed = MapSet.difference(last_nodes_map, good_nodes_map)

    new_nodelist = cluster_disconnect_nodes(state, removed, new_nodelist)
    new_nodelist = cluster_connect_nodes(state, added, new_nodelist)

    %{state | meta: %{meta | last_nodes: new_nodelist, nodes_scan_job: nil}}
  end

  defp cluster_disconnect_nodes(%State{} = state, removed, new_nodelist) do
    case Cluster.Strategy.disconnect_nodes(
           state.topology,
           state.disconnect,
           state.list_nodes,
           MapSet.to_list(removed)
         ) do
      :ok ->
        new_nodelist

      {:error, bad_nodes} ->
        # Add back the nodes which should have been removed, but which couldn't be for some reason
        Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
          MapSet.put(acc, n)
        end)
    end
  end

  defp cluster_connect_nodes(%State{} = state, added, new_nodelist) do
    case Cluster.Strategy.connect_nodes(
           state.topology,
           state.connect,
           state.list_nodes,
           MapSet.to_list(added)
         ) do
      :ok ->
        new_nodelist

      {:error, bad_nodes} ->
        # Remove the nodes which should have been added, but couldn't be for some reason
        Enum.reduce(bad_nodes, new_nodelist, fn {n, _}, acc ->
          MapSet.delete(acc, n)
        end)
    end
  end

  defp timestamp(), do: :erlang.system_time(:microsecond)
end
