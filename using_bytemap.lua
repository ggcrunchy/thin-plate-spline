--- Bytemap version of test.

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
local floor = math.floor

-- Plugins --
local Bytemap = require("plugin.Bytemap")

-- Exports
local M = {}

--
--
--

function M.Load (file_or_other, is_file)
  if is_file then
    return Bytemap.loadTexture{ filename = file_or_other }
  else -- "name" is another Bytemap
    return Bytemap.newTexture{ width = file_or_other.width, height = file_or_other.height }
  end
end

--
--
--
--
--
--

local Zero = string.char(0, 0, 0, 0)

--
--
--

function M.SetT (into, from, alpha, beta, xvalues, yvalues, n, kernel, t)
  local h, w = into.height, into.width
  local hm1, wm1 = h - 1, w - 1
  local bytes = from:GetBytes()
  local opts = {}

  local a1, a2, a3 = alpha[n + 1], alpha[n + 2], alpha[n + 3]
  local b1, b2, b3 = beta[n + 1], beta[n + 2], beta[n + 3]

  for row = 1, h do
    local v = (row - 1) / hm1

    opts.y1, opts.y2 = row, row

    for col = 1, w do
      local u, xoff, yoff = (col - 1) / wm1, 0, 0

      for i = 1, n do
        local dist = kernel(xvalues[i] - u, yvalues[i] - v)

        xoff, yoff = xoff + dist * alpha[i], yoff + dist * beta[i]
      end

      xoff = u + (xoff + a1 + a2 * u + a3 * v) * t
      yoff = v + (yoff + b1 + b2 * u + b3 * v) * t

      opts.x1, opts.x2 = col, col

      if xoff >= 0 and xoff <= 1 and yoff >= 0 and yoff <= 1 then
        local x = floor(xoff * wm1)
        local y = floor(yoff * hm1)
        local index = (y * w + x) * 4 + 1

        into:SetBytes(bytes:sub(index, index + 3), opts)
      else
        into:SetBytes(Zero, opts)
      end
    end
  end

  into:invalidate()
end

--
--
--

return M