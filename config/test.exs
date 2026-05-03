import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# `POSTGRES_PORT` is set per-worktree by `bin/db` (see docker-compose.yml) so
# multiple worktrees can run their own Postgres in parallel without colliding
# on 5432. The port is pinned in .env; load it here so `mix test` picks up
# the right port without needing the shell to source .env first.
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
postgres_port =
  System.get_env("POSTGRES_PORT") ||
    case File.read(Path.expand("../.env", __DIR__)) do
      {:ok, contents} ->
        Regex.run(~r/^POSTGRES_PORT=(\d+)/m, contents, capture: :all_but_first)
        |> case do
          [port] -> port
          _ -> "5432"
        end

      _ ->
        "5432"
    end

config :ultistats, Ultistats.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(postgres_port),
  database: "ultistats_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ultistats, UltistatsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "O/UuhLb61i5NqumpW1Pdwkl/fb0QmoLaIG14JDB7qqThie+Bmp9Z/1xSgNAnFyx2",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
