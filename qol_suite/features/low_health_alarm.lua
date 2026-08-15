-- QoL Suite: optionally silence the battle low-health alarm.
return function(mod)
  local OPTION = "lowHealthAlarm"

  mod.hooks:wrap("battle.low_health_alarm", function(next, ctx)
    if type(ctx) == "table" and mod.options:get(OPTION) ~= true then
      ctx.on = false
    end
    return next(ctx)
  end)
end
