local class = require 'ext.class'
local table = require 'ext.table'
local template = require 'template'
local Z4cFiniteDifferenceEquation = require 'eqn.z4c-fd'
local Solver = require 'solver.solver'

local xNames = table{'x', 'y', 'z'}

local Z4cFiniteDifferenceSolver = class(Solver)
Z4cFiniteDifferenceSolver.name = 'Z4c_FiniteDifference'

-- TODO make a gui variable for numGhost
-- hmm, can I do that without rebuilding solverProgram every time it changes?
-- probably not, courtesy of boundary
-- in fact, how would boundary work with numGhost!=2?
-- esp mirror boundary conditions?
Z4cFiniteDifferenceSolver.numGhost = 2


function Z4cFiniteDifferenceSolver:init(...)
	Z4cFiniteDifferenceSolver.super.init(self, ...)
	self.name = nil	-- don't append the eqn name to this
end

function Z4cFiniteDifferenceSolver:createEqn(eqn)
	self.eqn = Z4cFiniteDifferenceEquation(self)
end

function Z4cFiniteDifferenceSolver:refreshSolverProgram()
	Z4cFiniteDifferenceSolver.super.refreshSolverProgram(self)
	
	self.calcDerivKernelObj = self.solverProgramObj:kernel'calcDeriv'
	self.calcDerivKernelObj.obj:setArg(1, self.UBuf)
end

function Z4cFiniteDifferenceSolver:getCalcDTCode() end
function Z4cFiniteDifferenceSolver:refreshCalcDTKernel() end
function Z4cFiniteDifferenceSolver:calcDT() return self.fixedDT end

function Z4cFiniteDifferenceSolver:calcDeriv(derivBuf, dt)
	self.calcDerivKernelObj(derivBuf)
end

function Z4cFiniteDifferenceSolver:getDisplayInfosForType()
	local t = Z4cFiniteDifferenceSolver.super.getDisplayInfosForType(self)

	-- hmm, only works with U ... so it only applies to U ...
	table.insert(t.real3, {
		name = ' norm weighted',
		code = '*value = real3_weightedLen(*valuevec, U->gammaBar_ll) / calc_exp_neg4phi(U);',
	})

	-- hmm, how to do the weighting stuff with gammaBar_ll ... 
	-- also, how to determine which metric to raise by ... gamma vs gammaBar
	table.insert(t.sym3, {
		name = ' tr weighted',
		code = '*value = sym3_dot(U->gammaBar_uu, *valuesym3) / calc_det_gamma(U);',
	})

	return t
end

return Z4cFiniteDifferenceSolver

