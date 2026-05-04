defmodule Ultistats.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :ultistats

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn r ->
            Ecto.Migrator.run(r, :up, all: true)
            do_seed_system_rulesets()
          end,
          migrator_opts()
        )
    end
  end

  @doc """
  Idempotently upserts the global (system) rulesets — one row per
  entry in `Ultistats.Release.SystemRulesets.all/0`, all with
  `team_id: nil`. Safe to call repeatedly.

  When invoked from a context where the Repo is already running (dev
  `mix run priv/repo/seeds.exs`, tests), the upserts run directly
  against the live Repo. Otherwise we start the Repo via
  `Ecto.Migrator.with_repo/3` for the duration of the seed.
  """
  def seed_system_rulesets do
    load_app()

    if repo_running?() do
      do_seed_system_rulesets()
    else
      for repo <- repos() do
        {:ok, _, _} =
          Ecto.Migrator.with_repo(repo, fn _ -> do_seed_system_rulesets() end, migrator_opts())
      end
    end

    :ok
  end

  defp repo_running? do
    case Process.whereis(Ultistats.Repo) do
      nil -> false
      pid when is_pid(pid) -> true
    end
  end

  defp do_seed_system_rulesets do
    Enum.each(Ultistats.Release.SystemRulesets.all(), &upsert_system_ruleset/1)
  end

  defp upsert_system_ruleset(%{name: name} = attrs) do
    import Ecto.Query, only: [from: 2]

    query = from r in Ultistats.Games.Ruleset, where: r.name == ^name and is_nil(r.team_id)

    case Ultistats.Repo.one(query) do
      nil ->
        %Ultistats.Games.Ruleset{}
        |> Ultistats.Games.Ruleset.changeset(attrs)
        |> Ultistats.Repo.insert!()

      existing ->
        existing
        |> Ultistats.Games.Ruleset.changeset(attrs)
        |> Ultistats.Repo.update!()
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version), migrator_opts())
  end

  # Migrations need a session-mode connection (direct Postgres, port 5432),
  # not the Supabase transaction-mode pooler. Prefer MIGRATION_DATABASE_URL
  # when set; fall back to the app's DATABASE_URL otherwise.
  defp migrator_opts do
    case System.get_env("MIGRATION_DATABASE_URL") do
      nil -> []
      "" -> []
      url -> [url: url, prepare: :named, pool_size: 2]
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
