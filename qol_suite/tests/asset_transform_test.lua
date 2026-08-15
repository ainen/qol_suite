-- The caught marker must be derived from the player's imported assets; the
-- mod repository and release archive intentionally contain no copied tile.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local root = assert(source:match("^(.*)[/\\]tests[/\\][^/\\]+$"),
  "resolve QoL Suite test root")
local transform = assert(loadfile(root .. "/transforms.lua"))()

local reads, writes, blits, blanks = 0, 0, 0, 0
transform({
  exists = function() return false end,
  readImage = function() reads = reads + 1 end,
  blank = function() blanks = blanks + 1 end,
  blit = function() blits = blits + 1 end,
  writeImage = function() writes = writes + 1 end,
})
T.eq(reads + writes + blits + blanks, 0,
  "missing imported battle art leaves no derived marker")

local writtenPath, writtenImage
local sourceImage = {
  getDimensions = function() return 16, 8 end,
}
local markerImage = { kind = "blank-marker" }
transform({
  exists = function(path) return path == "battle/balls.png" end,
  readImage = function(path)
    T.eq(path, "battle/balls.png", "transform reads the native ball sheet")
    return sourceImage
  end,
  blank = function(width, height)
    T.eq(width, 8, "derived marker width matches the native tile")
    T.eq(height, 8, "derived marker height matches the native tile")
    return markerImage
  end,
  blit = function(destination, image, dx, dy, sx, sy, width, height)
    T.eq(destination, markerImage, "transform writes into its blank marker")
    T.eq(image, sourceImage, "transform copies from the imported sheet")
    T.eq(dx + dy + sx + sy, 0, "transform copies from the sheet origin")
    T.eq(width, 8, "transform copies one tile wide")
    T.eq(height, 8, "transform copies one tile high")
  end,
  writeImage = function(image, path)
    writtenImage, writtenPath = image, path
  end,
})
T.eq(writtenImage, markerImage, "transform writes the derived marker")
T.eq(writtenPath, "caught_marker.png",
  "transform uses the path consumed by CAUGHT MARKER")

T.finish("asset_transform")
