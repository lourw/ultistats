defmodule UltistatsWeb.UserSettingsHTML do
  use UltistatsWeb, :html

  import UltistatsWeb.UIComponents, only: [gender_radio: 1, position_radio: 1]

  embed_templates "user_settings_html/*"

  def settings_tab_classes(true),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-primary border-b-2 border-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"

  def settings_tab_classes(false),
    do:
      "min-h-11 inline-flex items-center pb-3 -mb-px text-sm font-medium text-base-content/60 hover:text-base-content border-b-2 border-transparent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
end
