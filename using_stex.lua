--- Shader version of test, using a data texture for positions.

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
local max = math.max
local min = math.min

-- Exports --
local M = {}

--
--
--

local AnchorsTex

--
--
--

graphics.defineEffect{
  category = "generator", name = "encode_anchors",

  vertexData = {
    { index = 0, name = "x" },
    { index = 1, name = "y" }
  },

  fragment = [[
    P_COLOR vec4 EncodeTwoFloatsRGBA (P_DEFAULT vec2 v)
    {
      P_DEFAULT vec4 enc = vec4(1., 255., 1., 255.) * v.xxyy;

      enc = fract(enc);

      return enc - enc.yyww * vec4(1. / 255., 0., 1. / 255., 0.);
    }

    P_COLOR vec4 FragmentKernel (P_UV vec2 _)
    {
      return EncodeTwoFloatsRGBA(CoronaVertexUserData.xy);
    }
  ]]
}

--
--
--

function M.Init (n)
  local old_magfilter = display.getDefault("magTextureFilter")
  local old_minfilter = display.getDefault("minTextureFilter")

  display.setDefault("magTextureFilter", "nearest")
  display.setDefault("minTextureFilter", "nearest")

  AnchorsTex = graphics.newTexture{ type = "canvas", width = n, height = 1, pixelWidth = n, pixelHeight = 1 }

  display.setDefault("magTextureFilter", old_magfilter)
  display.setDefault("minTextureFilter", old_minfilter)

  --
  --
  --

  for i = 1, n do
    local dummy = display.newRect(-AnchorsTex.width / 2 + i - .5, 0, 1, 1)

    dummy.fill.effect = "generator.custom.encode_anchors"

    AnchorsTex:draw(dummy)
  end

  AnchorsTex:setBackground(0, 0)
  AnchorsTex:invalidate()
end

--
--
--

function M.SetShaderParams (image, alpha, beta, xvalues, yvalues, n)
  image.fill = {
    type = "composite",
    paint1 = { type = "image", filename = "Image1.jpg" },
    paint2 = { type = "image", filename = AnchorsTex.filename, baseDir = AnchorsTex.baseDir }
  }

  image.fill.effect = "composite.custom.tps"

  local effect, scaled_alpha, scaled_beta = image.fill.effect, {}, {}
  local max_size = max(image.width, image.height)
  local ms2 = max_size * max_size
  local kw, kh = ms2 / image.width, ms2 / image.height

  for i = 1, n do
    scaled_alpha[i], scaled_beta[i] = alpha[i] * kw, beta[i] * kh
  end

  effect.alpha, effect.beta = scaled_alpha, scaled_beta

  effect.texSizesAlphaBeta = {
    image.width, image.height, AnchorsTex.width,
    alpha[n + 1] / image.width, alpha[n + 2], alpha[n + 3] * (image.height / image.width),
    beta[n + 1] / image.height, beta[n + 2] * (image.width / image.height), beta[n + 3]
  }

  local cache = AnchorsTex.cache

  for i = 1, n do
    local effect = cache[i].fill.effect

    effect.x, effect.y = min(xvalues[i] / image.width, .999975), min(yvalues[i] / image.height, .999975)
  end
  
  AnchorsTex:invalidate("cache")
end

--
--
--

function M.Category ()
  return "composite"
end

--
--
--

function M.RemainingUniformData ()
  return {
    name = "texSizesAlphaBeta",
    type = "mat3",
    index = 2
  }
end

--
--
--

function M.DeclareRemainingUniformsAndGetContributions ()
  return [[mat3 u_UserData2; // column 1: texture size; data texture width / column 2, 3: affine x, y
    
    P_DEFAULT vec2 DecodeTwoFloatsRGBA (P_UV float u)
    {
      P_DEFAULT vec4 rgba = texture2D(CoronaSampler1, vec2(u / u_UserData2[0].z, .5));
    
      return vec2(dot(rgba.xy, vec2(1., 1. / 255.)), dot(rgba.zw, vec2(1., 1. / 255.)));
    }

    P_UV vec2 GetContribution (P_UV vec2 uv, P_DEFAULT vec2 alpha_beta, P_DEFAULT vec2 anchor, P_DEFAULT vec3 tex_sizes)
    {
      P_UV vec2 diff = (uv - anchor) * tex_sizes.xy;
      P_UV float unscaled_r2 = dot(diff, diff);
      
      return alpha_beta * unscaled_r2 * (tex_sizes.z + .5 * log(unscaled_r2 + 2e-12));
    }
]]
end

--
--
--

function M.PrepareForContributions ()
  return [[P_DEFAULT float max_size = max(u_UserData2[0].x, u_UserData2[0].y);
      
    P_DEFAULT vec3 tex_sizes = vec3(u_UserData2[0].xy / max_size, log(max_size));

    // verify that texels land in expected spots:
    // return texture2D(CoronaSampler1, uv);

]]
end

--
--
--

function M.GetAnchor (col, row)
  return ("DecodeTwoFloatsRGBA(%.1f), tex_sizes"):format(col * 4 + row)
end

--
--
--

function M.GetColumn (_)
  return ""
end

--
--
--

function M.AccumulateAffineAndFinish ()
  return [[

    pos.x += dot(scaled, u_UserData2[1]);
    pos.y += dot(scaled, u_UserData2[2]);

]]
end

--
--
--

return M