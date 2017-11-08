--[[
common functions for all num rel equations
--]]

local class = require 'ext.class'
local table = require 'ext.table'
local template = require 'template'
local Equation = require 'eqn.eqn'

local NumRelEqn = class(Equation)

local xNames = table{'x', 'y', 'z'}

NumRelEqn.initStates = require 'init.numrel'

function NumRelEqn:createInitState()
	NumRelEqn.super.createInitState(self)
	self:addGuiVars{
		{
			type = 'combo',
			name = 'f',
			options = {
				'2/alpha',	-- 1+log slicing
				'1 + 1/alpha^2', 	-- Alcubierre 10.2.24: "shock avoiding condition" for Toy 1+1 spacetimes 
				'1', 		-- Alcubierre 4.2.50 - harmonic slicing
				'0', '.49', '.5', '1.5', '1.69',
			}
		},
		{name='linearConstraintCoeff', value=10},
	}
end

-- add an option for fixed Minkowsky boundary spacetime
function NumRelEqn:createBoundaryOptions()
	self.solver.boundaryOptions:insert{
		fixed = function(args)
			local lines = table()
			local gridSizeSide = 'gridSize_'..xNames[args.side]
			for _,U in ipairs{
				'buf['..args.index'j'..']',
				'buf['..args.index(gridSizeSide..'-numGhost+j')..']',
			} do
				lines:insert(template([[
	setFlatSpace(&<?=U?>);
]], {eqn=eqn, U=U}))
			end
			return lines:concat'\n'
		end,
	}
end

-- add the gui vars with a gui_ prefix
-- also add the initState's getCodePrefix
-- maybe I should do this everywhere?
function NumRelEqn:getCodePrefix(solver)
	local lines = table()
	
	local guivars = NumRelEqn.super.getCodePrefix(self)
	guivars = guivars:gsub('define ', 'define gui_')
	lines:insert(guivars)

	if self.initState.getCodePrefix then
		lines:insert(self.initState:getCodePrefix(self.solver))
	end

	-- prim and cons are the same for numrel 
	lines:insert(template([[

inline <?=eqn.prim_t?> primFromCons(<?=eqn.cons_t?> U, real3 x) { return U; }

inline <?=eqn.cons_t?> consFromPrim(<?=eqn.prim_t?> W, real3 x) { return W; }

inline void apply_dU_dW(
	<?=eqn.cons_t?>* U, 
	const <?=eqn.prim_t?>* WA, 
	const <?=eqn.prim_t?>* W, 
	real3 x
) {
	*U = *W;
}

inline void apply_dW_dU(
	<?=eqn.prim_t?>* W,
	const <?=eqn.prim_t?>* WA,
	const <?=eqn.cons_t?>* U,
	real3 x
) {
	*W = *U;
}

]], {eqn=self}))

	return lines:concat'\n'
end

-- and now for fillRandom ...
local ffi = require 'ffi'
local function crand() return 2 * math.random() - 1 end
function NumRelEqn:fillRandom(epsilon)
	local solver = self.solver
	local ptr = ffi.new(self.cons_t..'[?]', solver.volume)
	ffi.fill(ptr, 0, ffi.sizeof(ptr))
	for i=0,solver.volume-1 do
		for j=0,self.numStates-1 do
			ptr[i].ptr[j] = epsilon * crand()
		end
	end
	solver.UBufObj:fromCPU(ptr)
	return ptr
end


return NumRelEqn
