defmodule UltistatsWeb.Router do
  use UltistatsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UltistatsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", UltistatsWeb do
    pipe_through :browser

    get "/", PageController, :home

    live "/teams", TeamLive.Index, :index
    live "/teams/new", TeamLive.Form, :new
    live "/teams/:id", TeamLive.Show, :show
    live "/teams/:id/edit", TeamLive.Form, :edit

    live "/players", PlayerLive.Index, :index
    live "/players/new", PlayerLive.Form, :new
    live "/players/:id/edit", PlayerLive.Form, :edit
    live "/players/:id", PlayerLive.Show, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", UltistatsWeb do
  #   pipe_through :api
  # end
end
