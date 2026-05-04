defmodule UltistatsWeb.UIComponents do
  @moduledoc """
  Project-specific UI primitives. These are the only components that
  feature LiveViews should reach for when composing the live game,
  line picker, and timeline screens.

  Conforms to `docs/UI_DESIGN.md`. Adding a sixth primitive requires a
  doc update — propose it in the same PR.

  Components:

    * `action_button/1`        primary in-game action (Goal / Assist / Block / Turn)
    * `event_type_button/1`    toggleable in-game-action-styled button for the timeline edit modal
    * `player_chip/1`          tappable jersey-and-name pill
    * `score_readout/1`        large tabular-nums score display
    * `line_preset_card/1`     selectable line preset, with ratio warning
    * `timeline_event/1`       one row in the post-game / mid-game timeline
    * `gender_radio/1`         two native radio inputs for the FMP/MMP picker
    * `position_radio/1`       three native radio inputs for handler/cutter/hybrid
    * `role_radio/1`           two native radio inputs for the membership role (admin/member)
    * `gender_ratio_radio/1`   four radio inputs for the ruleset gender-ratio rule

  All interactive components keep `phx-*` bindings via `:rest` global
  attrs, so callers wire them like any other Phoenix component.

  Theming note: the accent color is "TBD" per UI_DESIGN.md. We use the
  daisyUI `primary` token as the interim accent. Update both this module
  and the doc when the accent is finalized.
  """
  use Phoenix.Component

  import UltistatsWeb.CoreComponents, only: [icon: 1]

  ## ---------------------------------------------------------------------
  ## action_button
  ## ---------------------------------------------------------------------

  @doc """
  Primary in-game action button. Renders at min 56x56 (UI_DESIGN.md
  §Tap targets). Disabled state both *visually* dims and prevents taps
  via the native `disabled` attribute (UI_DESIGN.md §Connectivity loss).

  ## Examples

      <.action_button kind={:goal} phx-click="record_goal">Goal</.action_button>
      <.action_button kind={:turn} disabled?={@disconnected}>Turn</.action_button>
  """
  attr :kind, :atom, required: true, values: [:goal, :assist, :block, :turn]
  attr :disabled?, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-target form name value)

  slot :inner_block

  def action_button(assigns) do
    assigns = assign(assigns, :meta, action_button_meta(assigns.kind))

    ~H"""
    <button
      type="button"
      disabled={@disabled?}
      aria-label={@meta.label}
      class={[
        "min-h-14 min-w-14 px-4 py-3 rounded-xl",
        "flex flex-col items-center justify-center gap-1",
        "text-base font-semibold leading-tight",
        "transition-colors motion-reduce:transition-none",
        "active:scale-[0.98] motion-reduce:active:scale-100",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100",
        @meta.color_classes,
        @class
      ]}
      {@rest}
    >
      <.icon name={@meta.icon} class="size-6" />
      <span>{render_slot(@inner_block) || @meta.label}</span>
    </button>
    """
  end

  defp action_button_meta(:goal),
    do: %{
      label: "Goal",
      icon: "hero-trophy",
      color_classes: "bg-success text-success-content active:bg-success/80"
    }

  defp action_button_meta(:assist),
    do: %{
      label: "Assist",
      icon: "hero-hand-thumb-up",
      color_classes: "bg-info text-info-content active:bg-info/80"
    }

  defp action_button_meta(:block),
    do: %{
      label: "Block",
      icon: "hero-shield-check",
      color_classes: "bg-primary text-primary-content active:bg-primary/80"
    }

  defp action_button_meta(:turn),
    do: %{
      label: "Turn",
      icon: "hero-arrow-path-rounded-square",
      color_classes: "bg-error text-error-content active:bg-error/80"
    }

  ## ---------------------------------------------------------------------
  ## event_type_button
  ## ---------------------------------------------------------------------

  @doc """
  Toggleable, action-styled button for picking an event type in the
  timeline edit modal. Geometry matches `action_button/1` (icon over
  label, min 56x56) so the modal speaks the same visual language as
  the in-game action bar (UI_DESIGN.md §Components — reuse the existing
  vocabulary instead of inventing a new one for adjacent surfaces).

  When `selected?` is true the button renders in the type's functional
  color; unselected uses the neutral `base-100` shell with a 2px
  border so the type icons still read clearly.

  ## Examples

      <.event_type_button
        type={:goal}
        selected?={@edit_type == :goal}
        phx-click="set_edit_type"
        phx-value-type="goal"
      />
  """
  attr :type, :atom,
    required: true,
    values: [:goal, :catch, :drop, :throwaway, :stall, :block, :pick, :foul]

  attr :selected?, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-type phx-target form name value)

  def event_type_button(assigns) do
    assigns = assign(assigns, :meta, event_type_button_meta(assigns.type))

    ~H"""
    <button
      type="button"
      aria-label={@meta.label}
      aria-pressed={to_string(@selected?)}
      class={[
        "min-h-14 min-w-14 px-4 py-3 rounded-xl",
        "flex flex-col items-center justify-center gap-1",
        "text-base font-semibold leading-tight",
        "transition-colors motion-reduce:transition-none",
        "active:scale-[0.98] motion-reduce:active:scale-100",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        if(@selected?,
          do: ["border-2 border-transparent", @meta.selected_classes],
          else: "border-2 border-base-300 bg-base-100 text-base-content active:bg-base-200"
        ),
        @class
      ]}
      {@rest}
    >
      <.icon name={@meta.icon} class="size-6" />
      <span>{@meta.label}</span>
    </button>
    """
  end

  defp event_type_button_meta(:goal),
    do: %{
      label: "Goal",
      icon: "hero-trophy",
      selected_classes: "bg-success text-success-content"
    }

  defp event_type_button_meta(:catch),
    do: %{
      label: "Catch",
      icon: "hero-hand-raised",
      selected_classes: "bg-info text-info-content"
    }

  defp event_type_button_meta(:drop),
    do: %{
      label: "Drop",
      icon: "hero-hand-thumb-down",
      selected_classes: "bg-warning text-warning-content"
    }

  defp event_type_button_meta(:throwaway),
    do: %{
      label: "Throwaway",
      icon: "hero-arrow-uturn-left",
      selected_classes: "bg-error text-error-content"
    }

  defp event_type_button_meta(:stall),
    do: %{
      label: "Stall",
      icon: "hero-clock",
      selected_classes: "bg-error text-error-content"
    }

  defp event_type_button_meta(:block),
    do: %{
      label: "Block",
      icon: "hero-shield-check",
      selected_classes: "bg-primary text-primary-content"
    }

  defp event_type_button_meta(:pick),
    do: %{
      label: "Pick",
      icon: "hero-exclamation-triangle",
      selected_classes: "bg-warning text-warning-content"
    }

  defp event_type_button_meta(:foul),
    do: %{
      label: "Foul",
      icon: "hero-no-symbol",
      selected_classes: "bg-warning text-warning-content"
    }

  ## ---------------------------------------------------------------------
  ## player_chip
  ## ---------------------------------------------------------------------

  @doc """
  Tappable player identity pill. Min 44px height (UI_DESIGN.md
  §Tap targets). Shows jersey number + name. The `selected?` prop
  flips the pressed state (visual + `aria-pressed`).

  The `player` prop is a map; we read `:number`/`"number"` and
  `:name`/`"name"` so the component is friendly to both Ecto structs
  and bare maps in tests.

  ## Examples

      <.player_chip player={p} selected?={@selected_id == p.id} phx-click="toggle" phx-value-id={p.id} />
  """
  attr :player, :map, required: true
  attr :selected?, :boolean, default: false
  attr :disabled?, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-target form name value)

  def player_chip(assigns) do
    assigns =
      assigns
      |> assign(:player_number, fetch(assigns.player, :number))
      |> assign(:player_name, fetch(assigns.player, :name))

    ~H"""
    <button
      type="button"
      disabled={@disabled?}
      aria-pressed={to_string(@selected?)}
      aria-label={"Player #{@player_number} #{@player_name}"}
      data-selected={to_string(@selected?)}
      class={[
        "min-h-11 min-w-11 px-3 py-2 rounded-full",
        "inline-flex items-center gap-2",
        "text-base font-medium",
        "border-2 transition-colors motion-reduce:transition-none",
        "active:scale-[0.98] motion-reduce:active:scale-100",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        if(@selected?,
          do: "bg-primary text-primary-content border-primary",
          else: "bg-base-100 text-base-content border-base-300 active:bg-base-200"
        ),
        @class
      ]}
      {@rest}
    >
      <span
        class={[
          "tabular-nums font-semibold inline-flex items-center justify-center",
          "size-7 rounded-full text-sm",
          if(@selected?,
            do: "bg-primary-content/20 text-primary-content",
            else: "bg-base-200 text-base-content"
          )
        ]}
        aria-hidden="true"
      >
        {@player_number}
      </span>
      <span class="truncate">{@player_name}</span>
      <.icon
        :if={@selected?}
        name="hero-check-circle-solid"
        class="size-5 ml-1"
      />
    </button>
    """
  end

  ## ---------------------------------------------------------------------
  ## score_readout
  ## ---------------------------------------------------------------------

  @doc """
  Large tabular-nums score display (UI_DESIGN.md §Typography). The
  `accent` prop highlights whichever side just scored — `:ours`,
  `:theirs`, or `nil` for the neutral pre-game state.

  ## Examples

      <.score_readout our_score={5} their_score={3} accent={:ours} />
  """
  attr :our_score, :integer, required: true
  attr :their_score, :integer, required: true
  attr :accent, :atom, default: nil, values: [:ours, :theirs, nil]
  attr :our_label, :string, default: "Us"
  attr :their_label, :string, default: "Them"
  attr :class, :any, default: nil

  def score_readout(assigns) do
    ~H"""
    <div
      class={["flex items-baseline gap-3", @class]}
      role="status"
      aria-label={"Score #{@our_label} #{@our_score}, #{@their_label} #{@their_score}"}
    >
      <div class="flex flex-col items-start">
        <span class="text-xs uppercase tracking-wide text-base-content/70">
          {@our_label}
        </span>
        <span class={[
          "tabular-nums font-bold text-4xl sm:text-5xl leading-none",
          @accent == :ours && "text-success",
          @accent != :ours && "text-base-content"
        ]}>
          {@our_score}
        </span>
      </div>
      <span class="tabular-nums text-2xl text-base-content/40 font-bold leading-none">
        :
      </span>
      <div class="flex flex-col items-start">
        <span class="text-xs uppercase tracking-wide text-base-content/70">
          {@their_label}
        </span>
        <span class={[
          "tabular-nums font-bold text-4xl sm:text-5xl leading-none",
          @accent == :theirs && "text-success",
          @accent != :theirs && "text-base-content"
        ]}>
          {@their_score}
        </span>
      </div>
    </div>
    """
  end

  ## ---------------------------------------------------------------------
  ## line_preset_card
  ## ---------------------------------------------------------------------

  @doc """
  Selectable line preset card shown before a point. When
  `gender_warning?` is true, an amber badge is shown — color *and* an
  icon *and* a label, per UI_DESIGN.md §Color (no signal-by-color-alone).

  The `preset` map should expose `:name` and either `:player_count` or
  a `:players` list we can count.
  """
  attr :preset, :map, required: true
  attr :selected?, :boolean, default: false
  attr :gender_warning?, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id phx-target form name value)

  def line_preset_card(assigns) do
    name = fetch(assigns.preset, :name)
    count = fetch(assigns.preset, :player_count) || count_players(assigns.preset)

    assigns =
      assigns
      |> assign(:preset_name, name)
      |> assign(:player_count, count)

    ~H"""
    <button
      type="button"
      aria-pressed={to_string(@selected?)}
      aria-label={"Line preset #{@preset_name}, #{@player_count} players"}
      data-selected={to_string(@selected?)}
      class={[
        "min-h-14 w-full text-left rounded-xl border-2 p-4",
        "flex items-center gap-3",
        "transition-colors motion-reduce:transition-none",
        "active:scale-[0.99] motion-reduce:active:scale-100",
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
        if(@selected?,
          do: "bg-primary text-primary-content border-primary",
          else: "bg-base-100 text-base-content border-base-300 active:bg-base-200"
        ),
        @class
      ]}
      {@rest}
    >
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-semibold text-base truncate">{@preset_name}</span>
          <.icon
            :if={@selected?}
            name="hero-check-circle-solid"
            class="size-5 shrink-0"
          />
        </div>
        <div class="text-sm opacity-80 tabular-nums">
          {@player_count} players
        </div>
      </div>
      <span
        :if={@gender_warning?}
        class="inline-flex items-center gap-1 rounded-full bg-warning text-warning-content text-xs font-semibold px-2 py-1 shrink-0"
        role="status"
      >
        <.icon name="hero-exclamation-triangle-solid" class="size-4" /> Ratio mismatch
      </span>
    </button>
    """
  end

  defp count_players(preset) do
    case fetch(preset, :players) do
      list when is_list(list) -> length(list)
      _ -> 0
    end
  end

  ## ---------------------------------------------------------------------
  ## timeline_event
  ## ---------------------------------------------------------------------

  @doc """
  One row in the timeline view. Shows event type icon, player label,
  and timestamp. When `editable?` is true, an edit affordance is
  rendered (and the optional `:actions` slot can render menu items).

  The `event` map should expose:

    * `:type`         one of `:goal | :assist | :block | :turn | :pull`
    * `:player_label` text to show (e.g. "#7 Sam")
    * `:timestamp`    pre-formatted string (e.g. "12:04")
    * `:point_label`  optional, e.g. "P3"
  """
  attr :event, :map, required: true
  attr :editable?, :boolean, default: false
  attr :class, :any, default: nil
  attr :rest, :global

  slot :actions,
    doc: "optional action menu shown when editable? is true (e.g. edit/delete buttons)"

  def timeline_event(assigns) do
    type = fetch(assigns.event, :type) || :goal
    meta = timeline_meta(type)

    assigns =
      assigns
      |> assign(:type, type)
      |> assign(:meta, meta)
      |> assign(:player_label, fetch(assigns.event, :player_label))
      |> assign(:timestamp, fetch(assigns.event, :timestamp))
      |> assign(:point_label, fetch(assigns.event, :point_label))

    ~H"""
    <div
      class={["min-h-9 flex items-center gap-2 px-4 py-0.5", @class]}
      data-event-type={@type}
      {@rest}
    >
      <span
        class={[
          "size-6 shrink-0 rounded-full inline-flex items-center justify-center",
          @meta.color_classes
        ]}
        aria-hidden="true"
      >
        <.icon name={@meta.icon} class="size-4" />
      </span>
      <span class="text-sm font-semibold shrink-0">{@meta.label}</span>
      <span :if={@point_label} class="text-[11px] text-base-content/60 tabular-nums shrink-0">
        {@point_label}
      </span>
      <span class="flex-1 text-sm text-base-content/80 truncate leading-tight">
        {@player_label}
      </span>
      <time class="text-[11px] text-base-content/60 tabular-nums shrink-0">{@timestamp}</time>
      <div :if={@editable?} class="shrink-0">
        <%= if @actions != [] do %>
          {render_slot(@actions, @event)}
        <% else %>
          <button
            type="button"
            class="min-h-9 min-w-9 inline-flex items-center justify-center rounded-md text-base-content/70 active:bg-base-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            aria-label={"Edit #{@meta.label} event"}
          >
            <.icon name="hero-ellipsis-horizontal" class="size-4" />
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  defp timeline_meta(:goal),
    do: %{
      label: "Goal",
      icon: "hero-trophy",
      color_classes: "bg-success text-success-content"
    }

  defp timeline_meta(:assist),
    do: %{
      label: "Assist",
      icon: "hero-hand-thumb-up",
      color_classes: "bg-info text-info-content"
    }

  defp timeline_meta(:block),
    do: %{
      label: "Block",
      icon: "hero-shield-check",
      color_classes: "bg-primary text-primary-content"
    }

  defp timeline_meta(:turn),
    do: %{
      label: "Turn",
      icon: "hero-arrow-path-rounded-square",
      color_classes: "bg-error text-error-content"
    }

  defp timeline_meta(:pull),
    do: %{
      label: "Pull",
      icon: "hero-paper-airplane",
      color_classes: "bg-base-300 text-base-content"
    }

  defp timeline_meta(:catch),
    do: %{
      label: "Catch",
      icon: "hero-check",
      color_classes: "bg-success text-success-content"
    }

  defp timeline_meta(:drop),
    do: %{
      label: "Drop",
      icon: "hero-arrow-down-tray",
      color_classes: "bg-error text-error-content"
    }

  defp timeline_meta(:throwaway),
    do: %{
      label: "Throwaway",
      icon: "hero-arrow-path-rounded-square",
      color_classes: "bg-error text-error-content"
    }

  defp timeline_meta(:stall),
    do: %{
      label: "Stall",
      icon: "hero-clock",
      color_classes: "bg-error text-error-content"
    }

  defp timeline_meta(:opponent_turnover),
    do: %{
      label: "Turnover",
      icon: "hero-arrow-uturn-right",
      color_classes: "bg-success text-success-content"
    }

  defp timeline_meta(:opponent_goal),
    do: %{
      label: "They scored",
      icon: "hero-flag",
      color_classes: "bg-error text-error-content"
    }

  defp timeline_meta(:pick),
    do: %{
      label: "Pick",
      icon: "hero-hand-raised",
      color_classes: "bg-base-300 text-base-content"
    }

  defp timeline_meta(:foul),
    do: %{
      label: "Foul",
      icon: "hero-exclamation-triangle",
      color_classes: "bg-base-300 text-base-content"
    }

  defp timeline_meta(:timeout_ours),
    do: %{
      label: "Timeout (us)",
      icon: "hero-pause",
      color_classes: "bg-warning text-warning-content"
    }

  defp timeline_meta(:timeout_theirs),
    do: %{
      label: "Timeout (them)",
      icon: "hero-pause",
      color_classes: "bg-warning text-warning-content"
    }

  defp timeline_meta(:timeout_resume),
    do: %{
      label: "Resume",
      icon: "hero-play",
      color_classes: "bg-base-300 text-base-content"
    }

  defp timeline_meta(:halftime),
    do: %{
      label: "Halftime",
      icon: "hero-flag",
      color_classes: "bg-warning text-warning-content"
    }

  defp timeline_meta(:halftime_resume),
    do: %{
      label: "Resume",
      icon: "hero-play",
      color_classes: "bg-base-300 text-base-content"
    }

  defp timeline_meta(_),
    do: %{
      label: "Event",
      icon: "hero-bolt",
      color_classes: "bg-base-300 text-base-content"
    }

  ## ---------------------------------------------------------------------
  ## gender_radio
  ## ---------------------------------------------------------------------

  @doc """
  Two native radio inputs side by side for picking a player's gender
  role (USAU FMP / MMP). Each radio is wrapped in a `<label>` so the
  full label area is tappable; both label rows are min-h-11 (44px) per
  UI_DESIGN.md §Tap targets.

  Both radios share the field's `name`, so the browser groups them and
  emits one selected value on form submission. Selection feedback is
  the browser's native radio "checked" state — no custom segmented
  styling.

  Like `gender_toggle/1` did, this component forwards `phx-*`
  attributes through `:rest`, so callers can wire `phx-click` (with a
  `phx-value-row` for the bulk-add form) to drive a server-side
  `set_gender` handler. On Phoenix forms with `phx-change="validate"`,
  selection naturally fires the form's change event too.

  ## Examples

      <.gender_radio field={@form[:gender_role]} phx-click="set_gender" />
      <.gender_radio field={f[:gender_role]} phx-click="set_gender" phx-value-row={row.key} />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-change phx-click phx-target form)

  def gender_radio(assigns) do
    value = normalize_gender_value(assigns.field.value)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:input_name, assigns.field.name)
      |> assign(:input_id, assigns.field.id)

    ~H"""
    <fieldset class={["space-y-1", @class]}>
      <legend class="sr-only">Gender role</legend>
      <div class="inline-flex items-center gap-3" role="radiogroup" aria-label="Gender role">
        <label class={gender_radio_label_classes(@value == "male_matching")}>
          <input
            type="radio"
            name={@input_name}
            id={"#{@input_id}_male_matching"}
            value="male_matching"
            checked={@value == "male_matching"}
            class="accent-primary size-5 shrink-0"
            {@rest}
            phx-value-gender="male_matching"
          />
          <span class="text-lg leading-none" aria-hidden="true">♂</span>
          <span class="sr-only">Male-matching</span>
        </label>
        <label class={gender_radio_label_classes(@value == "female_matching")}>
          <input
            type="radio"
            name={@input_name}
            id={"#{@input_id}_female_matching"}
            value="female_matching"
            checked={@value == "female_matching"}
            class="accent-primary size-5 shrink-0"
            {@rest}
            phx-value-gender="female_matching"
          />
          <span class="text-lg leading-none" aria-hidden="true">♀</span>
          <span class="sr-only">Female-matching</span>
        </label>
      </div>
    </fieldset>
    """
  end

  defp gender_radio_label_classes(selected?) do
    [
      "min-h-11 inline-flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium",
      "border border-base-300 cursor-pointer select-none",
      "focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-primary",
      if(selected?,
        do: "bg-primary/10 border-primary text-base-content",
        else: "bg-base-100 text-base-content active:bg-base-200"
      )
    ]
  end

  defp normalize_gender_value(nil), do: nil
  defp normalize_gender_value(""), do: nil
  defp normalize_gender_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_gender_value(value) when is_binary(value), do: value

  ## ---------------------------------------------------------------------
  ## position_radio
  ## ---------------------------------------------------------------------

  @doc """
  Three native radio inputs side by side for picking a player's
  position (Handler / Cutter / Hybrid). Mirrors `gender_radio/1`:
  shared `name`, label-wrapped inputs with min-h-11 tap targets, and a
  `:rest` passthrough for `phx-*` attrs (e.g. `phx-click="set_position"`
  with `phx-value-row` for bulk forms).

  ## Examples

      <.position_radio field={@form[:position]} phx-click="set_position_edit" />
      <.position_radio field={f[:position]} phx-click="set_position" phx-value-row={row.key} />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-change phx-click phx-target form)

  def position_radio(assigns) do
    value = normalize_position_value(assigns.field.value)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:input_name, assigns.field.name)
      |> assign(:input_id, assigns.field.id)
      |> assign(:options, [
        {"handler", "Handler", "hero-paper-airplane"},
        {"cutter", "Cutter", "hero-bolt"},
        {"hybrid", "Hybrid", "hero-arrows-right-left"}
      ])

    ~H"""
    <fieldset class={["space-y-1", @class]}>
      <legend class="sr-only">Position</legend>
      <div class="grid grid-cols-3 gap-2" role="radiogroup" aria-label="Position">
        <label
          :for={{val, label, icon} <- @options}
          class={position_button_classes()}
        >
          <input
            type="radio"
            name={@input_name}
            id={"#{@input_id}_#{val}"}
            value={val}
            checked={@value == val}
            class="sr-only peer"
            {@rest}
            phx-value-position={val}
          />
          <.icon name={icon} class="size-4" />
          <span>{label}</span>
        </label>
      </div>
    </fieldset>
    """
  end

  defp position_button_classes do
    [
      "min-h-11 px-3 py-1.5 rounded-lg cursor-pointer select-none",
      "inline-flex items-center justify-center gap-1.5",
      "text-sm font-semibold",
      "transition-colors motion-reduce:transition-none",
      "border border-base-300 bg-base-100 text-base-content active:bg-base-200",
      "has-[:checked]:bg-primary has-[:checked]:text-primary-content",
      "has-[:checked]:border-transparent has-[:checked]:active:bg-primary/80",
      "focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-primary"
    ]
  end

  defp position_radio_label_classes(selected?) do
    [
      "min-h-11 inline-flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-medium",
      "border border-base-300 cursor-pointer select-none",
      "focus-within:outline-2 focus-within:outline-offset-2 focus-within:outline-primary",
      if(selected?,
        do: "bg-primary/10 border-primary text-base-content",
        else: "bg-base-100 text-base-content active:bg-base-200"
      )
    ]
  end

  defp normalize_position_value(nil), do: nil
  defp normalize_position_value(""), do: nil
  defp normalize_position_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_position_value(value) when is_binary(value), do: value

  ## ---------------------------------------------------------------------
  ## role_radio
  ## ---------------------------------------------------------------------

  @doc """
  Two native radio inputs side by side for picking a member's
  team-membership role (Admin / Member). Mirrors `gender_radio/1` and
  `position_radio/1`: shared `name`, label-wrapped inputs with min-h-11
  tap targets, and a `:rest` passthrough for `phx-*` attrs (e.g.
  `phx-click="set_role"`).

  ## Examples

      <.role_radio field={@form[:role]} phx-click="set_role" />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-change phx-click phx-target form)

  def role_radio(assigns) do
    value = normalize_role_value(assigns.field.value)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:input_name, assigns.field.name)
      |> assign(:input_id, assigns.field.id)
      |> assign(:options, [
        {"admin", "Admin"},
        {"member", "Member"}
      ])

    ~H"""
    <fieldset class={["space-y-1", @class]}>
      <legend class="sr-only">Role</legend>
      <div class="inline-flex flex-wrap items-center gap-2" role="radiogroup" aria-label="Role">
        <label
          :for={{val, label} <- @options}
          class={position_radio_label_classes(@value == val)}
        >
          <input
            type="radio"
            name={@input_name}
            id={"#{@input_id}_#{val}"}
            value={val}
            checked={@value == val}
            class="accent-primary size-5 shrink-0"
            {@rest}
            phx-value-role={val}
          />
          <span class="text-sm leading-none">{label}</span>
        </label>
      </div>
    </fieldset>
    """
  end

  defp normalize_role_value(nil), do: "member"
  defp normalize_role_value(""), do: "member"
  defp normalize_role_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_role_value(value) when is_binary(value), do: value

  ## ---------------------------------------------------------------------
  ## gender_ratio_radio
  ## ---------------------------------------------------------------------

  @doc """
  Four native radio inputs side by side for picking a ruleset's gender
  ratio rule. Mirrors `position_radio/1`: shared `name`, label-wrapped
  inputs with min-h-11 tap targets, and a `:rest` passthrough for
  `phx-*` attrs (e.g. `phx-click="set_ratio_rule"`).

  Options: Endzone / Alternating / Fixed / None.

  ## Examples

      <.gender_ratio_radio field={@form[:gender_ratio_rule]} phx-click="set_ratio_rule" />
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(phx-change phx-click phx-target form)

  def gender_ratio_radio(assigns) do
    value = normalize_ratio_value(assigns.field.value)

    assigns =
      assigns
      |> assign(:value, value)
      |> assign(:input_name, assigns.field.name)
      |> assign(:input_id, assigns.field.id)
      |> assign(:options, [
        {"endzone", "Endzone"},
        {"alternating", "Alternating"},
        {"fixed", "Fixed"},
        {"none", "None"}
      ])

    ~H"""
    <fieldset class={["space-y-1", @class]}>
      <legend class="sr-only">Gender ratio rule</legend>
      <div
        class="inline-flex flex-wrap items-center gap-2"
        role="radiogroup"
        aria-label="Gender ratio rule"
      >
        <label
          :for={{val, label} <- @options}
          class={position_radio_label_classes(@value == val)}
        >
          <input
            type="radio"
            name={@input_name}
            id={"#{@input_id}_#{val}"}
            value={val}
            checked={@value == val}
            class="accent-primary size-5 shrink-0"
            {@rest}
            phx-value-rule={val}
          />
          <span class="text-sm leading-none">{label}</span>
        </label>
      </div>
    </fieldset>
    """
  end

  defp normalize_ratio_value(nil), do: nil
  defp normalize_ratio_value(""), do: nil
  defp normalize_ratio_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_ratio_value(value) when is_binary(value), do: value

  ## ---------------------------------------------------------------------
  ## helpers
  ## ---------------------------------------------------------------------

  # Read a field from a struct or a string-keyed map. Lets templates and
  # tests pass plain maps without ceremony.
  defp fetch(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end
end
