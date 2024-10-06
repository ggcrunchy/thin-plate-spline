--- General-purpose m-by-n matrices.

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

-- Modules --
local assert = assert
local rawget = rawget
local setmetatable = setmetatable
local sqrt = math.sqrt
local type = type

-- Cached module references --
local _Columns_From_
local _New_
local _NewOrResize_
local _Resize_

-- Exports --
local M = {}

-- --
local MatrixMethods = { __metatable = true }

MatrixMethods.__index = MatrixMethods

--
local function Index (matrix, row, col)
	assert(row >= 1 and row <= matrix.m_rows, "Bad row")
	assert(col >= 1 and col <= matrix.m_cols, "Bad column")
	
	return matrix.m_cols * (row - 1) + col
end

--
local function ZeroPrep (nrows, ncols, out)
	out = _NewOrResize_(nrows, ncols, out)

	for i = 1, nrows * ncols do
		out[i] = 0
	end

	return out
end

--- DOCME
-- @tparam MatrixMN A
-- @tparam MatrixMN B
-- @tparam[opt] MatrixMN out (can be A or B)
-- @treturn MatrixMN S
function M.Add (A, B, out)
	local nrows, ncols = A.m_rows, A.m_cols

	assert(nrows == B.m_rows, "Mismatched rows")
	assert(ncols == B.m_cols, "Mismatched columns")
-- TODO: zero-pad?  (if so, need to account for A or B being out)
	local sum = _NewOrResize_(nrows, ncols, out)

	for index = 1, nrows * ncols do
		sum[index] = A[index] + B[index]
	end

	return sum
end

--- DOCME
-- @tparam MatrixMN A
-- @tparam Vector Y
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN B
function M.BackSubstitute (A, Y, out)
	local ncols = A.m_cols

	assert(ncols == Y.m_rows, "Mismatched matrix and vector")
	assert(Y.m_cols == 1, "Non-column vector")

	out = _NewOrResize_(ncols, 1, out)

	local ri, dr, w = ncols * A.m_rows, ncols + 1, 0

	for row = ncols, 1, -1 do
		local sum = 0

		for dc = 1, w do
			sum = sum + A[ri + dc] * out[row + dc]
		end

		out[row], ri, w = (Y[row] - sum) / A[ri], ri - dr, w + 1
	end

	return out
end

--- DOCME
-- @tparam MatrixMN A
-- @uint k1
-- @uint k2
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN C
function M.Columns (A, k1, k2, out)
	return _Columns_From_(A, k1, k2, 1, out)
end

--- DOCME
-- @tparam MatrixMN A
-- @uint k1
-- @uint k2
-- @uint from
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN C
function M.Columns_From (A, k1, k2, from, out)
	local nrows, ncols = A.m_rows, A.m_cols
	local w, skip, inc = k2 - k1 + 1

	if k2 < k1 then
		skip, inc = ncols + 1, -1
	else
		skip, inc = ncols - w, 1
	end

	out = _NewOrResize_(nrows - from + 1, w, out)

	local index, ai = 1

	for row = from, nrows do
		ai = ai or Index(A, row, k1)

		for _ = 1, w do
			out[index], index, ai = A[ai], index + 1, ai + inc
		end

		ai = ai + skip
	end

	return out
end

--- DOCME
-- @tparam MatrixMN A
-- @uint row
-- @uint col
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN C
function M.Corner (A, row, col, out)
	local w, h = A.m_cols - col + 1, A.m_rows - row + 1

	out = _NewOrResize_(h, w, out)

	local index, ai, skip = 1, Index(A, row, col), col - 1

	for _ = 1, h do
		for _ = 1, w do
			out[index], index, ai = A[ai], index + 1, ai + 1
		end

		ai = ai + skip
	end

	return out
end

--- DOCME
-- @tparam MatrixMN A
-- @treturn number N
function M.FrobeniusNorm (A)
	local sum = 0

	for i = 1, A.m_rows * A.m_cols do
		sum = sum + A[i]^2
	end

	return sqrt(sum)
end

--- DOCME
-- @tparam MatrixMN A
-- @treturn number N
function M.FrobeniusNormSquared (A)
	local sum = 0

	for i = 1, A.m_rows * A.m_cols do
		sum = sum + A[i]^2
	end

	return sum
end

--- DOCME
-- @uint n
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN m
function M.Identity (n, out)
	out = ZeroPrep(n, n, out)

	for i = 1, n * n, n + 1 do
		out[i] = 1
	end

	return out
end

--
local function RowTimesColumn (A, B, ri, bi, n, len)
	local sum = 0

	for i = 1, len do
		sum, bi = sum + A[ri + i] * B[bi], bi + n
	end

	return sum
end

--- DOCME
-- @tparam MatrixMN A
-- @tparam MatrixMN B
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN P
function M.Mul (A, B, out)
	local m, n, len, ri, index = A.m_rows, B.m_cols, A.m_cols, 0, 1

	assert(len == B.m_rows, "Mismatched matrices")

	out = _NewOrResize_(m, n, out)

	for _ = 1, m do
		for col = 1, n do
			out[index], index = RowTimesColumn(A, B, ri, col, n, len), index + 1
		end

		ri = ri + len
	end

	return out
end

--- DOCME
-- @uint nrows
-- @uint ncols
-- @treturn MatrixMN m
function M.New (nrows, ncols)
	return setmetatable({ m_cols = ncols, m_rows = nrows }, MatrixMethods)
end

--- DOCME
-- @uint nrows
-- @uint ncols
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN m
function M.NewOrResize (nrows, ncols, out)
	if out then
		_Resize_(out, nrows, ncols)

		return out
	else
		return _New_(nrows, ncols)
	end
end

--- DOCME
-- @tparam MatrixMN A
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN m
function M.NewOrResize_Matrix (A, out)
	return _NewOrResize_(A.m_rows, A.m_cols, out)
end

--
local function GetM (v)
	return rawget(v, "m_rows") or #v
end

--
local function GetN (v)
	return rawget(v, "m_cols") or #v
end

--- DOCME
-- @tparam Vector v (TODO: Accept 1-element matrices... need check?)
-- @tparam Vector w
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN S
function M.OuterProduct (v, w, out)
	local n1, n2, index = GetM(v), GetN(w), 1

	out = _NewOrResize_(n1, n2, out)

	for i = 1, n1 do
		for j = 1, n2 do
			out[index], index = v[i] * w[j], index + 1
		end
	end

	return out
end

--- DOCME
-- @tparam MatrixMN A
-- @uint row
-- @uint col
-- @tparam MatrixMN B
function M.PutBlock (A, row, col, B)
	local row_to, ncols, index = B.m_rows + row - 1, B.m_cols, 1

	assert(row_to <= A.m_rows, "Bad row for block")
	assert(ncols + col - 1 <= A.m_cols, "Bad column for block")

	for r = row, row_to do
		local mi = Index(A, r, col)

		for at = mi, mi + ncols - 1 do
			A[at], index = B[index], index + 1
		end
	end
end

--- DOCME
-- @tparam MatrixMN A
-- @uint nrows
-- @uint ncols
function M.Resize (A, nrows, ncols)
	A.m_rows, A.m_cols = nrows, ncols
end

--- DOCME
-- @tparam MatrixMN A
-- @number k
-- @tparam[opt] MatrixMN out (can be A)
-- @treturn MatrixMN S
function M.Scale (A, k, out)
	local nrows, ncols = A.m_rows, A.m_cols

	out = _NewOrResize_(nrows, ncols, out)

	for i = 1, ncols * nrows do
		out[i] = A[i] * k
	end

	return out
end

--- DOCME
-- @tparam MatrixMN A
-- @tparam MatrixMN B
-- @tparam[opt] MatrixMN out (can be A or B)
-- @treturn MatrixMN D
function M.Sub (A, B, out)
	local nrows, ncols = A.m_rows, A.m_cols

	assert(nrows == B.m_rows, "Mismatched rows")
	assert(ncols == B.m_cols, "Mismatched columns")
-- TODO: Zero-pad? (if so, need to account for A or B being out)
	out = _NewOrResize_(nrows, ncols, out)

	for index = 1, nrows * ncols do
		out[index] = A[index] - B[index]
	end

	return out
end

--- DOCME A<sup>T</sup>.
-- @tparam MatrixMN A
-- @tparam[opt] MatrixMN out
-- @treturn MatrixMN A
function M.Transpose (A, out)
	local nrows, ncols, index = A.m_rows, A.m_cols, 1

	--
	if A ~= out then
		out = _NewOrResize_(ncols, nrows, out)

		for col = 1, ncols do
			local ci = col

			for _ = 1, nrows do
				out[index], index, ci = A[ci], index + 1, ci + ncols
			end
		end

	-- Transpose self, vector case: just swap dimensions.
	elseif ncols == 1 or nrows == 1 then
		out.m_rows, out.m_cols = ncols, nrows

	-- Transpose self, general.
	else
		assert(false, "NYI!")
		--[[
		for each length>1 cycle C of the permutation
			pick a starting address s in C
			let D = data at s
			let x = predecessor of s in the cycle
			while x ≠ s
				move data from x to successor of x
				let x = predecessor of x
			move data from D to successor of s

			A B C D	 	A E I	1 2 3 4		1 5 9	11 12 13 14		11 21 31
			E F G H ->	B F J	5 6 7 8 ->	2 6 A	21 22 23 24 ->	12 22 32
			I J K L		C G K	9 A B C		3 7 B	31 32 33 34		13 23 33
						D H L				4 8 C					14 24 34
		]]
	end

	return out
end

--- DOCME
-- @uint nrows
-- @uint ncols
-- @treturn MatrixMN m
function M.Zero (nrows, ncols)
	return ZeroPrep(nrows, ncols)
end

-- Add methods.
do
	--- Metamethod.
	-- @uint row
	-- @uint col
	-- @treturn number S
	function MatrixMethods:__call (row, col)
		return self[Index(self, row, col)]
	end

	-- IsVector(), IsScalar()?
	-- Multiply(), TransposeMultiply()?
	-- Rank()?
	-- column, row length, length squared
	-- column, row dot products
	-- Plus(), Minus(), Times()...

	--
	local function IterOpts (opts)
		local from, to, out

		if type(opts) == "table" then
			from, to, out = opts.from, opts.to, opts.out
		end

		return from or 1, to or 1, out
	end

	--- DOCME
	-- @uint col
	-- @uint[opt=1] from
	-- @treturn number L
	function MatrixMethods:ColumnLength (col, from)
		local sum, index, ncols = 0, Index(self, from or 1, col), self.m_cols

		for _ = from or 1, self.m_rows do
			sum, index = sum + self[index]^2, index + ncols
		end

		return sqrt(sum)
	end

	--- DOCME
	-- @uint col
	-- @tparam[opt=1] ?|table|uint opts
	-- @treturn MatrixMN C
	function MatrixMethods:GetColumn (col, opts)
		local from, to, out = IterOpts(opts)
		local m, n = self.m_rows, self.m_cols
		local index = Index(self, from, col)

		out = _NewOrResize_(m + to - from, 1, out)

		for _ = from, m do
			out[to], to, index = self[index], to + 1, index + n
		end

		return out
	end

	--- DOCME
	-- @treturn uint NCOLS
	function MatrixMethods:GetColumnCount ()
		return self.m_cols
	end

	--- DOCME
	-- @treturn uint R
	-- @treturn uint C
	function MatrixMethods:GetDims ()
		return self.m_rows, self.m_cols
	end

	--- DOCME
	-- @uint row
	-- @uint[opt=1] from
	-- @treturn table R
	function MatrixMethods:GetRow (row, from)
		local arr, index = {}, Index(self, row, from or 1)

		for _ = from or 1, self.m_cols do
			arr[#arr + 1], index = self[index], index + 1
		end

		return arr
	end

	--- DOCME
	-- @treturn uint NROWS
	function MatrixMethods:GetRowCount ()
		return self.m_rows
	end

	-- DOCME
	-- @uint row
	-- @uint[opt=1] from
	-- @treturn number L
	function MatrixMethods:RowLength (row, from)
		local sum, index = 0, Index(self, row, from or 1)

		for _ = from or 1, self.m_cols do
			sum, index = sum + self[index]^2, index + 1
		end

		return sqrt(sum)
	end

	-- ^^ TODO: Squared lengths?
	--- @function MatrixMethods:Resize
	-- @uint nrows
	-- @uint ncols
	MatrixMethods.Resize = M.Resize

	--- DOCME
	-- @uint row
	-- @uint col
	-- @number value
	function MatrixMethods:Set (row, col, value)
		self[Index(self, row, col)] = value
	end

	--- DOCME
	-- @uint row
	-- @uint col
	-- @number delta
	function MatrixMethods:Update (row, col, delta)
		local index = Index(self, row, col)

		self[index] = self[index] + delta
	end
end

-- Cache module members.
_Columns_From_ = M.Columns_From
_New_ = M.New
_NewOrResize_ = M.NewOrResize
_Resize_ = M.Resize

-- Export the module.
return M