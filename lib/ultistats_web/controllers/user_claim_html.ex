defmodule UltistatsWeb.UserClaimHTML do
  @moduledoc """
  Templates for the public stub-claim flow rendered by
  `UltistatsWeb.UserClaimController`.
  """
  use UltistatsWeb, :html

  alias Ultistats.Accounts.User

  embed_templates "user_claim_html/*"
end
