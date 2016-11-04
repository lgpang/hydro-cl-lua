--[[
this has so much in common with Euler3D ...
and I don't want to keep updating the both of them ...
and I don't really care about this as much as the 3D version ...
so maybe I should have this subclass / steal from Euler3D?
--]]

local class = require 'ext.class'
local table = require 'ext.table'
local Equation = require 'eqn.eqn'

local Euler1D = class(Equation)
Euler1D.name = 'Euler1D'

Euler1D.numStates = 3

Euler1D.consVars = {'rho', 'mx', 'ETotal'}
Euler1D.primVars = {'rho', 'vx', 'P'}

-- notice the current cheap system just appends the dim to mirror on the var prefix
-- but in 1D, there is only 'mx', not 'my' or 'mz'
-- soo... the system will break for 2D and 3D. 
-- soo ... fix the system
Euler1D.mirrorVars = {{'mx'}, {}, {}}

Euler1D.displayVars = {
	'rho',
	'vx',
	'mx',
	'eInt',
	'eKin', 
	'eTotal', 
	'EInt', 
	'EKin', 
	'ETotal', 
	'P',
	'S', 
	'h',
	'H', 
	'hTotal',
	'HTotal',
} 

Euler1D.initStates = require 'init.euler'
Euler1D.initStateNames = table.map(Euler1D.initStates, function(info) return info.name end)

Euler1D.guiVars = table{
	require 'guivar.float'{name='gamma', value=7/5}
}
Euler1D.guiVarsForName = Euler1D.guiVars:map(function(var) return var, var.name end)

function Euler1D:getCodePrefix()
	return table{
		Euler1D.super.getCodePrefix(self),
		[[
#define gamma_1 (gamma-1.)
#define gamma_3 (gamma-3.)

prim_t primFromCons(cons_t U) {
	real EInt = U.ETotal - .5 * U.mx * U.mx / U.rho;
	return (prim_t){
		.rho = U.rho,
		.vx = U.mx / U.rho,
		.P = EInt / gamma_1,
	};
}
]]
	}:concat'\n'
end

function Euler1D:getTypeCode()
	return 
		require 'eqn.makestruct'('prim_t', self.primVars) .. '\n' ..
		Euler1D.super.getTypeCode(self) 
end

function Euler1D:getInitStateCode(solver)
	local initState = self.initStates[1+solver.initStatePtr[0]]
	assert(initState, "couldn't find initState "..solver.initStatePtr[0])	
	local code = initState.init(solver)	
	
	return table{
		[[
cons_t consFromPrim(prim_t W) {
	return (cons_t){
		.rho = W.rho,
		.mx = W.rho * W.vx,
		.ETotal = .5 * W.rho * W.vx * W.vx + W.P / gamma_1,
	};
}

__kernel void initState(
	__global cons_t* UBuf
) {
	SETBOUNDS(0,0);
	real3 x = CELL_X(i);
	real3 mids = real3_scale(real3_add(mins, maxs), .5);
	bool lhs = x.x < mids.x
#if dim > 1
		&& x.y < mids.y
#endif
#if dim > 2
		&& x.z < mids.z
#endif
	;
	real rho = 0;
	real vx = 0;
	real P = 0;

]] .. code .. [[

	UBuf[index] = consFromPrim((prim_t){.rho=rho, .vx=vx, .P=P});
}
]],
	}:concat'\n'
end

function Euler1D:getSolverCode(solver)	
	return table{
		'#include "eqn/euler1d.cl"',
	}:concat'\n'
end

function Euler1D:getCalcDisplayVarCode()
	return [[
	prim_t W = primFromCons(*U);
	switch (displayVar) {
	case display_U_rho: value = W.rho; break;
	case display_U_vx: value = W.vx; break;
	case display_U_P: value = W.P; break;
	case display_U_mx: value = U->mx; break;
	case display_U_eInt: value = W.P / (W.rho * gamma_1); break;
	case display_U_eKin: value = .5 * W.vx * W.vx; break;
	case display_U_eTotal: value = U->ETotal / W.rho; break;
	case display_U_EInt: value = W.P / gamma_1; break;
	case display_U_EKin: value = .5 * W.rho * W.vx * W.vx; break;
	case display_U_ETotal: value = U->ETotal; break;
	case display_U_S: value = W.P / pow(W.rho, (real)gamma); break;
	case display_U_H: value = W.P * gamma / gamma_1; break;
	case display_U_h: value = W.P * gamma / gamma_1 / W.rho; break;
	case display_U_HTotal: value = W.P * gamma / gamma_1 + .5 * W.rho * W.vx * W.vx; break;
	case display_U_hTotal: value = W.P * gamma / gamma_1 / W.rho + .5 * W.vx * W.vx; break;
	}
]]
end

return Euler1D
