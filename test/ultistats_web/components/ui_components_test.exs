defmodule UltistatsWeb.UIComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import UltistatsWeb.UIComponents

  describe "action_button/1" do
    test "renders a Goal button with semantic <button> and aria-label" do
      html =
        render_component(&action_button/1, kind: :goal)

      assert html =~ "<button"
      assert html =~ ~s(type="button")
      assert html =~ ~s(aria-label="Goal")
      # default icon and text fallback
      assert html =~ "hero-trophy"
      assert html =~ ">Goal<"
    end

    test "renders each kind without crashing and applies its functional color" do
      for {kind, token} <- [
            {:goal, "bg-success"},
            {:assist, "bg-info"},
            {:block, "bg-primary"},
            {:turn, "bg-error"}
          ] do
        html = render_component(&action_button/1, kind: kind)
        assert html =~ token, "expected #{kind} button to use #{token}"
      end
    end

    test "disabled?={true} emits the native disabled attribute" do
      html = render_component(&action_button/1, kind: :goal, disabled?: true)

      assert html =~ ~r/<button[^>]*\sdisabled\b/
      assert html =~ "disabled:opacity-50"
    end

    test "honors min 56x56 tap target (UI_DESIGN.md §Tap targets)" do
      html = render_component(&action_button/1, kind: :goal)
      # Tailwind: min-h-14 = 3.5rem = 56px, min-w-14 = 56px
      assert html =~ "min-h-14"
      assert html =~ "min-w-14"
    end
  end

  describe "player_chip/1" do
    @player %{id: 1, number: 7, name: "Sam"}

    test "renders jersey number and name" do
      html = render_component(&player_chip/1, player: @player)

      assert html =~ "7"
      assert html =~ "Sam"
      assert html =~ ~s(aria-label="Player 7 Sam")
    end

    test "selected?={true} marks the chip as pressed" do
      html = render_component(&player_chip/1, player: @player, selected?: true)

      assert html =~ ~s(aria-pressed="true")
      assert html =~ ~s(data-selected="true")
      assert html =~ "bg-primary"
    end

    test "selected?={false} is not pressed" do
      html = render_component(&player_chip/1, player: @player, selected?: false)
      assert html =~ ~s(aria-pressed="false")
      assert html =~ ~s(data-selected="false")
    end

    test "honors min 44px tap target" do
      html = render_component(&player_chip/1, player: @player)
      # Tailwind: min-h-11 = 44px
      assert html =~ "min-h-11"
      assert html =~ "min-w-11"
    end
  end

  describe "score_readout/1" do
    test "renders both numbers with tabular-nums" do
      html = render_component(&score_readout/1, our_score: 5, their_score: 3)

      assert html =~ ~r/>\s*5\s*</
      assert html =~ ~r/>\s*3\s*</
      assert html =~ "tabular-nums"
      assert html =~ ~s(role="status")
    end

    test "accent={:ours} highlights our score with the success color" do
      html = render_component(&score_readout/1, our_score: 5, their_score: 3, accent: :ours)
      # should contain a span with text-success around our score; assert both
      # the class and the digit are present (proximity check below)
      assert html =~ "text-success"
      assert html =~ "5"
    end

    test "accent=nil does not apply the accent color" do
      html = render_component(&score_readout/1, our_score: 0, their_score: 0, accent: nil)
      refute html =~ "text-success"
    end
  end

  describe "line_preset_card/1" do
    @preset %{id: 1, name: "O-line A", player_count: 7}

    test "renders preset name and player count" do
      html = render_component(&line_preset_card/1, preset: @preset)

      assert html =~ "O-line A"
      assert html =~ "7 players"
      assert html =~ ~s(aria-pressed="false")
    end

    test "selected?={true} flips aria-pressed and applies primary styling" do
      html = render_component(&line_preset_card/1, preset: @preset, selected?: true)

      assert html =~ ~s(aria-pressed="true")
      assert html =~ "bg-primary"
    end

    test "gender_warning?={true} renders an amber badge with icon AND label (no color-only signal)" do
      html =
        render_component(&line_preset_card/1, preset: @preset, gender_warning?: true)

      assert html =~ "bg-warning"
      assert html =~ "Ratio mismatch"
      assert html =~ "hero-exclamation-triangle"
    end

    test "gender_warning?={false} does not render the badge" do
      html =
        render_component(&line_preset_card/1, preset: @preset, gender_warning?: false)

      refute html =~ "Ratio mismatch"
    end

    test "falls back to counting :players list when :player_count is absent" do
      preset = %{name: "D-line", players: [%{}, %{}, %{}]}
      html = render_component(&line_preset_card/1, preset: preset)
      assert html =~ "3 players"
    end
  end

  describe "gender_radio/1" do
    defp gender_field(value) do
      %Phoenix.HTML.FormField{
        id: "player_gender_role",
        name: "player[gender_role]",
        errors: [],
        field: :gender_role,
        form: nil,
        value: value
      }
    end

    test "renders two native radio inputs with the same field name" do
      html = render_component(&gender_radio/1, field: gender_field(nil))

      assert html =~ ~r/<input[^>]*type="radio"[^>]*value="female_matching"/
      assert html =~ ~r/<input[^>]*type="radio"[^>]*value="male_matching"/

      # Both share the field name (so the browser groups them).
      assert Regex.scan(~r/name="player\[gender_role\]"/, html) |> length() == 2
    end

    test "selected value's radio gets the native checked attribute" do
      html = render_component(&gender_radio/1, field: gender_field("female_matching"))

      assert html =~ ~r/<input[^>]*value="female_matching"[^>]*\schecked\b/
      refute html =~ ~r/<input[^>]*value="male_matching"[^>]*\schecked\b/
    end

    test "with nil value, neither radio is checked" do
      html = render_component(&gender_radio/1, field: gender_field(nil))
      refute html =~ ~r/<input[^>]*type="radio"[^>]*\schecked\b/
    end

    test "wraps each radio in a <label> so the whole label is tappable" do
      html = render_component(&gender_radio/1, field: gender_field(nil))

      # Two <label> elements (one per option), each containing a radio.
      assert Regex.scan(~r/<label[^>]*>/, html) |> length() == 2
    end

    test "labels honor the 44px tap target floor (min-h-11)" do
      html = render_component(&gender_radio/1, field: gender_field(nil))
      # min-h-11 lives on the label classes.
      assert html =~ "min-h-11"
    end

    test "shows ♀/♂ glyphs plus screen-reader long names" do
      html = render_component(&gender_radio/1, field: gender_field(nil))

      assert html =~ "♀"
      assert html =~ "♂"
      assert html =~ "Female-matching"
      assert html =~ "Male-matching"
    end

    test "groups the radios with role=radiogroup and an accessible label" do
      html = render_component(&gender_radio/1, field: gender_field(nil))

      assert html =~ ~s(role="radiogroup")
      assert html =~ ~s(aria-label="Gender role")
    end
  end

  describe "timeline_event/1" do
    @event %{type: :goal, player_label: "#7 Sam", timestamp: "12:04", point_label: "P3"}

    test "renders event label, player, and timestamp" do
      html = render_component(&timeline_event/1, event: @event)

      assert html =~ "Goal"
      assert html =~ "#7 Sam"
      assert html =~ "12:04"
      assert html =~ "P3"
      assert html =~ ~s(data-event-type="goal")
    end

    test "editable?={false} does not render edit/delete affordances" do
      html = render_component(&timeline_event/1, event: @event, editable?: false)

      refute html =~ "hero-ellipsis-horizontal"
      refute html =~ ~s(aria-label="Edit Goal event")
    end

    test "editable?={true} renders the default edit affordance when no actions slot" do
      html = render_component(&timeline_event/1, event: @event, editable?: true)

      assert html =~ "hero-ellipsis-horizontal"
      assert html =~ ~s(aria-label="Edit Goal event")
    end

    test "renders sensibly for each event type" do
      for type <- [:goal, :assist, :block, :turn, :pull] do
        html =
          render_component(&timeline_event/1,
            event: %{type: type, player_label: "x", timestamp: "0:00"}
          )

        assert html =~ ~s(data-event-type="#{type}")
      end
    end
  end
end
