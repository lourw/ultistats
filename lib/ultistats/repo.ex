defmodule Ultistats.Repo do
  use Ecto.Repo,
    otp_app: :ultistats,
    adapter: Ecto.Adapters.Postgres
end
