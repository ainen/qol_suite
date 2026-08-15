-- Derive the caught-marker tile from the player's imported battle assets.
-- The repository contains only this recipe; no ROM-derived pixels are shipped.
return function(ctx)
  local source = "battle/balls.png"
  if not ctx.exists(source) then return end

  local image = ctx.readImage(source)
  local width, height = image:getDimensions()
  if width < 8 or height < 8 then return end

  local marker = ctx.blank(8, 8)
  ctx.blit(marker, image, 0, 0, 0, 0, 8, 8)
  ctx.writeImage(marker, "caught_marker.png")
end
