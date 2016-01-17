
-- love .

local bit = require("bit")
package.path = package.path .. ";slaxml/?.lua"
local slax = require("slaxdom")
local http = require("socket.http")

blurshader = [[
extern vec2 shift;

const int radius = 11;
const float filter[radius] = float[radius](
  0.0402,0.0623,0.0877,0.1120,0.1297,0.1362,0.1297,0.1120,0.0877,0.0623,0.0402
);

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  vec2 ntc = tc - float(int(radius / 2)) * shift;
  vec4 ncolor = vec4(0.0, 0.0, 0.0, 0.0);
  for (int i = 0; i < radius; ++i) {
    ncolor += filter[i] * Texel(tex, ntc).rgba;
    ntc += shift;
  }
  return ncolor;
}
]]
blendshader = [[
float overlay(float a, float b) {
	return a < 0.5 ?
    (2.0 * a * b) :
    (1.0 - 2.0 * (1.0 - a) * (1.0 - b));
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc) {
  vec4 texel = Texel(tex, tc);
  return vec4(
    overlay(color.r, texel.r),
    overlay(color.g, texel.g),
    overlay(color.b, texel.b),
    texel.a
  );
}
]]


local BLURSTRENGTH = 0.01
local BLURDURATION = 0.1
local SHUFFLE = false
local LATENCY = 3072

local taiko = false
local taikosum = 0
local taikohits = 0

local songnr = 0
local imagenr = 0
local songs = {}
local images = {}
local nochange = false
local hidegui = true

local beat = ""
local beatpos = 0

local color = {0, 0, 0}

local image = nil
local loop = nil
local buildup = nil

local tinyfont = love.graphics.newFont("SourceCodePro-Regular.ttf", 12)
local smallfont = love.graphics.newFont("SourceCodePro-Regular.ttf", 30)
local largefont = love.graphics.newFont("SourceCodePro-Regular.ttf", 100)

local blackout = false
local shortblackout = false

local vblur = 0
local hblur = 0

local colors = {
  13453898, 16443317, 10453360, 2302755, 12344664, 14521461, 10145515, 2845892,
  15715768, 7229792, 1964308, 7453816, 16570741, 11068576, 9802124, 1879160,
  16719310, 11725917, 6125259, 16645236, 16561365, 16760200, 9935530, 16745027,
  16628916, 1722486, 16753475, 12236908, 16741688, 15116503, 4278860, 16739914,
  1878473, 12964070, 9323909, 7619272, 14060121, 14886251, 15605837, 2084555,
  7885225, 16751530, 16525383, 10478271, 10840399, 9075037, 4574882, 16482045,
  15526590, 16604755, 16426860, 16550316, 14407634, 1540205, 7855591, 16752777,
  9392285, 15592941, 16728996, 16542853, 13477086, 16574595, 12968836
}

local function wrap(min, n, max)
  if n < min then return max end
  if n > max then return min end
  return n
end


local function changeImage(nr)
  if nochange then return end
  imagenr = nr or math.ceil(math.random() * #images)
  image = images[imagenr]
end

local function changeColor()
  local c = colors[math.ceil(math.random() * #colors)]
  color[1] = bit.band(bit.rshift(c, 16), 0xFF)
  color[2] = bit.band(bit.rshift(c, 8), 0xFF)
  color[3] = bit.band(c, 0xFF)
end

local function loadRespack(file, name, draw)
  if not love.filesystem.mount(file, name) then
    return
  end

  local base = name .. "/"
  -- sigh
  for i = 0, 5 do
    if love.filesystem.isFile(base .. "info.xml") then
      break
    else
      base = base .. name .. "/"
    end
  end
  if not love.filesystem.isFile(base .. "info.xml") then
    return
  end

  local songdom
  if love.filesystem.isFile(base .. "songs.xml") then
    songdom = slax:dom(love.filesystem.read(base .. "songs.xml"), {simple=true})
  elseif love.filesystem.isFile(base .. "Songs.xml") then
    songdom = slax:dom(love.filesystem.read(base .. "Songs.xml"), {simple=true})
  end
  if songdom then
    for si, sv in ipairs(songdom.root.kids) do
      if sv.name == "song" then
        local song = {}
        for i, v in ipairs(sv.attr) do if v.name == "name" then song.name = v.value end end

        for ki, kv in ipairs(sv.kids) do
          if kv.type ~= "text" and #(kv.kids) > 0 and kv.kids[1].type == "text" then
            song[kv.name] = kv.kids[1].value
          end
        end

        song.path = base .. "Songs/" .. song.name .. ".mp3"
        if song.buildup then
          song.buildupPath = base .. "Songs/" .. song.buildup .. ".mp3"
        end

        table.insert(songs, song)
      end
    end
  end

  local imagedom
  if love.filesystem.isFile(base .. "images.xml") then
    imagedom = slax:dom(love.filesystem.read(base .. "images.xml"), {simple=true})
  elseif love.filesystem.isFile(base .. "Images.xml") then
    imagedom = slax:dom(love.filesystem.read(base .. "Images.xml"), {simple=true})
  end
  if imagedom then
    for ii, iv in ipairs(imagedom.root.kids) do
      if iv.name == "image" then
        local image = {}
        for i, v in ipairs(iv.attr) do if v.name == "name" then image.name = v.value end end

        for ki, kv in ipairs(iv.kids) do
          if kv.type ~= "text" and #(kv.kids) > 0 and kv.kids[1].type == "text" then
            image[kv.name] = kv.kids[1].value
          end
        end

        -- siiigh
        local paths = {
          base .. "Images/" .. image.name .. ".png",
          base .. "Images/" .. image.name .. ".jpg",
          base .. "Animations/" .. image.name .. "/" .. image.name .. "_00.png",
          base .. "Animations/" .. image.name .. "/" .. image.name .. "_00.jpg",
          base .. "Animations/" .. image.name .. "/" .. image.name .. "_01.png",
          base .. "Animations/" .. image.name .. "/" .. image.name .. "_01.jpg",
          base .. image.name .. "/" .. image.name .. "_00.png",
          base .. image.name .. "/" .. image.name .. "_00.jpg",
          base .. image.name .. "/" .. image.name .. "_01.png",
          base .. image.name .. "/" .. image.name .. "_01.jpg"
        }

        for i, v in ipairs(paths) do
          if love.filesystem.isFile(v) then
            image.path = v
          end
        end
        if image.path then
          image.data = love.graphics.newImage(image.path)
          table.insert(images, image)

          if draw then
            if math.random() >= 0.5 then
              vblur = BLURSTRENGTH
              hblur = 0
            else
              vblur = 0
              hblur = BLURSTRENGTH
            end
            changeColor()
            changeImage(#images)
            love.graphics.clear()
            love.graphics.origin()
            love.draw()
            love.graphics.setColor(0, 0, 0, 100)
            love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), 80)
            love.graphics.setColor(255, 255, 255)
            love.graphics.setFont(smallfont)
            love.graphics.printf("LOADING " .. name:upper(), 0, 15, 800, "center")
            love.graphics.present()
          end
        end
      end
    end
  end
end

local function loadSong(id)
  if buildup then buildup.source:stop() end
  if loop then loop.source:stop() end
  taiko = false
  taikosum = 0
  taikohits = 0

  if type(id) == "string" then
    for i, v in ipairs(songs) do
      if v.name == id then
        id = i
        break
      end
    end
  end

  loop = {}

  songnr = id
  local song = songs[id]
  loop.data = love.sound.newSoundData(song.path)
  loop.source = love.audio.newSource(loop.data)
  loop.rhythm = song.rhythm
  loop.source:setLooping(true)

  if song.buildup then
    buildup = {}
    buildup.data = love.sound.newSoundData(song.buildupPath)
    buildup.source = love.audio.newSource(buildup.data)
    buildup.rhythm = song.buildupRhythm or "...."

    current = buildup
  else
    buildup = nil
    current = loop
  end
  current.source:play()
end

local function samplesToBeats(samples)
  return samples / (current.data:getSampleCount() / #current.rhythm)
end

local function beatsToSamples(beats)
  return (beats / #current.rhythm) * current.data:getSampleCount()
end

local function nearestBeat(samples, char)
  local beats = samplesToBeats(samples)

  local backw = 0
  for i = beatpos, 0, -1 do
    if current.rhythm:sub(i, i) == char then
      backw = i
      break
    end
  end

  local forw = 0
  for i = beatpos, #current.rhythm do
    if current.rhythm:sub(i, i) == char then
      forw = i
      break
    end
  end

  if math.abs(beats - backw) < math.abs(beats - forw) then
    return backw - 1
  else
    return forw - 1
  end
end

function love.load()
  math.randomseed(os.clock())
  math.random() math.random() math.random()

  love.graphics.setDefaultFilter("nearest", "nearest", 8)
  blurshader = love.graphics.newShader(blurshader)
  blendshader = love.graphics.newShader(blendshader)

  fxcanvas = love.graphics.newCanvas()
  blurshader:send("shift", {0, 0})

  acccanvas = love.graphics.newCanvas(200, 20)
  acccanvas:clear(0, 0, 0)

  items = love.filesystem.getDirectoryItems("respacks")
  for i, v in ipairs(items) do
    if v:find("zip", 3 - #v + 1, true) then
      loadRespack("respacks/" .. v, v:sub(0, #v - 4), true)
    end
  end
  hidegui = false

  loadSong(math.ceil(math.random() * #songs))
  changeImage()
end

function love.draw()
  local width = love.graphics.getWidth()
  local height = love.graphics.getHeight()
  local vcenter = width / 2
  local hcenter = height / 2
  love.graphics.setColor(255, 255, 255)
  love.graphics.setBlendMode("alpha")

  if blackout == true or shortblackout == true then
    love.graphics.setBackgroundColor(0, 0, 0)
    shortblackout = false
    return
  end

  local scale = height / image.data:getHeight()

  local xoff = 0
  if image.align == "center" then
    xoff =  vcenter - ((image.data:getWidth()*scale) / 2)
  elseif image.align == "left" then
    xoff = 0
  elseif image.align == "right" then
    xoff = width - (image.data:getWidth() * scale)
  end

  fxcanvas:clear()
  love.graphics.setCanvas(fxcanvas)
  love.graphics.setShader(blurshader)
  blurshader:send("shift", {vblur, 0})
  love.graphics.draw(image.data, xoff, height - (image.data:getHeight() * scale), 0, scale, scale)
  blurshader:send("shift", {0, hblur})
  love.graphics.draw(fxcanvas, 0, 0)
  love.graphics.setShader()
  love.graphics.setCanvas()
  love.graphics.setColor(color)
  love.graphics.setShader(blendshader)
  love.graphics.draw(fxcanvas, 0, 0)
  love.graphics.setShader()
  love.graphics.setColor(255, 255, 255)
  love.graphics.setBackgroundColor(color)

  if not hidegui then
    local beattext = beat
    local beattextw = largefont:getWidth(beattext)

    local rhythmtext = current.rhythm:sub(beatpos+1)
    local rhythmtextw = smallfont:getWidth(rhythmtext)
    while rhythmtextw < love.graphics.getWidth() - rhythmtextw do
      rhythmtext = rhythmtext .. loop.rhythm
      rhythmtextw = smallfont:getWidth(rhythmtext)
    end

    love.graphics.setColor(0, 0, 0, 100)
    love.graphics.rectangle("fill", 0, 0, width, 80)
    love.graphics.rectangle("fill", 0, height - 20, width, 20)

    love.graphics.setColor(255, 255, 255)
    love.graphics.setFont(smallfont)
    love.graphics.print(rhythmtext, vcenter + (beattextw / 2), 15)
    love.graphics.print(rhythmtext:reverse(), (vcenter - (beattextw / 2)) - rhythmtextw, 15)
    if beattext ~= "." then
      love.graphics.setFont(largefont)
      love.graphics.print(beattext, vcenter - (beattextw / 2), -40)
    end
    love.graphics.setFont(tinyfont)
    love.graphics.printf(string.format("(%i/%i) %s", songnr, #songs, songs[songnr].title
      ), 10, height - 17, (width / 2) - 10, "left")
    love.graphics.printf(string.format("%s (%i/%i)", image.fullname, imagenr, #images
      ), (width / 2) + 10, height - 17, (width / 2) - 20, "right")

    if taiko then
      love.graphics.setColor(0, 0, 0, 100)
      love.graphics.rectangle("fill", vcenter - 100, height - 140, 200, 140)

      acccanvas:renderTo(function()
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, 0, 200, 20)
        love.graphics.setColor(255, 255, 255)
        love.graphics.line(100, 0, 100, 20)
      end)
      love.graphics.draw(acccanvas, vcenter - 100, height - 20)

      local taikoacc = math.floor(taikosum / taikohits)
      love.graphics.setColor(255, 255, 255)
      love.graphics.setFont(largefont)
      love.graphics.printf(tostring(taikoacc) .. "%", 0, height - 140, width, "center")
    end
  end
end

function love.update(dt)
  local newbeatpos = math.ceil(samplesToBeats(current.source:tell("samples") - LATENCY))

  vblur = vblur - (dt * (BLURSTRENGTH / BLURDURATION))
  if vblur < 0 then vblur = 0 end
  hblur = hblur - (dt * (BLURSTRENGTH / BLURDURATION))
  if hblur < 0 then hblur = 0 end

  if newbeatpos ~= beatpos then
    beatpos = newbeatpos
    beat = current.rhythm:sub(beatpos, beatpos)

    if beat ~= "." then
      blackout = false
    end

    if beat == "x" then
      vblur = BLURSTRENGTH
      changeImage()
      changeColor()
    elseif beat == "o" then
      hblur = BLURSTRENGTH
      changeImage()
      changeColor()
    elseif beat == "-" then
      changeImage()
      changeColor()
    elseif beat == "+" then
      blackout = true
      shortblackout = false
    elseif beat == "|" then
      shortblackout = true
      blackout = false
    elseif beat == ":" then
      changeImage()
    elseif beat == "*" then
      changeColor()
    elseif beat == "X" then
      vblur = BLURSTRENGTH
    elseif beat == "O" then
      hblur = BLURSTRENGTH
    elseif beat == "~" then
      changeColor() --fadeColor()
    elseif beat == "=" then
      changeImage() --fadeImage()
    end

    if SHUFFLE and current == loop and beatpos == #current.rhythm then
      current.source:stop()
      loadSong(math.ceil(math.random() * #songs))
    end
  end

  if buildup and buildup.source:isStopped() then
    current = loop
    current.source:play()
  end
end

function love.resize(w, h)
  fxcanvas = love.graphics.newCanvas(w, h)
end

function love.keypressed(b)
  if b == "up" then
    songnr = wrap(1, songnr + 1, #songs)
    loadSong(songnr)
  elseif b == "down" then
    songnr = wrap(1, songnr - 1, #songs)
    loadSong(songnr)
  elseif b == "lshift" or b == "rshift" then
    loadSong(math.ceil(math.random() * #songs))
  elseif b == "left" then
    imagenr = wrap(1, imagenr - 1, #images)
    image = images[imagenr]
  elseif b == "right" then
    imagenr = wrap(1, imagenr + 1, #images)
    image = images[imagenr]
  elseif b == "f" then
    nochange = not nochange
  elseif b == "h" then
    hidegui = not hidegui
  elseif b == "f11" then
    love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
  elseif b == "escape" then
    if love.window.getFullscreen() then
      love.window.setFullscreen(false, "desktop")
    else
      love.event.push("quit")
    end

  elseif b == "y" then taiko = true
    local now = current.source:tell("samples") - LATENCY
    local nearest = nearestBeat(now, "o")
    local diff = beatsToSamples(nearest) - now
    local x = (diff / current.data:getSampleRate()) * 100
    taikosum = taikosum + math.max(100 - math.abs(x), 0)
    taikohits = taikohits + 1
    acccanvas:renderTo(function()
      love.graphics.setBlendMode("additive")
      love.graphics.setColor(255, 0, 0)
      love.graphics.line(x * 2 + 100, 0, x * 2 + 100, 20)
      love.graphics.setBlendMode("alpha")
    end)

  elseif b == "x" then taiko = true
    local now = current.source:tell("samples") - LATENCY
    local nearest = nearestBeat(now, "x")
    local diff = beatsToSamples(nearest) - now
    local x = (diff / current.data:getSampleRate()) * 100
    taikosum = taikosum + math.max(100 - math.abs(x), 0)
    taikohits = taikohits + 1
    acccanvas:renderTo(function()
      love.graphics.setBlendMode("additive")
      love.graphics.setColor(0, 0, 255)
      love.graphics.line(x * 2 + 100, 0, x * 2 + 100, 20)
      love.graphics.setBlendMode("alpha")
    end)
  end
end
