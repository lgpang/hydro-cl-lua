--[[
Based on 2008 Yano
--]]

local class = require 'ext.class'
local table = require 'ext.table'
local file = require 'ext.file'
local template = require 'template'
local EinsteinEqn = require 'eqn.einstein'
local symmath = require 'symmath'
local makeStruct = require 'eqn.makestruct'

local common = require 'common'()
local xNames = common.xNames
local symNames = common.symNames
local from3x3to6 = common.from3x3to6 
local from6to3x3 = common.from6to3x3 
local sym = common.sym


local Z4_2008Yano = class(EinsteinEqn)
Z4_2008Yano.name = 'Z4 (2008 Yano)'

local fluxVars = table{
	{a = 'real3'},
	{d = '_3sym3'},
	{K = 'sym3'},
	{Theta = 'real'},
	{Z = 'real3'},
}

Z4_2008Yano.consVars = table{
	{alpha = 'real'},
	{gamma = 'sym3'},
}:append(fluxVars)

Z4_2008Yano.numWaves = makeStruct.countScalars(fluxVars)
assert(Z4_2008Yano.numWaves == 31)

Z4_2008Yano.hasCalcDTCode = true
Z4_2008Yano.hasEigenCode = true
Z4_2008Yano.useSourceTerm = true

function Z4_2008Yano:createInitState()
	Z4_2008Yano.super.createInitState(self)
	self:addGuiVar{name = 'lambda', value = -1}
end

function Z4_2008Yano:getCommonFuncCode()
	return template([[
void setFlatSpace(global <?=eqn.cons_t?>* U, real3 x) {
	U->alpha = 1;
	U->gamma = sym3_ident;
	U->a = real3_zero;
	U->d.x = sym3_zero;
	U->d.y = sym3_zero;
	U->d.z = sym3_zero;
	U->K = sym3_zero;
	U->Theta = 0;
	U->Z = real3_zero;
}
]], {eqn=self})
end

Z4_2008Yano.initStateCode = [[
kernel void initState(
	constant <?=solver.solver_t?>* solver,
	global <?=eqn.cons_t?>* UBuf
) {
	SETBOUNDS(0,0);
	real3 x = cell_x(i);
	real3 mids = real3_real_mul(real3_add(mins, maxs), .5);
	
	global <?=eqn.cons_t?>* U = UBuf + index;
	setFlatSpace(U, x);

	real alpha = 1.;
	real3 beta_u = real3_zero;
	sym3 gamma_ll = sym3_ident;
	sym3 K_ll = sym3_zero;

	<?=code?>

	U->alpha = alpha;
	U->gamma = gamma_ll;
	U->K = K_ll;
	
	//Z_u n^u = 0
	//Theta = alpha n_u Z^u = alpha Z^u
	//for n_a = (-alpha, 0)
	//n^a = (1/alpha, -beta^i/alpha)
	//(Z_t - Z_i beta^i) / alpha = Theta ... = ?
	//Z^t n_t + Z^i n_i = -alpha Z^t = Theta
	U->Theta = 0;
	U->Z = real3_zero;
}

kernel void initDerivs(
	constant <?=solver.solver_t?>* solver,
	global <?=eqn.cons_t?>* UBuf
) {
	SETBOUNDS(numGhost,numGhost);
	global <?=eqn.cons_t?>* U = UBuf + index;

<? for i,xi in ipairs(xNames) do ?>
	U->a.<?=xi?> = (U[stepsize.<?=xi?>].alpha - U[-stepsize.<?=xi?>].alpha) / (solver->grid_dx.s<?=i-1?> * U->alpha);
	<? for j=0,2 do ?>
		<? for k=j,2 do ?>
	U->d.<?=xi?>.s<?=j..k?> = .5 * (U[stepsize.<?=xi?>].gamma.s<?=j..k?> - U[-stepsize.<?=xi?>].gamma.s<?=j..k?>) / solver->grid_dx.s<?=i-1?>;
		<? end ?>
	<? end ?>
<? end ?>
}
]]

Z4_2008Yano.solverCodeFile = 'eqn/z4.cl'

function Z4_2008Yano:getDisplayVars()
	local vars = Z4_2008Yano.super.getDisplayVars(self)
	vars:append{
		{det_gamma = '*value = sym3_det(U->gamma);'},
		{volume = '*value = U->alpha * sqrt(sym3_det(U->gamma));'},
		{f = '*value = calc_f(U->alpha);'},
		{K = [[
	real det_gamma = sym3_det(U->gamma);
	sym3 gammaU = sym3_inv(U->gamma, det_gamma);
	*value = sym3_dot(gammaU, U->K);
]]		},
		{expansion = [[
	real det_gamma = sym3_det(U->gamma);
	sym3 gammaU = sym3_inv(U->gamma, det_gamma);
	*value = -sym3_dot(gammaU, U->K);
]]		},
--[=[
	-- 1998 Bona et al
--[[
H = 1/2 ( R + K^2 - K_ij K^ij ) - alpha^2 8 pi rho
for 8 pi rho = G^00

momentum constraints
--]]
		{H = [[
	.5 * 
]]		},
--]=]

	-- shift-less gravity only
	-- gravity with shift is much more complex
	-- TODO add shift influence (which is lengthy)
		{gravity = [[
	real det_gamma = sym3_det(U->gamma);
	sym3 gammaU = sym3_inv(U->gamma, det_gamma);
	*value_real3 = real3_real_mul(sym3_real3_mul(gammaU, U->a), -U->alpha * U->alpha);
]], type='real3'},
	}
	
	return vars
end

Z4_2008Yano.eigenVars = table{
	{alpha = 'real'},
	{sqrt_f = 'real'},
	{gamma = 'sym3'},
	{gammaU = 'sym3'},
	{sqrt_gammaUjj = 'real3'},
}

function Z4_2008Yano:eigenWaveCodePrefix(side, eig, x, waveIndex)
	return template([[
	<? if side==0 then ?>
	real eig_lambdaLight = <?=eig?>.alpha * <?=eig?>.sqrt_gammaUjj.x;
	<? elseif side==1 then ?>
	real eig_lambdaLight = <?=eig?>.alpha * <?=eig?>.sqrt_gammaUjj.y;
	<? elseif side==2 then ?>
	real eig_lambdaLight = <?=eig?>.alpha * <?=eig?>.sqrt_gammaUjj.z;
	<? end ?>
	real eig_lambdaGauge = eig_lambdaLight * <?=eig?>.sqrt_f;
]], {
		eig = '('..eig..')',
		side = side,
	})
end

function Z4_2008Yano:eigenWaveCode(side, eig, x, waveIndex)

	local betaUi
	if self.useShift then
		betaUi = eig..'.beta_u.'..xNames[side+1]
	else
		betaUi = '0'
	end

	if waveIndex == 0 then
		return '-'..betaUi..' - eig_lambdaGauge'
	elseif waveIndex >= 1 and waveIndex <= 6 then
		return '-'..betaUi..' - eig_lambdaLight'
	elseif waveIndex >= 7 and waveIndex <= 23 then
		return '-'..betaUi
	elseif waveIndex >= 24 and waveIndex <= 29 then
		return '-'..betaUi..' + eig_lambdaLight'
	elseif waveIndex == 30 then
		return '-'..betaUi..' + eig_lambdaGauge'
	end

	error'got a bad waveIndex'
end



function Z4_2008Yano:fillRandom(epsilon)
	local ptr = Z4_2008Yano.super.fillRandom(self, epsilon)
	local solver = self.solver
	for i=0,solver.volume-1 do
		ptr[i].alpha = ptr[i].alpha + 1
		ptr[i].gamma.xx = ptr[i].gamma.xx + 1
		ptr[i].gamma.yy = ptr[i].gamma.yy + 1
		ptr[i].gamma.zz = ptr[i].gamma.zz + 1
	end
	solver.UBufObj:fromCPU(ptr)
	return ptr
end

return Z4_2008Yano
