--- Staging area.

--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
-- [ MIT license: http://www.opensource.org/licenses/mit-license.php ]
--

-- Standard library imports --
local log = math.log
local max = math.max
local min = math.min

-- Conditional modules --
local with_bm, with_smat4, with_stex

-- Modules --
local matrix_mn = require("matrix_mn")
local qr = require("qr")

-- Solar2D modules --
local widget = require("widget")

--
--
--

local N = 16

--
--
--

-- set false to do Bytemap-based test
local UsingShader = true --false

--
--
--

local with_shader

if UsingShader then
  -- decide shader version, according to how positions are stored
  local IsTextureMode = true
  
  if IsTextureMode then
    with_stex = require("using_stex")

    with_stex.Init(N)
  else
    with_smat4 = require("using_smat4")
  end

  with_shader = with_stex or with_smat4
else
  with_bm = require("using_bytemap")
end

--
--
--

local ImageW, ImageH = 256, 384

--
--
--

local function AddImage (group, name, x, y)
  local is_filename, bm = type(name) == "string"

  if with_bm then
    bm = with_bm.Load(name, is_filename)
  elseif is_filename then
    bm = { filename = name, baseDir = system.ResourceDirectory } -- just do normal image
  else
    bm = name -- "name" is previous data
  end

  local image
  
  if with_stex and bm == name then -- see above
    image = display.newRect(group, 0, 0, ImageW, ImageH)
  else
    image = display.newImageRect(group, bm.filename, bm.baseDir, ImageW, ImageH)
  end

  image.x, image.y = x, y

  local outline = display.newRect(group, image.x, image.y, image.width, image.height)

  outline.strokeWidth = 2

  outline:setFillColor(0, 0)
  outline:setStrokeColor(1, 0, 0)

  return image, bm
end

--
--
--

local function Touch (event)
  local phase, node = event.phase, event.target

  if phase == "began" then
    display:getCurrentStage():setFocus(node)

    local gparent = node.parent.parent

    node.bounds = gparent[1].contentBounds
    node.xoff, node.yoff = event.x - node.x, event.y - node.y
  elseif phase == "moved" and node.xoff then
    node.x = max(min(event.x - node.xoff, node.bounds.xMax), node.bounds.xMin)
    node.y = max(min(event.y - node.yoff, node.bounds.yMax), node.bounds.yMin)
    
    local parent = node.parent

    parent[2].x, parent[2].y = node.x, node.y
  elseif phase == "ended" or phase == "cancelled" then
    display.getCurrentStage():setFocus(nil)

    node.xoff = nil
  end

  return true
end

--
--
--

local group1 = display.newGroup()
local group2 = display.newGroup()

local image1, bm1 = AddImage(group1, "Image1.jpg", display.contentCenterX * .5, display.contentCenterY * .5)
local image2, bm2 = AddImage(group2, "Image1.jpg", display.contentCenterX * 1.5, display.contentCenterY * .5)

local R = {
  0, 0,
  .5, 0,
  1, 0,
  0, .5,
  1, .5,
  0, 1,
  .5, 1,
  1, 1
}

for _ = 1, N do
local x = (_ - 1) % 4 + 1
local y = math.floor((_ - 1) / 4) + 1

  R[#R + 1] = x / 5--random()
  R[#R + 1] = y / 2.5--random()
end

for j = 1, 2 do
  local image = j == 1 and image1 or image2
  local parent, bounds = image.parent, image.contentBounds

  for i = 1, N do
    local g, b = (N - i) / N, i / N
    local x = R[i * 2 - 1]
    local y = R[i * 2]

    if j == 2 then
--[[
      x = max(0, min(x + (2 * random() - 1) * .05, 1))
      y = max(0, min(y + (2 * random() - 1) * .05, 1))
]]
    end

    local ngroup = display.newGroup()
    local node = display.newCircle(ngroup, bounds.xMin + x * image.width, bounds.yMin + y * image.height, 13)
    
    display.newText(ngroup, i, node.x, node.y, native.systemFont, 15)

    node:addEventListener("touch", Touch)
    node:setFillColor(1, g, b)
    parent:insert(ngroup)
  end
end

--
--
--

local SetT

--
--
--

local Interpolate = widget.newSlider{
  x = 120, width = 200,
  y = 1.5 * display.contentCenterY,
  value = 0,
  
  listener = function(event)
    if event.phase == "moved" then
      SetT(event.value / 100)
    end 
  end
}

Interpolate.isVisible = false

--
--
--

local group3 = display.newGroup()
local image3, bm3 = AddImage(group3, bm1, display.contentCenterX, display.contentCenterY * 1.5)

group3.isVisible = false

--
--
--

local function RadialKernel (dx, dy)
  local r2 = dx * dx + dy * dy

  return .5 * r2 * log(r2 + 1e-100)
end

--
--
--

local function BuildMatrix (X, Y)
	local M = matrix_mn.New(N + 3, N + 3)

  for row = 1, N do
    local xr, yr = X[row], Y[row]

    for col = 1, N do
      if row ~= col then
        M:Set(row, col, RadialKernel(xr - X[col], yr - Y[col]))
      else
        M:Set(row, col, 0)
      end
    end

    M:Set(row, N + 1, 1)
    M:Set(row, N + 2, X[row])
    M:Set(row, N + 3, Y[row])
  end

  for i = 1, 3 do
    for col = 1, N do
      if i == 1 then
        M:Set(N + i, col, 1)
      elseif i == 2 then
        M:Set(N + i, col, X[col])
      else
        M:Set(N + i, col, Y[col])
      end
    end

    M:Set(N + i, N + 1, 0)
    M:Set(N + i, N + 2, 0)
    M:Set(N + i, N + 3, 0)
  end

  return M
end

--
--
--

local function GetXY (group)
  local bounds = group[1].contentBounds
  local x, y = bounds.xMin, bounds.yMin
  local w, h = bounds.xMax - x, bounds.yMax - y
  local X, Y, j = matrix_mn.Zero(N + 3, 1), matrix_mn.Zero(N + 3, 1), 1

  for i = 3, group.numChildren do -- skip image + outline
    local node = group[i][1]
    local nx, ny = node.x - x, node.y - y

    if not with_stex then
      nx, ny = nx / w, ny / h
    end

    X[j], Y[j], j = nx, ny, j + 1
  end

  return X, Y
end

--
--
--

local function Bake ()
  local x1, y1 = GetXY(group1)
  local x2, y2 = GetXY(group2)
  local dx, dy = matrix_mn.Zero(N + 3, 1), matrix_mn.Zero(N + 3, 1)

  matrix_mn.Sub(x1, x2, dx)
  matrix_mn.Sub(y1, y2, dy)

  local M = BuildMatrix(x2, y2)
  local DupM = matrix_mn.Columns(M, 1, N + 3) -- Solve_Householder modifies its matrix
--[[
local M2 = BuildMatrix(x1, y1)
local M3 = matrix_mn.Columns(M2, 1, N + 3)
]]
  local alpha = matrix_mn.New(1, 1)
  local beta = matrix_mn.New(1, 1)
--[[
local alpha2 = matrix_mn.New(1, 1)
local beta2 = matrix_mn.New(1, 1)
]]
  qr.Solve_Householder(M, alpha, dx, 4, nil)
  qr.Solve_Householder(DupM, beta, dy, 4, nil)
--[[
qr.Solve_Householder(M2, alpha2, x2, 4, nil)
qr.Solve_Householder(M3, beta2, y2, 4, nil)
]]
  return x2, y2, alpha, beta
end

--
--
--

local X, Y, Alpha, Beta

--
--
--

local bgroup = display.newGroup()
local bake = display.newRoundedRect(bgroup, display.contentCenterX, 100, 100, 100, 12)

bake:addEventListener("touch", function(event)
  local phase, button = event.phase, event.target

  if phase == "began" then
    display:getCurrentStage():setFocus(button)
  elseif phase == "ended" or phase == "cancelled" then
    display:getCurrentStage():setFocus(nil)

    bgroup.isVisible = false
    group3.isVisible = true
    Interpolate.isVisible = true

    X, Y, Alpha, Beta = Bake()

    if with_shader then
      with_shader.SetShaderParams(image3, Alpha, Beta, X, Y, N)
    end

    SetT(0)
  end
end)

bake:setFillColor(.7, .3, .2)

display.newText(bgroup, "Bake", bake.x, bake.y, native.systemFontBold, 15)

--
--
--

function SetT (t)
  if with_bm then
    with_bm.SetT(bm3, bm1, Alpha, Beta, X, Y, N, RadialKernel, t)
  else
    image3:setFillColor(t) -- encode time in red channel
  end
end

--
--
--

if with_shader then
  local AlphaBeta, GetContributions = "vec2(u_UserData0[%i][%i], u_UserData1[%i][%i])", ""

  for col = 0, 3 do
    GetContributions = GetContributions .. with_shader.GetColumn(col)

    for row = 0, 3 do
      local ab, anchor = AlphaBeta:format(col, row, col, row), with_shader.GetAnchor(col, row)

      GetContributions = GetContributions .. "pos += GetContribution(uv, " .. ab .. ", " .. anchor .. ");\n"
    end
  end

  --
  --
  --

  local effect = {
    category = with_shader.Category(), name = "tps",

    uniformData = {
      {
        name = "alpha",
        type = "mat4",
        index = 0
      }, {
        name = "beta",
        type = "mat4",
        index = 1
      }, 
      with_shader.RemainingUniformData()
    },

    fragment = [[
      uniform P_DEFAULT mat4 u_UserData0; // alpha
      uniform P_DEFAULT mat4 u_UserData1; // beta
      uniform P_DEFAULT ]] .. with_shader.DeclareRemainingUniformsAndGetContributions() .. [[

      P_COLOR vec4 FragmentKernel (P_UV vec2 uv)
      {
        P_DEFAULT vec2 pos = vec2(0.);
]] .. with_shader.PrepareForContributions() .. GetContributions .. [[

        P_COLOR float t = CoronaColorScale(vec4(1.)).r;

        pos *= t;

        P_DEFAULT vec3 scaled = vec3(1., uv) * t;

]] .. with_shader.AccumulateAffineAndFinish().. [[

        pos += uv;

        P_UV vec2 diff = abs(pos - .5); // how far is the updated position from the center...

        return texture2D(CoronaSampler0, pos) * step(max(diff.x, diff.y), .5); // ...enough to put it outside the image?
      }
  ]]

  }

  graphics.defineEffect(effect)

  -- uncomment to see the final shader code:
  -- print(effect.fragment)
end