local class = require 'ext.class'
local template = require 'template'
local Poisson = require 'solver.poisson'

local SelfGrav = class(Poisson)

SelfGrav.gravitationConstant = 1	---- 6.67384e-11 m^3 / (kg s^2)
SelfGrav.matterField = 'rho'
SelfGrav.momentumField = 'm'
SelfGrav.totalEnergyField = 'ETotal'

-- params for solver/poisson.cl 
function SelfGrav:getCodeParams()
	return {
		args = 'global '..self.solver.eqn.cons_t..'* UBuf',
		calcRho = template([[
#define gravitationalConstant <?=clnumber(self.gravitationConstant)?>
	global <?=eqn.cons_t?>* U = UBuf + index;
	//maybe a 4pi?  or is that only in the continuous case?
	rho = -gravitationalConstant * U-><?=self.matterField?>;
]], 
		{
			self = self,
			solver = self.solver,
			eqn = self.solver.eqn,
			clnumber = require 'clnumber',
		}),
	}
end

--should this be scaled by gravitationalConstant too?
function SelfGrav:getPoissonCode()
	return template(
		[[

kernel void calcGravityDeriv(
	global <?=eqn.cons_t?>* derivBuffer,
	global const <?=eqn.cons_t?>* UBuf
) {
	SETBOUNDS(2,2);
	
	global <?=eqn.cons_t?>* deriv = derivBuffer + index;
	const global <?=eqn.cons_t?>* U = UBuf + index;

	//for (int side = 0; side < dim; ++side) {
	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;
		int indexL = index - stepsize[side];
		int indexR = index + stepsize[side];
	
		real gradient = (UBuf[indexR].<?=self.potentialField?> - UBuf[indexL].<?=self.potentialField?>) / (2. * dx<?=side?>_at(i));
		real gravity = -gradient;

		deriv-><?=self.momentumField?>.s[side] -= U-><?=self.matterField?> * gravity;
		deriv-><?=self.totalEnergyField?> -= U-><?=self.matterField?> * gravity * U-><?=self.momentumField?>.s[side];
	}<? end ?>
}

]],
	{
		self = self,
		solver = self.solver,
		eqn = self.solver.eqn,
	})
end

function SelfGrav:refreshSolverProgram()
	SelfGrav.super.refreshSolverProgram(self)
	
	local solver = self.solver
	solver.calcGravityDerivKernel = solver.solverProgram:kernel'calcGravityDeriv'
	solver.calcGravityDerivKernel:setArg(1, solver.UBuf)
end

local field = 'gravityPoisson'
local enableField = 'useGravity'
local apply = SelfGrav:createBehavior(field, enableField)
return function(parent)
	local template = apply(parent)

	function template:step(dt)
		template.super.step(self, dt)
		
		if not self[enableField] then return end
		self.integrator:integrate(dt, function(derivBuf)
			self[field]:relax()
			self.calcGravityDerivKernel:setArg(0, derivBuf)
			self.app.cmds:enqueueNDRangeKernel{kernel=self.calcGravityDerivKernel, dim=self.dim, globalSize=self.gridSize:ptr(), localSize=self.localSize:ptr()}
		end)
	end

	return template
end
