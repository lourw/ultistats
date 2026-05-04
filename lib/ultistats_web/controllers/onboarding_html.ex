defmodule UltistatsWeb.OnboardingHTML do
  use UltistatsWeb, :html

  import UltistatsWeb.UIComponents, only: [gender_radio: 1, position_radio: 1]

  embed_templates "onboarding_html/*"
end
