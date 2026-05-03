defmodule Ultistats.Repo do
  use Ecto.Repo,
    otp_app: :ultistats,
    adapter:
      Application.compile_env(:ultistats, [Ultistats.Repo, :adapter], Ecto.Adapters.SQLite3)
end
