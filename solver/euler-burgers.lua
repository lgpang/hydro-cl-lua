local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local file = require 'ext.file'
local range = require 'ext.range'
local template = require 'template'
local FiniteVolumeSolver = require 'solver.fvsolver'

local common = require 'common'()
local xNames = common.xNames
local symNames = common.symNames
local from3x3to6 = common.from3x3to6 
local from6to3x3 = common.from6to3x3 
local sym = common.sym


-- TODO make this work with ops, specifically Euler's SelfGrav
local EulerBurgers = class(FiniteVolumeSolver)
EulerBurgers.name = 'EulerBurgers'
EulerBurgers.eqnName = 'euler'

function EulerBurgers:init(...)
	EulerBurgers.super.init(self, ...)
	self.name = nil	-- don't append the eqn name to this
end

function EulerBurgers:createEqn()
	EulerBurgers.super.createEqn(self)
	self.eqn.getCalcDTCode = function() end	-- override calcDT 
end

function EulerBurgers:createBuffers()
	EulerBurgers.super.createBuffers(self)
	
	self:clalloc('intVelBuf', self.numCells * self.dim * ffi.sizeof(self.app.real))
	self:clalloc('PBuf', self.numCells * ffi.sizeof(self.app.real))
end

function EulerBurgers:getSolverCode()
	return table{
		EulerBurgers.super.getSolverCode(self),
		template(file['solver/euler-burgers.cl'], {solver=self, eqn=self.eqn}),
	}:concat'\n'
end

function EulerBurgers:refreshSolverProgram()
	EulerBurgers.super.refreshSolverProgram(self)

	-- no mention of ULR just yet ...

	self.calcIntVelKernelObj = self.solverProgramObj:kernel('calcIntVel', self.solverBuf, self.intVelBuf, self.getULRBuf)
	self.calcFluxKernelObj = self.solverProgramObj:kernel('calcFlux', self.solverBuf, self.fluxBuf, self.getULRBuf, self.intVelBuf)

	self.computePressureKernelObj = self.solverProgramObj:kernel('computePressure', self.solverBuf, self.PBuf, self.UBuf) 
	
	self.diffuseMomentumKernelObj = self.solverProgramObj:kernel{name='diffuseMomentum', domain=self.domainWithoutBorder}
	self.diffuseMomentumKernelObj.obj:setArg(0, self.solverBuf)
	self.diffuseMomentumKernelObj.obj:setArg(2, self.PBuf)
	
	self.diffuseWorkKernelObj = self.solverProgramObj:kernel'diffuseWork'
	self.diffuseWorkKernelObj.obj:setArg(0, self.solverBuf)
	self.diffuseWorkKernelObj.obj:setArg(2, self.UBuf)
	self.diffuseWorkKernelObj.obj:setArg(3, self.PBuf)

	if self.eqn.useSourceTerm then
		self.addSourceKernelObj = self.solverProgramObj:kernel{name='addSource', domain=self.domainWithoutBorder}
		self.addSourceKernelObj.obj:setArg(0, self.solverBuf)
		self.addSourceKernelObj.obj:setArg(2, self.UBuf)
	end
end

function EulerBurgers:addDisplayVars()
	EulerBurgers.super.addDisplayVars(self)

	self:addDisplayVarGroup{
		name = 'P', 
		vars = {
			{P = '*value = buf[index];'},
		},
	}

	for j,xj in ipairs(xNames) do
		self:addDisplayVarGroup{
			name = 'intVel', 
			codePrefix = [[
	int indexInt = ]]..(j-1)..[[ + dim * index;
]],
			vars = range(0,self.dim-1):map(function(i)
				return {[xj..'_'..i] = '*value = buf['..i..' + indexInt];'}
			end),
		}
	end
end

local realptr = ffi.new'realparam[1]'
local function real(x)
	realptr[0] = x
	return realptr
end

function EulerBurgers:step(dt)
	-- calc deriv here
	self.integrator:integrate(dt, function(derivBuf)
		self.calcIntVelKernelObj()

		self.calcFluxKernelObj.obj:setArg(4, real(dt))
		self.calcFluxKernelObj()
	
		self.calcDerivFromFluxKernelObj.obj:setArg(1, derivBuf)
		self.calcDerivFromFluxKernelObj()
	
		if self.eqn.useSourceTerm then
			self.addSourceKernelObj.obj:setArg(1, derivBuf)
			self.addSourceKernelObj()
		end
	end)

	self:boundary()

	-- TODO potential update here
	
	self.integrator:integrate(dt, function(derivBuf)
		self.computePressureKernelObj()
	
		self.diffuseMomentumKernelObj.obj:setArg(1, derivBuf)
		self.diffuseMomentumKernelObj()
	end)
	
	self:boundary()
	
	self.integrator:integrate(dt, function(derivBuf)
		self.diffuseWorkKernelObj.obj:setArg(1, derivBuf)
		self.diffuseWorkKernelObj()
	end)
end

return EulerBurgers
