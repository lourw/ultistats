defmodule UltistatsWeb.PageControllerTest do
  use UltistatsWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Ultistats"
  end
end
