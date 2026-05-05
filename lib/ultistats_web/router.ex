defmodule UltistatsWeb.Router do
  use UltistatsWeb, :router

  import UltistatsWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {UltistatsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", UltistatsWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Team-join flow — public landing page (the recipient may not be
    # logged in yet). The POST handlers enforce auth themselves.
    get "/join/:token", TeamJoinController, :show
    get "/join/:token/claim/:membership_id", TeamJoinController, :claim_show
    post "/join/:token/claim/:membership_id", TeamJoinController, :claim
    post "/join/:token/create", TeamJoinController, :create
  end

  ## App routes — require an authenticated user

  # Onboarding is authed-only but intentionally NOT gated by
  # `require_complete_profile` — this is where the user fills the
  # profile out, so gating it would loop on itself.
  scope "/", UltistatsWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/onboarding/profile", OnboardingController, :edit
    put "/onboarding/profile", OnboardingController, :update
  end

  scope "/", UltistatsWeb do
    pipe_through [:browser, :require_authenticated_user, :require_complete_profile]

    get "/games/:id/summary.csv", StatsExportController, :game_summary
    get "/teams/:id/leaderboard.csv", StatsExportController, :team_leaderboard

    live_session :authenticated,
      on_mount: [{UltistatsWeb.UserAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive.Index, :index

      live "/teams", TeamLive.Index, :index
      live "/teams/new", TeamLive.Form, :new
      live "/teams/:id", TeamLive.Show, :show
      live "/teams/:id/edit", TeamLive.Form, :edit

      live "/members", MemberLive.Index, :index
      live "/members/new", MemberLive.Form, :new
      live "/members/:id/edit", MemberLive.Form, :edit
      live "/members/:id", MemberLive.Show, :show

      live "/line_presets", LinePresetLive.Index, :index
      live "/line_presets/new", LinePresetLive.Form, :new
      live "/line_presets/:id/edit", LinePresetLive.Form, :edit
      live "/line_presets/:id", LinePresetLive.Show, :show

      live "/rulesets/new", RulesetLive.Form, :new
      live "/rulesets/:id/edit", RulesetLive.Form, :edit
      live "/rulesets/:id", RulesetLive.Show, :show

      live "/games", GameLive.Index, :index
      live "/games/new", GameLive.Start, :new
      live "/games/:id", GameLive.Show, :show
      live "/games/:id/timeline", GameLive.Timeline, :index
      live "/games/:id/summary", GameLive.Summary, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", UltistatsWeb do
  #   pipe_through :api
  # end

  ## Authentication routes

  scope "/", UltistatsWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", UltistatsWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm-email/:token", UserSettingsController, :confirm_email
  end

  scope "/", UltistatsWeb do
    pipe_through [:browser]

    get "/users/log-in", UserSessionController, :new
    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  if Application.compile_env(:ultistats, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
