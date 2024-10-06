--- Shader version of test, using a mat4 for positions.

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

-- Exports --
local M = {}

--
--
--

local function EncodeTenBitsPair (x, y)
	assert(x >= 0 and x <= 1024, "Invalid x")
	assert(y >= 0 and y <= 1024, "Invalid y")

	x, y = floor(x + .5), floor(y + .5)

	local signed = y == 1024

	if signed then
		y = 1023
	end

	local xhi = floor(x / 64)
	local xlo = x - xhi * 64
	local xy = (1 + (xlo * 1024 + y) * 2^-16) * 2^xhi

	return signed and -xy or xy
end

--- Encodes two numbers &isin; [0, 1] into a **highp**-range float for retrieval in GLSL.
-- @number x Number #1...
-- @number y ...and #2.
-- @treturn number Encoded pair.
local function EncodeFloats (x, y)
	return EncodeTenBitsPair(x * 1024, y * 1024)
end

--
--
--

local CapPo2 = 4 -- largest observed absolute value (could be wrong!!) of affine terms was 2.5 or so, so assume next power-of-2 of 4...

--
--
--

local MulCap = 512 / CapPo2 -- ...splitting 1024 into negative and positive sides, we can scale such a value by this much

-- the values will be renormalized in TenBitsPair_OutH()
-- since we packed them as `result = (v * MulCap) + 512`, the (normalized) way to re-obtain
-- `v` in-shader is: `(result - 512) / (MulCap * 1024)`, or `(result / 1024 - .5) / MulCap`.

--
--
--

function M.SetShaderParams (image, alpha, beta, xvalues, yvalues, n)
  image.fill.effect = "filter.custom.tps"

  local effect, anchor, affine = image.fill.effect, {}, {}

  effect.alpha, effect.beta = alpha, beta

  for i = 1, n do
    anchor[i] = EncodeFloats(floor(xvalues[i] * 1024) / 1024, floor(yvalues[i] * 1024) / 1024)
  end

  effect.anchor = anchor

  for i = 1, 3 do
    -- see notes above on `MulCap`
    local a, b = alpha[n + i], beta[n + i]

    a, b = (floor(a * MulCap) + 512) / 1024, (floor(b * MulCap) + 512) / 1024

    affine[i] = EncodeFloats(a, b)
  end
    
  effect.affine = affine
end

--
--
--

function M.Category ()
  return "filter"
end

--
--
--

function M.RemainingUniformData ()
  return {
    name = "anchor",
    type = "mat4",
    index = 2
  }, {
    name = "affine",
    type = "vec3",
    index = 3
  }
end

--
--
--

local Order

if system.getInfo("platform") == "win32" then
    function Order (precision, qualifier)
        return precision .. [[ ]] .. qualifier .. "\n"
    end
else
    function Order (precision, qualifier)
        return qualifier .. [[ ]] .. precision .. "\n"
    end
end

--
--
--

local OUT = [[

    #define OUT_PARAM(precision) ]] .. Order("precision", "out")
 
--
--
--

local Decode = [[

		P_DEFAULT _VAR_TYPE_ axy = abs(xy);
]] ..

-- Select a 2^16-wide floating point range, comprising elements (1 + s / 65536) * 2^bin,
-- where significand s is an integer in [0, 65535]. The range's ulp will be 2^bin / 2^16,
-- i.e. 2^(bin - 16), and can be used to extract s.
[[
		P_DEFAULT _VAR_TYPE_ bin = floor(log2(axy));
		P_DEFAULT _VAR_TYPE_ num = exp2(16. - bin) * axy; // this is (axy - 2^16) / 2^(bin - 16) plus 65536...
]] ..

-- The lower 10 bits of the offset make up the y-value. The upper 6 bits, along with
-- the bin index, are used to compute the x-value. The bin index can exceed 15, so x
-- can assume the value 1024 without incident. It seems at first that y cannot, since
-- 10 bits fall just short. If the original input was signed, however, this is taken
-- to mean "y = 1024". Rather than conditionally setting it directly, though, 1023 is
-- found in the standard way and then incremented.
[[
		P_DEFAULT _VAR_TYPE_ rest = floor(num / 1024.); // ...so this is 64 more than expected...
		P_DEFAULT _VAR_TYPE_ y = num - rest * 1024.; // ...here those extras cancel out (65536 - 64 * 1024)...
		P_DEFAULT _VAR_TYPE_ y_bias = step(0., -xy);
]]
--[=[
local Error = [[

		#error "High fragment precision needed to decode number"
]]
]=]
--
--
--

local TenBitsPairsCode = [[

	void TenBitsPair_OutH (P_DEFAULT _VAR_TYPE_ xy, OUT_PARAM(P_DEFAULT) _VAR_TYPE_ xo, OUT_PARAM(P_DEFAULT) _VAR_TYPE_ yo)
	{
		]] .. Decode .. [[

		xo = (bin - 1.) * 64. + rest; // ...as with TenBitsPair
		yo = y + y_bias;
    
    xo /= 1024.;
    yo /= 1024.;
	}
]]

--
--
--

local TenBitsPairVec3 = TenBitsPairsCode:gsub("_VAR_TYPE_", "vec3")
local TenBitsPairVec4 = TenBitsPairsCode:gsub("_VAR_TYPE_", "vec4")

function M.DeclareRemainingUniformsAndGetContributions ()
  return [[mat4 u_UserData2; // packed x, y
    uniform P_DEFAULT vec3 u_UserData3; // packed affine terms
]] .. OUT .. TenBitsPairVec3 .. TenBitsPairVec4 .. [[

    P_UV vec2 GetContribution (P_UV vec2 uv, P_DEFAULT vec2 alpha_beta, P_DEFAULT vec2 anchor)
    {
      P_UV float r2 = dot(uv - anchor, uv - anchor);

      return .5 * alpha_beta * r2 * log(r2 + 2e-12);
    }

]]
end

--
--
--

function M.PrepareForContributions ()
  return [[
    P_DEFAULT vec4 anchorx, anchory; // columns

]]
end

--
--
--

function M.GetAnchor (_, row)
  return ("vec2(anchorx[%i], anchory[%i])"):format(row, row)
end

--
--
--

function M.GetColumn (col)
  return ("TenBitsPair_OutH(u_UserData2[%i], anchorx, anchory);\n"):format(col)
end

--
--
--

function M.AccumulateAffineAndFinish ()
  return ([[
      P_DEFAULT vec3 xterms, yterms;

      TenBitsPair_OutH(u_UserData3, xterms, yterms);

      pos.x += dot(scaled, xterms - .5) / %f;
      pos.y += dot(scaled, yterms - .5) / %f;

]]):format(MulCap / 1024, MulCap / 1024)
end

--
--
--

return M