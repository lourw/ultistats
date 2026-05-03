defmodule Ultistats.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        UltistatsWeb.Telemetry,
        Ultistats.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:ultistats, :ecto_repos), skip: skip_migrations?()},
        seed_child_spec(),
        {DNSCluster, query: Application.get_env(:ultistats, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Ultistats.PubSub},
        # Start a worker by calling: Ultistats.Worker.start_link(arg)
        # {Ultistats.Worker, arg},
        # Start to serve requests, typically the last entry
        UltistatsWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ultistats.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UltistatsWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  # Returns a child spec that runs `priv/repo/seeds.exs` once at boot, or
  # `nil` to skip seeding. Seeds are gated by the `:seed_on_start`
  # application env (set true in `config/dev.exs` only). The seed script
  # is itself idempotent — re-runs are no-ops when data already exists.
  defp seed_child_spec do
    if Application.get_env(:ultistats, :seed_on_start, false) do
      {Task,
       fn ->
         seeds_path = Path.join(:code.priv_dir(:ultistats), "repo/seeds.exs")

         if File.exists?(seeds_path) do
           Code.eval_file(seeds_path)
         end
       end}
    end
  end
end
