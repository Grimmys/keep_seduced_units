local MAX_RETRY_ATTEMPTS = 5

local seducer_force_cqi = 0
local is_seducer_human = false
local seduced_units = {}
local seduced_units_health_ratio_post_battle = {}
local active_battle_with_seduction = false -- neccessary variable for skipping UnitCreated events happening right after settlement capture but not related to seduction
local read_ui_values_attempt_count = 0

function keep_seduced_units()
    core:add_listener(
        "KeepSeducedUnits_UnitSeduced",
        "FactionBribesUnit",
        function (context)
          attacker = cm:model():pending_battle():attacker()
          if not attacker then
            return false
          end
          defender = cm:model():pending_battle():defender()
          if not defender then
            return false
          end
          return attacker:faction():is_human() or defender:faction():is_human()
        end,
        function(context)
          unit_entry =
          table.insert(seduced_units, {key = context:ancillary():unit_key(), exp = context:ancillary():experience_level()})
          -- TODO: handle case where both factions are seducing
          is_seducer_human = context:faction():is_human()
          seducer_force_cqi = get_force_cqi_in_battle_from_faction_name(context:faction():name())
          active_battle_with_seduction = true
          -- log("New unit seduced: " .. context:ancillary():unit_key() .. " - " .. context:ancillary():faction():name())
          -- log("Seducer Force CQI: " .. tostring(seducer_force_cqi))
        end,
        true
    )

    core:add_listener(
      "KeepSeducedUnits_BattleEnd",
      "PanelOpenedCampaign",
      function (context)
        return active_battle_with_seduction and context.string == "popup_battle_results"
      end,
      function(context)
        core:get_tm():callback(check_post_battle_seduced_units, 1)
      end,
      true
    )

    core:add_listener(
      "KeepSeducedUnits_BackToCampaignAfterBattle",
      "ScriptEventBattleSequenceCompleted",
      function(context)
        return active_battle_with_seduction
      end,
      function (context)
        reset_seduce_state_variables()
      end,
      true
    )

    core:add_listener(
      "KeepSeducedUnits_SeducedUnitAddedToForce",
      "UnitCreated",
      function (context)
        return active_battle_with_seduction
      end,
      function (context)
        local unit_added_to_force = context:unit()
        local seduced_unit_index = table.find_index_with_key(seduced_units, unit_added_to_force:unit_key(), "key")
        if seduced_unit_index == -1 then
          log("ERROR: Unit addded to force cannot be found in list of seduced units.")
          return
        end

        cm:set_unit_hp_to_unary_of_maximum(unit_added_to_force, seduced_units_health_ratio_post_battle[seduced_unit_index])
        -- TODO: also take into consideration xp earned during this battle (take from UI?)
        cm:add_experience_to_unit(unit_added_to_force, seduced_units[seduced_unit_index]["exp"])
        table.remove(seduced_units, seduced_unit_index)
        table.remove(seduced_units_health_ratio_post_battle, seduced_unit_index)
      end,
      true
    )
end

cm:add_saving_game_callback(
  function(context)
      cm:save_named_value("ksu_seducer_force_cqi", seducer_force_cqi, context)
      cm:save_named_value("ksu_is_seducer_human", is_seducer_human, context)
      cm:save_named_value("ksu_seduced_units", seduced_units, context)
      cm:save_named_value("ksu_seduced_units_health_ratio_post_battle", seduced_units_health_ratio_post_battle, context)
      cm:save_named_value("ksu_active_battle_with_seduction", active_battle_with_seduction, context)
  end
)

cm:add_loading_game_callback(
  function(context)
      seducer_force_cqi = cm:load_named_value("ksu_seducer_force_cqi", seducer_force_cqi, context)
      is_seducer_human = cm:load_named_value("ksu_is_seducer_human", is_seducer_human, context)
      seduced_units = cm:load_named_value("ksu_seduced_units", seduced_units, context)
      seduced_units_health_ratio_post_battle = cm:load_named_value("ksu_seduced_units_health_ratio_post_battle", seduced_units_health_ratio_post_battle, context)
      active_battle_with_seduction = cm:load_named_value("ksu_active_battle_with_seduction", active_battle_with_seduction, context)
  end
)

function get_force_cqi_in_battle_from_faction_name(faction_name)
  local pending_battle = cm:model():pending_battle()
  local attacker = pending_battle:attacker()
  local defender = pending_battle:defender()

  if not attacker:is_null_interface() and attacker:faction():name() == faction_name then
    return attacker:military_force():command_queue_index()
  end

  if not defender:is_null_interface() and defender:faction():name() == faction_name then
    return defender:military_force():command_queue_index()
  end

  log("ERROR: Cannot get force CQI in battle for faction " .. faction_name)
  return 0
end

function check_post_battle_seduced_units()
  local was_able_to_read_statuses = compute_post_battle_unit_statuses()
  if not was_able_to_read_statuses then
    if read_ui_values_attempt_count < MAX_RETRY_ATTEMPTS then
      read_ui_values_attempt_count = read_ui_values_attempt_count + 1
      core:get_tm():callback(check_post_battle_seduced_units, 1)
    else
      log("ERROR: Cannot read remaining health of units from post battle screen")
    end
    return
  end

  local pending_battle = cm:model():pending_battle()

  local attacker_force_cqi = nil
  if not pending_battle:attacker():is_null_interface() then
    attacker_force_cqi = pending_battle:attacker():military_force():command_queue_index()
  end
  local defender_force_cqi = nil
  if not pending_battle:defender():is_null_interface() then
    defender_force_cqi = pending_battle:defender():military_force():command_queue_index()
  end

  local seducer_character = nil
  local victim_character = nil
  if pending_battle:attacker_won() and attacker_force_cqi == seducer_force_cqi then
    seducer_character = pending_battle:attacker()
    victim_character = pending_battle:defender()
  elseif pending_battle:defender_won() and defender_force_cqi == seducer_force_cqi then
    seducer_character = pending_battle:defender()
    victim_character = pending_battle:attacker()
  end

  if seducer_character then
    clone_seduced_units = table.clone(seduced_units)
    clone_seduced_units_health_ratio = table.clone(seduced_units_health_ratio_post_battle)
    for index, seduced_unit in ipairs(clone_seduced_units) do
      if clone_seduced_units_health_ratio[index] > 0 then
        cm:grant_unit_to_character(cm:char_lookup_str(seducer_character), seduced_unit["key"])
        if victim_character and not victim_character:is_null_interface() then
          cm:remove_unit_from_character(cm:char_lookup_str(victim_character), seduced_unit["key"])
        end
      end
    end
  end

  core:get_tm():real_callback(reset_seduce_state_variables, 10)
end

function compute_post_battle_unit_statuses()
  local uic_units = nil
  if is_seducer_human then
    uic_units = find_uicomponent(core:get_ui_root(), "popup_battle_results", "allies_combatants_panel", "army",
    "units_and_banners_parent", "units_window", "listview", "list_clip", "list_box", "commander_header_0", "units")
  else
    uic_units = find_uicomponent(core:get_ui_root(), "popup_battle_results", "enemy_combatants_panel", "army",
    "units_and_banners_parent", "units_window", "listview", "list_clip", "list_box", "commander_header_0", "units")
  end
  if not uic_units then
    return false
  end
  -- Looping in reverse order because seduced units are at the end
  for i = uic_units:ChildCount() - 1, 0, -1 do
    local uic_unit = UIComponent(uic_units:Find(i))
    local unit_key = uic_unit:Id()
    local uic_health_bar = find_uicomponent(uic_unit, "card_image_holder", "health_frame", "health_bar")
    local unit_health_ratio = (find_uicomponent(uic_health_bar, "health_fill"):Width() - 1) / uic_health_bar:Width()
    --log("Unit key: " .. unit_key .. " - Current health ratio: " .. unit_health_ratio)
    table.insert(seduced_units_health_ratio_post_battle, 1, unit_health_ratio)
    if #seduced_units_health_ratio_post_battle == #seduced_units then
      break
    end
  end
  return true
end

function reset_seduce_state_variables()
  seducer_force_cqi = 0
  is_seducer_human = false
  seduced_units = {}
  seduced_units_health_ratio_post_battle = {}
  active_battle_with_seduction = false
  read_ui_values_attempt_count = 0
  --log("Seducing state variables cleared")
end
