defmodule UltistatsWeb.TeamJoinHTML do
  @moduledoc """
  Templates for the public team-join flow rendered by
  `UltistatsWeb.TeamJoinController`.
  """
  use UltistatsWeb, :html

  import UltistatsWeb.UIComponents, only: [gender_radio: 1, position_radio: 1]

  alias Ultistats.Accounts.User
  alias Ultistats.Teams

  embed_templates "team_join_html/*"
end
