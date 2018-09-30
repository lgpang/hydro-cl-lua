--[[
This is a Solver that uses a fluxBuffer
and that uses calcDerivFromFlux to update it
--]]
local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local file = require 'ext.file'
local template = require 'template'
local GridSolver = require 'solver.gridsolver'

local common = require 'common'()
local xNames = common.xNames
local symNames = common.symNames
local from3x3to6 = common.from3x3to6 
local from6to3x3 = common.from6to3x3 
local sym = common.sym


local FiniteVolumeSolver = class(GridSolver)

function FiniteVolumeSolver:createBuffers()
	FiniteVolumeSolver.super.createBuffers(self)
	self:clalloc('fluxBuf', self.numCells * self.dim * ffi.sizeof(self.eqn.cons_t))
end

function FiniteVolumeSolver:getSolverCode()
	return table{
		FiniteVolumeSolver.super.getSolverCode(self),
		template(file['solver/calcDerivFV.cl'], {solver=self}),
	}:concat'\n'
end

function FiniteVolumeSolver:refreshSolverProgram()
	FiniteVolumeSolver.super.refreshSolverProgram(self)

	-- 'calcFlux' is usually provided, but the args vary, so I'll leave it to the subclass
	
	self.calcDerivFromFluxKernelObj = self.solverProgramObj:kernel{name='calcDerivFromFlux', domain=self.domainWithoutBorder}
	self.calcDerivFromFluxKernelObj.obj:setArg(0, self.solverBuf)
	self.calcDerivFromFluxKernelObj.obj:setArg(2, self.fluxBuf)
end

function FiniteVolumeSolver:addDisplayVars()
	FiniteVolumeSolver.super.addDisplayVars(self)

	-- TODO add kernels for each side
	for j,xj in ipairs(xNames) do
		self:addDisplayVarGroup{
			name = 'flux '..xj, 
			bufferField = 'fluxBuf',
			type = self.eqn.cons_t,
			codePrefix = [[
	int indexInt = ]]..(j-1)..[[ + dim * index;
	const global ]]..self.eqn.cons_t..[[* flux = buf + indexInt;
]],
			vars = range(0,self.eqn.numIntStates-1):map(function(i)
				return {[''..i] = '*value = flux->ptr['..i..'];'}
			end),
		}
	end
end

return FiniteVolumeSolver
