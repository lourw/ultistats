defmodule UltistatsWeb.PageController do
  use UltistatsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
