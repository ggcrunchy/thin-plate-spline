--- An example of thin-plate splines for image transformation.

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

-- Plugins --
local core = require("plugin.eigencore")
local double = require("plugin.eigendouble")

-- Corona imports --
local getTimer = system.getTimer

local File = "Image.jpg"
local image = display.newImageRect(File, 512, 256)

--
image.x, image.y = display.contentCenterX, display.contentCenterY

local outline = display.newRect(image.x, image.y, image.width, image.height)

outline.strokeWidth = 4

outline:setFillColor(0, 0)
outline:setStrokeColor(1, 0, 0)

--
do
	local bounds, xoff, yoff = image.contentBounds

	local function Touch (event)
		local phase, image = event.phase, event.target

		if phase == "began" then
			display:getCurrentStage():setFocus(image)

			xoff, yoff = event.x - image.x, event.y - image.y
		elseif phase == "moved" and xoff then
			image.x = math.max(math.min(event.x - xoff, bounds.xMax), bounds.xMin)
			image.y = math.max(math.min(event.y - yoff, bounds.yMax), bounds.yMin)
		elseif phase == "ended" or phase == "cancelled" then
			display.getCurrentStage():setFocus(nil)

			xoff, yoff = nil
		end

		return true
	end

	local N = 15

	local group1 = display.newGroup()
	local group2 = display.newGroup()

	for i = 1, N do
		local g, b = (N - i) / N, i / N
		local x1 = math.random()
		local y1 = math.random()

		local pos1 = display.newRect(group1, bounds.xMin + x1 * image.width, bounds.yMin + y1 * image.height, 30, 30)

		pos1:addEventListener("touch", Touch)
		pos1:setFillColor(1, g, b)

		local x2 = math.min(math.max(x1 + (2 * math.random() - 1) * .1, 0), 1)
		local y2 = math.min(math.max(y1 + (2 * math.random() - 1) * .1, 0), 1)

		local pos2 = display.newCircle(group2, bounds.xMin + x2 * image.width, bounds.yMin + y2 * image.height, 15)

		pos2:addEventListener("touch", Touch)
		pos2:setFillColor(1, g, b)
	end

	local bake = display.newCircle(display.contentCenterX, display.contentHeight - 50, 25)

	bake:addEventListener("touch", function(event)
		local phase, button = event.phase, event.target

		if phase == "began" then
			display:getCurrentStage():setFocus(button)
		elseif phase == "ended" or phase == "cancelled" then
			display:getCurrentStage():setFocus(nil)

			local mat = double.Zero(N + 3)
			local X = double.Vector(N + 3)
			local Y = double.Vector(N + 3)

			for i = 1, N do
				local circle = group2[i]

				X:coeffAssign(i, circle.x - bounds.xMin)
				Y:coeffAssign(i, circle.y - bounds.yMin)
			end

			local Xp = double.Vector(N + 3)
			local Yp = double.Vector(N + 3)

			for i = 1, N do
				local rect = group1[i]

				Xp:coeffAssign(i, rect.x - bounds.xMin)
				Yp:coeffAssign(i, rect.y - bounds.yMin)
			end

			X,Xp=Xp,X
			Y,Yp=Yp,Y

			for row = 1, N do
				local xr, yr = X(row), Y(row)

				for col = 1, N do
					if row ~= col then
						local xc, yc = X(col), Y(col)
						local r2 = (xr - xc)^2 + (yr - yc)^2

						mat:coeffAssign(row, col, .5 * r2 * math.log(r2 + 1e-100))
					end
				end

				mat:coeffAssign(row, N + 1, 1)
				mat:coeffAssign(row, N + 2, X(row))
				mat:coeffAssign(row, N + 3, Y(row))
			end

			for i = 1, 3 do
				for col = 1, N do
					if i == 1 then
						mat:coeffAssign(N + i, col, 1)
					elseif i == 2 then
						mat:coeffAssign(N + i, col, X(col))
					else
						mat:coeffAssign(N + i, col, Y(col))
					end
				end

				Xp:coeffAssign(N + i, 0)
				Yp:coeffAssign(N + i, 0)
			end

			local qr = mat:householderQr()
			local Xb = qr:solve(Xp)
			local Yb = qr:solve(Yp)

			local Xn = X:topRows(N)
			local Yn = Y:topRows(N)

			local Xbn = .5 * Xb:topRows(N)
			local Ybn = .5 * Yb:topRows(N)

			local warp = require("plugin.memoryBitmap").newTexture{ width = image.width, height = image.height }

			--
			image.fill = { type = "image", filename = warp.filename, baseDir = warp.baseDir }

			--
			local K = 2 -- attempt to handle scalings that go off the image

			do
				local kernel = { category = "composite", group = "morph", name = "warp" }

				kernel.vertexData = {
					{ name = "t", index = 0, default = 0, min = 0, max = 1 }
				}

				kernel.fragment = ([[
					P_DEFAULT vec2 DecodeTwoFloatsRGBA (P_DEFAULT vec4 rgba)
					{
						return vec2(dot(rgba.xy, vec2(1., 1. / 255.)), dot(rgba.zw, vec2(1., 1. / 255.)));
					}

					P_COLOR vec4 FragmentKernel (P_UV vec2 uv)
					{
						P_COLOR vec4 rgba = texture2D(CoronaSampler1, uv);
						P_UV vec2 pos = 2. * DecodeTwoFloatsRGBA(rgba) - 1.;

						uv = mix(uv, %i. * pos, CoronaVertexUserData.x);
						
						P_UV vec2 inside = smoothstep(vec2(.5025 + CoronaVertexUserData.x * .0375), vec2(.5 + CoronaVertexUserData.x * .0175), abs(uv - .5));

						return CoronaColorScale(texture2D(CoronaSampler0, uv)) * (inside.x * inside.y);
					}
				]]):format(K)

				graphics.defineEffect(kernel)
			end

			--
			local x2, y2 = Xb(N + 2), Yb(N + 2)
			local x3, y3 = Xb(N + 3), Yb(N + 3)
			local sxr, syr = Xb(N + 1) - .5 * (x2 + x3), Yb(N + 1) - .5 * (y2 + y3)
			local iw, ih = K * image.width, K * image.height

			local function GetRowSum (row)
				return (Yn - (row - .5)):cwiseAbs2()
			end
			
			local function Do (row_contrib, col, sx, sy)
				local r2 = (Xn - (col - .5)):cwiseAbs2() + row_contrib
				local factor = r2:cwiseProduct((r2 + 1e-100):log())

				sx, sy = sx + factor:dot(Xbn), sy + factor:dot(Ybn)

				return .5 * sx / iw + .5, .5 * sy / ih + .5
			end

			local row, col, sxc, syc, row_contrib = 0, image.width + 1

			timer.performWithDelay(50, function(event)
				local w, h, wait_until = image.width, image.height, event.time + 40

				repeat
					--
					if col <= w then
						local sx, sy = core.WithCache(Do, row_contrib, col, sxc, syc)

						--
						local y = (sx * 255) % 1
						local x = sx - y / 255
						local w = (sy * 255) % 1
						local z = sy - w / 255

						warp:setPixel(col, row, x, y, z, w)

						sxc, syc, col = sxc + x2, syc + y2, col + 1

					--
					else
						row, col, sxr, syr = row + 1, 1, sxr + x3, syr + y3

						if row <= h then
							sxc, syc, row_contrib = sxr, syr, core.WithCache(GetRowSum, row)

						--
						else
							local widget = require("widget")

							widget.newSlider{
								top = 20,
								left = 20,
								width = 150,
								value = 0,
								listener = function(event)
									image.fill.effect.t = event.value / 100
								end
							}

							image.fill = {
								type = "composite",
								paint1 = { type = "image", filename = File },
								paint2 = { type = "image", filename = warp.filename, baseDir = warp.baseDir }
							}

							image.fill.effect = "composite.morph.warp"

							timer.cancel(event.source)

							break
						end
					end
				until getTimer() >= wait_until

				warp:invalidate()
			end, 0)
		end
	end)
end