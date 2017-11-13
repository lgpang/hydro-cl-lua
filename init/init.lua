local class = require 'ext.class'
local table = require 'ext.table'
local template = require 'template'
local time = table.unpack(require 'time')

local InitCond = class()

function InitCond:refreshInitStateProgram(solver)
	local initStateCode = table{
		solver.codePrefix,
		
		-- this calls InitCond:getInitStateCode below
		solver.eqn:getInitStateCode(),
	
	}:concat'\n'
	time('compiling init state program', function()
		solver.initStateProgramObj = solver.Program{
			code = initStateCode,
		}
		solver.initStateProgramObj:compile()
	end)
	solver.initStateKernelObj = solver.initStateProgramObj:kernel('initState', solver.UBuf)
end

-- TODO maybe consolidate this and initState()
-- TODO maybe make the template env vars modular too
function InitCond:getInitStateCode(solver)
	local eqn = solver.eqn
	local header = self.header and self:header(eqn.solver) or nil
	local code = self.initState and self:initState(eqn.solver) or nil
	assert(eqn.initStateCode, "expected Eqn.initStateCode")
	return (header or '')..'\n'..template(eqn.initStateCode, {
		eqn = eqn,
		code = code or '//no code from InitCond:initState() was provided',
		solver = eqn.solver,
	})
end

-- called when the solver resets
function InitCond:resetState(solver)
	solver.initStateKernelObj()
end

return InitCond
