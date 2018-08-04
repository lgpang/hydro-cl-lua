<?
local common = require 'common'()
local xNames = common.xNames
local symNames = common.symNames
local from3x3to6 = common.from3x3to6 
local from6to3x3 = common.from6to3x3 
local sym = common.sym
?>

kernel void calcDT(
	global real* dtBuf,
	const global <?=eqn.cons_t?>* UBuf
) {
	SETBOUNDS(0,0);
	if (OOB(numGhost,numGhost)) {
		dtBuf[index] = INFINITY;
		return;
	}
		
	const global <?=eqn.cons_t?>* U = UBuf + index;
	real det_gamma = sym3_det(U->gamma);
	real f = calc_f(U->alpha);
	
	//the only advantage of this calcDT over the default is that here this sqrt(f) is only called once
	real sqrt_f = sqrt(f);

	real dt = INFINITY;
	<? for side=0,solver.dim-1 do ?>{
		
		<? if side==0 then ?>
		real gammaUjj = (U->gamma.yy * U->gamma.zz - U->gamma.yz * U->gamma.yz) / det_gamma;
		<? elseif side==1 then ?>
		real gammaUjj = (U->gamma.xx * U->gamma.zz - U->gamma.xz * U->gamma.xz) / det_gamma;
		<? elseif side==2 then ?>
		real gammaUjj = (U->gamma.xx * U->gamma.yy - U->gamma.xy * U->gamma.xy) / det_gamma;
		<? end ?>	
		real lambdaLight = U->alpha * sqrt(gammaUjj);
		
		real lambdaGauge = lambdaLight * sqrt_f;
		real lambda = (real)max(lambdaGauge, lambdaLight);
		
		real lambdaMin = (real)min((real)0., -lambda);
		real lambdaMax = (real)max((real)0., lambda);
		dt = (real)min((real)dt, (real)(grid_dx<?=side?> / (fabs(lambdaMax - lambdaMin) + (real)1e-9)));
	}<? end ?>
	dtBuf[index] = dt; 
}

//used by PLM
<? for side=0,solver.dim-1 do ?>
<?=eqn.eigen_t?> eigen_forCell_<?=side?>(
	<?=eqn.cons_t?> U,
	real3 x 
) {
	<?=eqn.eigen_t?> eig;
	eig.alpha = U->alpha;
	eig.sqrt_f = sqrt(calc_f(U->alpha));
	eig.gamma = U->gamma;
	real det_gamma = sym3_det(U->gamma);
	eig.gammaU = sym3_inv(U->gamma, det_gamma);
	eig.sqrt_gammaUjj = _real3(sqrt(eig.gammaU.xx), sqrt(eig.gammaU.yy), sqrt(eig.gammaU.zz));
	return eig;
}
<? end ?>

<? for side=0,solver.dim-1 do ?>
range_t calcCellMinMaxEigenvalues_<?=side?>(
	const global <?=eqn.cons_t?>* U,
	real3 x
) {
	real det_gamma = sym3_det(U->gamma);
	
	<? if side==0 then ?>
	real gammaUjj = (U->gamma.yy * U->gamma.zz - U->gamma.yz * U->gamma.yz) / det_gamma;
	<? elseif side==1 then ?>
	real gammaUjj = (U->gamma.xx * U->gamma.zz - U->gamma.xz * U->gamma.xz) / det_gamma;
	<? elseif side==2 then ?>
	real gammaUjj = (U->gamma.xx * U->gamma.yy - U->gamma.xy * U->gamma.xy) / det_gamma;
	<? end ?>
	
	real lambdaLight = U->alpha * sqrt(gammaUjj);
	
	real f = calc_f(U->alpha);
	real lambdaGauge = lambdaLight * sqrt(f);

	real lambdaMax = max(lambdaGauge, lambdaLight);
	//= lambdaLight * max(sqrt(f), 1)

	return (range_t){
		.min = -lambdaMax, 
		.max = lambdaMax,
	};
}
<? end ?>

<?=eqn.eigen_t?> eigen_forInterface(
	<?=eqn.cons_t?> UL,
	<?=eqn.cons_t?> UR,
	real3 x,
	real3 n
) {
	real alpha = .5 * (UL.alpha + UR.alpha);
	sym3 avg_gamma = (sym3){
		.xx = .5 * (UL.gamma.xx + UR.gamma.xx),
		.xy = .5 * (UL.gamma.xy + UR.gamma.xy),
		.xz = .5 * (UL.gamma.xz + UR.gamma.xz),
		.yy = .5 * (UL.gamma.yy + UR.gamma.yy),
		.yz = .5 * (UL.gamma.yz + UR.gamma.yz),
		.zz = .5 * (UL.gamma.zz + UR.gamma.zz),
	};
	real det_avg_gamma = sym3_det(avg_gamma);

	<?=eqn.eigen_t?> eig;
	eig.alpha = alpha;
	eig.sqrt_f = sqrt(calc_f(alpha));
	eig.gammaU = sym3_inv(avg_gamma, det_avg_gamma);
	eig.sqrt_gammaUjj = _real3(sqrt(eig.gammaU.xx), sqrt(eig.gammaU.yy), sqrt(eig.gammaU.zz));
	return eig;
}

<? for side=0,solver.dim-1 do ?>
<?=eqn.waves_t?> eigen_leftTransform_<?=side?>(
	<?=eqn.eigen_t?> eig,
	<?=eqn.cons_t?> inputU,
	real3 pt 
) {
	<?=eqn.cons_t?> result;
	
	//input
	real3 a = real3_swap<?=side?>(inputU.a);							//0-2
	sym3 dx = sym3_swap<?=side?>(inputU.d.v<?=side?>);					//3-8
	sym3 dy = sym3_swap<?=side?>(inputU.d.v<?=side==1 and 0 or 1?>);	//9-14
	sym3 dz = sym3_swap<?=side?>(inputU.d.v<?=side==2 and 0 or 2?>);	//15-20
	sym3 K = sym3_swap<?=side?>(inputU.K);								//21-26
	real Theta = inputU.Theta;											//27
	real3 Z = real3_swap<?=side?>(inputU.Z);							//28-30

	//eig
	real sqrt_f = eig.sqrt_f;
	real f = sqrt_f * sqrt_f;	
	real fSq = f * f;
	real f_3_2 = f * sqrt_f;
	real f_5_2 = fSq * sqrt_f;

	real f_minus_1 = f - 1.;
	real f_minus_1_sq = f_minus_1 * f_minus_1;

	sym3 gamma = sym3_swap<?=side?>(eig.gamma);
	sym3 gammaU = sym3_swap<?=side?>(eig.gammaU);

	real3x3 K_ul = sym3_sym3_mul(gammaU, K);

	real tr_K = mat3_trace(K_ul);

	real sqrt_gUxx = eig.sqrt_gammaUjj.s<?=side?>;

	real aUx = a.x * gammaU.xx + a.y * gammaU.xy + a.z * gammaU.xz;
	real ZUx = Z.x * gammaU.xx + Z.y * gammaU.xy + Z.z * gammaU.xz;

	//d_i = d_ijk gamma^jk
	real3 d = _real3(
		sym3_dot(dx, gammaU),
		sym3_dot(dy, gammaU),
		sym3_dot(dz, gammaU));
	real3 dU = sym3_real3_mul(gammaU, d);

	//e_i = d_jki gamma^jk
	real3 e = (real3){
<? for i,xi in ipairs(xNames) do
?>		.<?=xi?> = 0. <? 
	for j,xj in ipairs(xNames) do
		for k,xk in ipairs(xNames) do
?> + d<?=xj?>.<?=sym(k,i)?> * gammaU.<?=sym(j,k)?><?
		end
	end
?>,
<? end
?>	};
	real3 eU = sym3_real3_mul(gammaU, e);

	result.ptr[0] = -.5 * (
		+ aUx / (sqrt_f * sqrt_gUxx)
		- tr_K 	
		+ (
			+ f * (m - 2.) * (ZUx + eU.x - dU.x) / (sqrt_f * sqrt_gUxx)
			+ (m * f - 2.) * Theta
		) / f_minus_1
	) / gammaU.xx;

	result.ptr[30] = .5 * (
		+ aUx / (sqrt_f * sqrt_gUxx)
		+ tr_K
		+ (
			+ f * (m - 2.) * (ZUx + eU.x - dU.x) / (sqrt_f * sqrt_gUxx)
			- (m * f - 2.) * Theta
		) / f_minus_1
	) / gammaU.xx;

	result.ptr[9] = -(
		+ d.z
		- e.z
		
		+ d_ull.x.xz
		+ d_ull.x.xz
		
		- d_llu.z.x.x
		- d_llu.x.z.x
		
		- 2. * dx.xz * gammaU.xx
		
		+ a.z
		- 2. * Z.z
	) / (2. * gammaU.xx);

	result.ptr[1] = .25 * (
		- a.z * gammaU.xx

		+ gammaU.xx * (d_llu.y.z.y - d_llu.z.y.y)
		+ gammaU.xy * (d_llu.z.y.x - d_llu.y.z.x)

		+ 2. * sqrt_gUxx * K_ul.x.z
		+ 2. * Z.z * gammaU.xx
	) / gammaU.xx;
	
	result.ptr[23] = (
		+ a.z * gammaU.xx
		
		+ gammaU.yy * gammaU.xx * dz.yy 
		+ gammaU.yz * gammaU.xx * dz.yz 
		+ gammaU.xy * gammaU.xz * dy.zz 
		+ gammaU.xy * gammaU.xy * dy.yz 
		
		- gammaU.xx * gammaU.yy * dy.yz 
		- gammaU.xx * gammaU.yz * dy.zz 
		- gammaU.xy * gammaU.xy * dz.yy 
		- gammaU.xy * gammaU.xz * dz.yz 
	
	) / (2. * gammaU.xx);
	result.ptr[24] = -(
		+ 2. * gammaU.xx * sqrt_gUxx * K.xz 
		+ gammaU.xy * gammaU.xz * dy.zz 
		- gammaU.xy * gammaU.xz * dz.yz 
		+ gammaU.xy * gammaU.xy * dy.yz 
		- gammaU.xy * gammaU.xy * dz.yy 
		+ 2. * gammaU.xy * K.yz * sqrt_gUxx 
		+ 2. * gammaU.xz * K.zz * sqrt_gUxx 
		- gammaU.yy * gammaU.xx * dy.yz 
		+ gammaU.yy * gammaU.xx * dz.yy 
		- gammaU.yz * gammaU.xx * dy.zz 
		+ gammaU.yz * gammaU.xx * dz.yz 
		
		+ a.z * gammaU.xx 
		- 2. * Z.z * gammaU.xx
	) / (4. * gammaU.xx);
	result.ptr[2] = (
		- a.y * gammaU.xx
		
		+ gammaU.xx * (d_llu.z.y.z - d_llu.y.z.z)
		+ gammaU.xz * (d_llu.y.z.x - d_llu.z.y.x)
		
		+ 2. * sqrt_gUxx * K_ul.x.y
		+ 2. * Z.y * gammaU.xx
	) / (4. * gammaU.xx);
	result.ptr[3] = .25 * (
		+ aU.x
	
		+ gammaU.xy * (d_llu.y.z.z - d_llu.z.y.z)
		+ gammaU.xz * (d_llu.z.y.y - d_llu.y.z.y)
		
		+ 2. * sqrt_gUxx * (K_ul.x.x - tr_K + Theta)
	) / gammaU.xx - .25 * a.x + .5 * Z.x;
	result.ptr[4] = (
		+ eU.x
		- dU.x
		
		+ Theta * sqrt_gUxx
		+ ZUx
	) / (2. * sqrt_gUxx);
	result.ptr[5] = (
		+ d_llu.z.z.x
		- d_ull.x.zz
		
		+ K.zz * sqrt_gUxx
	) / (2. * sqrt_gUxx);
	result.ptr[6] = (
		+ d_llu.z.y.x + d_llu.y.z.x - 2. * d_ull.x.yz
		
		+ 2. * K.yz * sqrt_gUxx
	) / (4. * sqrt_gUxx);
	result.ptr[7] = -(
		+ gammaU.xx * gammaU.yy * dy.xy
		- gammaU.xx * gammaU.yy * dx.yy
		- gammaU.xx * gammaU.yy * m * dy.xy
		+ gammaU.xx * gammaU.yy * m * dx.yy
		+ gammaU.xx * gammaU.yz * dy.xz
		+ gammaU.xx * gammaU.yz * dz.xy
		- 2. * gammaU.xx * gammaU.yz * dx.yz
		- gammaU.xx * gammaU.yz * m * dy.xz
		- gammaU.xx * gammaU.yz * m * dz.xy
		+ 2. * gammaU.xx * gammaU.yz * m * dx.yz
		+ gammaU.xx * gammaU.zz * dz.xz
		- gammaU.xx * gammaU.zz * dx.zz
		- gammaU.xx * gammaU.zz * m * dz.xz
		+ gammaU.xx * gammaU.zz * m * dx.zz
		- 2. * gammaU.xy * gammaU.xz * dy.xz
		- 2. * gammaU.xy * gammaU.xz * dz.xy
		+ 4. * gammaU.xy * gammaU.xz * dx.yz
		+ gammaU.xy * gammaU.xz * m * dy.xz
		+ gammaU.xy * gammaU.xz * m * dz.xy
		- 2. * gammaU.xy * gammaU.xz * m * dx.yz
		- 2. * gammaU.xy * gammaU.yz * dy.yz
		+ 2. * gammaU.xy * gammaU.yz * dz.yy
		+ gammaU.xy * gammaU.yz * m * dy.yz
		- gammaU.xy * gammaU.yz * m * dz.yy
		- 2. * gammaU.xy * gammaU.zz * dy.zz
		+ 2. * gammaU.xy * gammaU.zz * dz.yz
		+ gammaU.xy * gammaU.zz * m * dy.zz
		- gammaU.xy * gammaU.zz * m * dz.yz
		- 2. * gammaU.xy * gammaU.xy * dy.xy
		+ 2. * gammaU.xy * gammaU.xy * dx.yy
		+ gammaU.xy * gammaU.xy * m * dy.xy
		- gammaU.xy * gammaU.xy * m * dx.yy
		+ 2. * gammaU.xz * gammaU.yy * dy.yz
		- 2. * gammaU.xz * gammaU.yy * dz.yy
		- gammaU.xz * gammaU.yy * m * dy.yz
		+ gammaU.xz * gammaU.yy * m * dz.yy
		+ 2. * gammaU.xz * gammaU.yz * dy.zz
		- 2. * gammaU.xz * gammaU.yz * dz.yz
		- gammaU.xz * gammaU.yz * m * dy.zz
		+ gammaU.xz * gammaU.yz * m * dz.yz
		- 2. * gammaU.xz * gammaU.xz * dz.xz
		+ 2. * gammaU.xz * gammaU.xz * dx.zz
		+ gammaU.xz * gammaU.xz * m * dz.xz
		- gammaU.xz * gammaU.xz * m * dx.zz
		- gammaU.xx * gammaU.xx * dx.xx

		+ gammaU.xx * a.x
		- aU.x * f_minus_1 / f
		- 2. * gammaU.xx * Z.x
		- (m - 2.) * ZUx
	) / (gammaU.xx * gammaU.xx);
	result.ptr[8] = -(
		+ d_y
		- e_y
		
		+ d_ull.x.xy
		+ d_ull.x.xy
		- d_llu.x.y.x
		- d_llu.y.x.x
		
		+ a.y
		- 2. * Z.y
	) / (2. * gammaU.xx)
	+ dx.xy
	;
	
	result.ptr[22] = -(
		+ gammaU.xy * gammaU.xz * dy.yz 
		- gammaU.xy * gammaU.xz * dz.yy 
		+ gammaU.xz * gammaU.xz * dy.zz 
		- gammaU.xz * gammaU.xz * dz.yz 
		- gammaU.yz * gammaU.xx * dy.yz 
		+ gammaU.yz * gammaU.xx * dz.yy 
		- gammaU.zz * gammaU.xx * dy.zz 
		+ gammaU.zz * gammaU.xx * dz.yz 
	) / (2. * gammaU.xx)
	+ .5 * a.y
	;

	result.ptr[25] = -(
		+ 2. * gammaU.xx * sqrt_gUxx * K.xy 
		+ 2. * gammaU.xy * K.yy * sqrt_gUxx 
		+ 2. * gammaU.xz * K.yz * sqrt_gUxx 
		
		- gammaU.xy * gammaU.xz * dy.yz 
		+ gammaU.xy * gammaU.xz * dz.yy 
		- gammaU.xz * gammaU.xz * dy.zz 
		+ gammaU.xz * gammaU.xz * dz.yz 
		+ gammaU.yz * gammaU.xx * dy.yz 
		- gammaU.yz * gammaU.xx * dz.yy 
		+ gammaU.zz * gammaU.xx * dy.zz 
		- gammaU.zz * gammaU.xx * dz.yz 
		
	) / (4. * gammaU.xx)
	- .25 * a.y
	+ .5 * Z.y;
	result.ptr[26] = .25 * (
		+ aU.x
		
		+ gammaU.xy * gammaU.yz * dy.yz 
		- gammaU.xy * gammaU.yz * dz.yy 
		+ gammaU.xy * gammaU.zz * dy.zz 
		- gammaU.xy * gammaU.zz * dz.yz 
		- gammaU.xz * gammaU.yy * dy.yz 
		+ gammaU.xz * gammaU.yy * dz.yy 
		- gammaU.xz * gammaU.yz * dy.zz 
		+ gammaU.xz * gammaU.yz * dz.yz 
	
		- 2. * sqrt_gUxx * (K_ul.x.x - tr_K + Theta)
	) / gammaU.xx - .25 * a.x + .5 * Z.x;
	result.ptr[27] = -.5 * (
		+ gammaU.xx * gammaU.yy * dy.xy 
		- gammaU.xx * gammaU.yy * dx.yy 
		+ gammaU.xx * gammaU.yz * dy.xz 
		+ gammaU.xx * gammaU.yz * dz.xy 
		- 2. * gammaU.xx * gammaU.yz * dx.yz 
		+ gammaU.xx * gammaU.zz * dz.xz 
		- gammaU.xx * gammaU.zz * dx.zz 
		- gammaU.xy * gammaU.xz * dy.xz 
		- gammaU.xy * gammaU.xz * dz.xy 
		+ 2. * gammaU.xy * gammaU.xz * dx.yz 
		- gammaU.xy * gammaU.yz * dy.yz 
		+ gammaU.xy * gammaU.yz * dz.yy 
		- gammaU.xy * gammaU.zz * dy.zz 
		+ gammaU.xy * gammaU.zz * dz.yz 
		- gammaU.xy * gammaU.xy * dy.xy 
		+ gammaU.xy * gammaU.xy * dx.yy 
		+ gammaU.xz * gammaU.yy * dy.yz 
		- gammaU.xz * gammaU.yy * dz.yy 
		+ gammaU.xz * gammaU.yz * dy.zz 
		- gammaU.xz * gammaU.yz * dz.yz 
		- gammaU.xz * gammaU.xz * dz.xz 
		+ gammaU.xz * gammaU.xz * dx.zz 
		+ ZUx
	) / sqrt_gUxx + .5 * Theta;
	result.ptr[28] = -.5 * (
		+ gammaU.xx * dz.xz 
		- gammaU.xx * dx.zz 
		- gammaU.xy * dy.zz 
		+ gammaU.xy * dz.yz 
	) / sqrt_gUxx + .5 * K.zz;
	result.ptr[29] = -.25 * (
		+ gammaU.xx * dy.xz 
		+ gammaU.xx * dz.xy 
		- 2. * gammaU.xx * dx.yz 
		- gammaU.xy * dy.yz 
		+ gammaU.xy * dz.yy 
		+ gammaU.xz * dy.zz 
		- gammaU.xz * dz.yz 
	) / sqrt_gUxx + .5 * K.yz;

	result.ptr[10] = dy.xx;
	result.ptr[11] = dy.xy;
	result.ptr[12] = dy.xz;
	result.ptr[13] = dy.yy;
	result.ptr[14] = dy.yz;
	result.ptr[15] = dy.zz;
	result.ptr[16] = dz.xx;
	result.ptr[17] = dz.xy;
	result.ptr[18] = dz.xz;
	result.ptr[19] = dz.yy;
	result.ptr[20] = dz.yz;
	result.ptr[21] = dz.zz;

	return result;
}

<?=eqn.cons_t?> eigen_rightTransform_<?=side?>(
	<?=eqn.eigen_t?> eig,
	<?=eqn.waves_t?> input,
	real3 unused
) {
	real sqrt_f = eig.sqrt_f;
	real f = sqrt_f * sqrt_f;
	real fSq = f * f;
	real f_3_2 = f * sqrt_f;
	sym3 gamma = sym3_swap<?=side?>(eig.gamma);
	sym3 gammaU = sym3_swap<?=side?>(eig.gammaU);

	a.x = (gammaU.xy * gammaU.yz * input.ptr[14] * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.yz * input.ptr[14] * f * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.yz * input.ptr[19] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.yz * input.ptr[19] * f * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.zz * input.ptr[15] * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.zz * input.ptr[15] * f * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.zz * input.ptr[20] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.zz * input.ptr[20] * f * 1. / sqrt(gammaU.xx) 
		- 2. * gammaU.xy * input.ptr[22] * 1. / sqrt(gammaU.xx) 
		+ 2. * gammaU.xy * input.ptr[22] * f * 1. / sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.yy * input.ptr[14] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * gammaU.yy * input.ptr[14] * f * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * gammaU.yy * input.ptr[19] * 1. / sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.yy * input.ptr[19] * f * 1. / sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.yz * input.ptr[15] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * gammaU.yz * input.ptr[15] * f * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * gammaU.yz * input.ptr[20] * 1. / sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.yz * input.ptr[20] * f * 1. / sqrt(gammaU.xx) 
		- 2. * gammaU.xz * input.ptr[23] * 1. / sqrt(gammaU.xx) 
		+ 2. * gammaU.xz * input.ptr[23] * f * 1. / sqrt(gammaU.xx) 
		+ f_3_2 * gammaU.xx * input.ptr[0] 
		- sqrt_f * gammaU.xx * input.ptr[0] 
		+ sqrt_f * gammaU.xx * input.ptr[30] 
		- f_3_2 * gammaU.xx * input.ptr[30] 
		+ 2. * f * input.ptr[27] 
		- 2. * f * input.ptr[4] 
		- f * m * input.ptr[27] 
		+ f * m * input.ptr[4]) / (sqrt(gammaU.xx) * (1. 
		- f));
	a.y = (gammaU.xy * gammaU.xz * input.ptr[14] 
		- gammaU.xy * gammaU.xz * input.ptr[19] 
		+ gammaU.xz * gammaU.xz * input.ptr[15] 
		- gammaU.xz * gammaU.xz * input.ptr[20] 
		- gammaU.yz * gammaU.xx * input.ptr[14] 
		+ gammaU.yz * gammaU.xx * input.ptr[19] 
		- gammaU.zz * gammaU.xx * input.ptr[15] 
		+ gammaU.zz * gammaU.xx * input.ptr[20] 
		+ 2. * input.ptr[22] * gammaU.xx) / gammaU.xx;
	a.z = (
		-(gammaU.xy * gammaU.xz * input.ptr[15] 
		- gammaU.xy * gammaU.xz * input.ptr[20] 
		+ gammaU.xy * gammaU.xy * input.ptr[14] 
		- gammaU.xy * gammaU.xy * input.ptr[19] 
		- gammaU.yy * gammaU.xx * input.ptr[14] 
		+ gammaU.yy * gammaU.xx * input.ptr[19] 
		- gammaU.yz * gammaU.xx * input.ptr[15] 
		+ gammaU.yz * gammaU.xx * input.ptr[20] 
		- 2. * input.ptr[23] * gammaU.xx)) / gammaU.xx;
	dx.xx = (gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * f_3_2 * input.ptr[4] 
		- gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * f_3_2 * m * input.ptr[4] 
		- gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[27] * sqrt_f 
		- sqrt(gammaU.xx) * gammaU.yy * input.ptr[4] * gammaU.xy * gammaU.xy * sqrt_f 
		+ gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[4] * sqrt_f 
		- 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[29] * sqrt(gammaU.xx) * sqrt_f 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[29] * 1. / sqrt(gammaU.xx) * sqrt_f 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[29] * f_3_2 * 1. / sqrt(gammaU.xx) 
		+ 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[29] * f_3_2 * sqrt(gammaU.xx) 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[6] * 1. / sqrt(gammaU.xx) * sqrt_f 
		+ 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[6] * sqrt(gammaU.xx) * sqrt_f 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[6] * f_3_2 * 1. / sqrt(gammaU.xx) 
		- 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[6] * f_3_2 * sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[25] * sqrt_f 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[25] * f_3_2 
		+ gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[25] * f_3_2 * gammaU.xx 
		- gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[25] * sqrt_f * gammaU.xx 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[2] * sqrt_f 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[2] * f_3_2 
		+ gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[2] * f_3_2 * gammaU.xx 
		- gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[2] * sqrt_f * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * sqrt(gammaU.xx) * gammaU.yy * sqrt_f 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * 1. / sqrt(gammaU.xx) * sqrt_f 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * f_3_2 * 1. / sqrt(gammaU.xx) 
		- 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * f_3_2 * sqrt(gammaU.xx) * gammaU.yy 
		- 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * sqrt(gammaU.xx) * gammaU.yy * sqrt_f 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * 1. / sqrt(gammaU.xx) * sqrt_f 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * f_3_2 * 1. / sqrt(gammaU.xx) 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * f_3_2 * sqrt(gammaU.xx) * gammaU.yy 
		+ gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * sqrt(gammaU.xx) * gammaU.yy * sqrt_f 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * 1. / sqrt(gammaU.xx) * sqrt_f 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * f_3_2 * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * f_3_2 * sqrt(gammaU.xx) * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * sqrt(gammaU.xx) * gammaU.yy * sqrt_f 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * 1. / sqrt(gammaU.xx) * sqrt_f 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * f_3_2 * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * f_3_2 * sqrt(gammaU.xx) * gammaU.yy 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f_3_2 * input.ptr[27] * 1. / sqrt(gammaU.xx) 
		+ 3. * gammaU.xy * gammaU.xy * f_3_2 * input.ptr[27] * sqrt(gammaU.xx) * gammaU.yy 
		- 3. * gammaU.xy * gammaU.xy * input.ptr[26] * gammaU.yy * sqrt_f * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[26] * sqrt_f 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[26] * f_3_2 
		+ 3. * gammaU.xy * gammaU.xy * input.ptr[26] * f_3_2 * gammaU.yy * gammaU.xx 
		+ gammaU.xy * gammaU.xy * input.ptr[27] * sqrt(gammaU.xx) * gammaU.yy * sqrt_f 
		+ 3. * gammaU.xy * gammaU.xy * input.ptr[3] * gammaU.yy * f_3_2 * gammaU.xx 
		- 3. * gammaU.xy * gammaU.xy * input.ptr[3] * gammaU.yy * sqrt_f * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[3] * sqrt_f 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[3] * f_3_2 
		- gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[1] * sqrt_f * gammaU.xx 
		+ gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[1] * f_3_2 * gammaU.xx 
		- gammaU.xz * gammaU.yy * input.ptr[1] * f_3_2 * gammaU.xy * gammaU.xy 
		+ gammaU.xz * gammaU.yy * input.ptr[1] * sqrt_f * gammaU.xy * gammaU.xy 
		+ gammaU.xz * gammaU.yy * input.ptr[24] * gammaU.xy * gammaU.xy * sqrt_f 
		+ gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[24] * f_3_2 * gammaU.xx 
		- gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[24] * sqrt_f * gammaU.xx 
		- gammaU.xz * gammaU.yy * input.ptr[24] * f_3_2 * gammaU.xy * gammaU.xy 
		+ gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[28] * 1. / sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * sqrt_f 
		- gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[28] * sqrt(gammaU.xx) * sqrt_f 
		+ gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[28] * f_3_2 * sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[28] * f_3_2 * 1. / sqrt(gammaU.xx) * gammaU.xy * gammaU.xy 
		- gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[5] * 1. / sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * sqrt_f 
		+ gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[5] * sqrt(gammaU.xx) * sqrt_f 
		- gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[5] * f_3_2 * sqrt(gammaU.xx) 
		+ gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[5] * f_3_2 * 1. / sqrt(gammaU.xx) * gammaU.xy * gammaU.xy 
		+ gammaU.yy * gammaU.yy * input.ptr[26] * sqrt_f * gammaU.xx * gammaU.xx 
		- gammaU.yy * gammaU.yy * input.ptr[26] * f_3_2 * gammaU.xx * gammaU.xx 
		- gammaU.yy * gammaU.yy * input.ptr[3] * f_3_2 * gammaU.xx * gammaU.xx 
		+ gammaU.yy * gammaU.yy * input.ptr[3] * sqrt_f * gammaU.xx * gammaU.xx 
		- f_3_2 * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[27] 
		+ 2. * f_3_2 * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[4] * 1. / sqrt(gammaU.xx) 
		- 3. * f_3_2 * gammaU.xy * gammaU.xy * input.ptr[4] * sqrt(gammaU.xx) * gammaU.yy 
		- f_3_2 * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * m * input.ptr[4] * 1. / sqrt(gammaU.xx) 
		+ 2. * f_3_2 * gammaU.xy * gammaU.xy * m * input.ptr[4] * sqrt(gammaU.xx) * gammaU.yy 
		+ f_3_2 * m * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[27] 
		+ f_3_2 * m * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[27] * 1. / sqrt(gammaU.xx) 
		- 2. * f_3_2 * m * gammaU.xy * gammaU.xy * input.ptr[27] * sqrt(gammaU.xx) * gammaU.yy 
		+ input.ptr[0] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * input.ptr[0] * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.xy * gammaU.yy 
		+ 2. * input.ptr[0] * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.xy * gammaU.yy * f 
		- input.ptr[0] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f 
		+ input.ptr[0] * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy 
		- input.ptr[0] * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * f 
		- input.ptr[30] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		+ 2. * input.ptr[30] * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.xy * gammaU.yy 
		- input.ptr[30] * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy 
		+ input.ptr[30] * sqrt(gammaU.xx) * f * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * input.ptr[30] * gammaU.xx * sqrt_gUxx * f * gammaU.xy * gammaU.xy * gammaU.yy 
		+ input.ptr[30] * gammaU.xx * gammaU.xx * sqrt_gUxx * f * gammaU.yy * gammaU.yy 
		- input.ptr[7] * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * sqrt_f 
		+ input.ptr[7] * gammaU.xx * gammaU.xx * gammaU.xx * f_3_2 * gammaU.yy * gammaU.yy 
		+ 2. * input.ptr[7] * gammaU.xy * gammaU.xy * gammaU.yy * sqrt_f * gammaU.xx * gammaU.xx 
		- input.ptr[7] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * sqrt_f * gammaU.xx 
		+ input.ptr[7] * f_3_2 * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xx 
		- 2. * input.ptr[7] * f_3_2 * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.xx * gammaU.xx) / (
		-gammaU.xx * sqrt_f * (gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- f * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xx * gammaU.xy * gammaU.xy * gammaU.yy 
		+ 2. * gammaU.xx * f * gammaU.xy * gammaU.xy * gammaU.yy 
		+ gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy 
		- gammaU.xx * gammaU.xx * f * gammaU.yy * gammaU.yy));
	dx.xy = (2. * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] 
		- 2. * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.yz * input.ptr[29] * gammaU.yy 
		- 2. * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] 
		+ 2. * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.yz * input.ptr[6] * gammaU.yy 
		+ gammaU.xy * gammaU.xy * gammaU.xy * sqrt(gammaU.xx) * gammaU.zz * input.ptr[28] 
		- gammaU.xy * gammaU.xx * sqrt_gUxx * gammaU.zz * input.ptr[28] * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * sqrt(gammaU.xx) * gammaU.zz * input.ptr[5] 
		+ gammaU.xy * gammaU.xx * sqrt_gUxx * gammaU.zz * input.ptr[5] * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[1] 
		+ gammaU.xy * gammaU.xz * input.ptr[1] * gammaU.xx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[24] 
		+ gammaU.xy * gammaU.xz * input.ptr[24] * gammaU.xx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[28] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[28] * sqrt(gammaU.xx) * gammaU.yy 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[5] * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[5] * sqrt(gammaU.xx) * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[26] * gammaU.xx 
		+ gammaU.xy * input.ptr[26] * gammaU.xx * gammaU.xx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[27] * sqrt(gammaU.xx) 
		+ gammaU.xy * input.ptr[27] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[3] * gammaU.xx 
		+ gammaU.xy * input.ptr[3] * gammaU.xx * gammaU.xx * gammaU.yy 
		+ gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[4] * sqrt(gammaU.xx) 
		- gammaU.xy * input.ptr[4] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		+ gammaU.xz * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[29] 
		- gammaU.xz * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[6] 
		- gammaU.xz * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[29] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[6] * 1. / sqrt(gammaU.xx) 
		+ gammaU.yy * gammaU.yy * input.ptr[25] * gammaU.xx * gammaU.xx 
		- gammaU.yy * input.ptr[25] * gammaU.xy * gammaU.xy * gammaU.xx 
		+ gammaU.yy * gammaU.yy * input.ptr[2] * gammaU.xx * gammaU.xx 
		- gammaU.yy * input.ptr[2] * gammaU.xx * gammaU.xy * gammaU.xy 
		- input.ptr[8] * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy 
		- input.ptr[8] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xx 
		+ 2. * input.ptr[8] * gammaU.xy * gammaU.xy * gammaU.xx * gammaU.xx * gammaU.yy) / (
		-gammaU.xx * (gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xx * gammaU.xy * gammaU.xy * gammaU.yy 
		+ gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy));
	dx.xz = (
		-(gammaU.xy * input.ptr[29] * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * input.ptr[6] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * input.ptr[28] * 1. / sqrt(gammaU.xx) 
		- gammaU.xz * input.ptr[5] * 1. / sqrt(gammaU.xx) 
		+ input.ptr[1] 
		+ input.ptr[24] 
		- input.ptr[9] * gammaU.xx)) / gammaU.xx;
	dx.yy = (2. * gammaU.xx * gammaU.yz * input.ptr[29] * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xx * gammaU.xx * gammaU.yz * input.ptr[29] * gammaU.yy 
		- 2. * gammaU.xx * gammaU.yz * input.ptr[6] * gammaU.xy * gammaU.xy 
		+ 2. * gammaU.xx * gammaU.xx * gammaU.yz * input.ptr[6] * gammaU.yy 
		+ gammaU.xx * gammaU.zz * input.ptr[28] * gammaU.xy * gammaU.xy 
		- gammaU.xx * gammaU.xx * gammaU.zz * input.ptr[28] * gammaU.yy 
		- gammaU.xx * gammaU.zz * input.ptr[5] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * gammaU.xx * gammaU.zz * input.ptr[5] * gammaU.yy 
		- gammaU.xx * sqrt_gUxx * input.ptr[26] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * gammaU.xx * sqrt_gUxx * input.ptr[26] * gammaU.yy 
		- gammaU.xx * input.ptr[27] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * gammaU.xx * input.ptr[27] * gammaU.yy 
		- gammaU.xx * sqrt_gUxx * input.ptr[3] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * gammaU.xx * sqrt_gUxx * input.ptr[3] * gammaU.yy 
		+ gammaU.xx * input.ptr[4] * gammaU.xy * gammaU.xy 
		- gammaU.xx * gammaU.xx * input.ptr[4] * gammaU.yy 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[29] 
		+ 2. * gammaU.xy * gammaU.xz * input.ptr[29] * gammaU.xx * gammaU.yy 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[6] 
		- 2. * gammaU.xy * gammaU.xz * input.ptr[6] * gammaU.xx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[25] * sqrt(gammaU.xx) 
		+ gammaU.xy * input.ptr[25] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[2] * sqrt(gammaU.xx) 
		+ gammaU.xy * input.ptr[2] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		+ gammaU.xz * input.ptr[14] * 1. / sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xz * input.ptr[14] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.yy 
		+ gammaU.xz * input.ptr[14] * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy 
		- gammaU.xz * input.ptr[19] * 1. / sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		+ 2. * gammaU.xz * input.ptr[19] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.yy 
		- gammaU.xz * input.ptr[19] * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy 
		+ gammaU.xz * input.ptr[1] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		- gammaU.xz * input.ptr[1] * gammaU.xy * gammaU.xy * sqrt(gammaU.xx) 
		- gammaU.xz * input.ptr[24] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy 
		+ gammaU.xz * input.ptr[24] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		+ gammaU.xz * gammaU.xz * input.ptr[28] * gammaU.xx * gammaU.yy 
		- gammaU.xz * gammaU.xz * input.ptr[28] * gammaU.xy * gammaU.xy 
		- gammaU.xz * gammaU.xz * input.ptr[5] * gammaU.xx * gammaU.yy 
		+ gammaU.xz * gammaU.xz * input.ptr[5] * gammaU.xy * gammaU.xy 
		+ input.ptr[11] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * input.ptr[11] * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.xy * gammaU.yy 
		+ input.ptr[11] * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy) / (sqrt(gammaU.xx) * (gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xx * gammaU.xy * gammaU.xy * gammaU.yy 
		+ gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy));
	dx.yz = (
		-(gammaU.xy * input.ptr[14] * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * input.ptr[19] * 1. / sqrt(gammaU.xx) 
		- gammaU.xz * input.ptr[15] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * input.ptr[20] * 1. / sqrt(gammaU.xx) 
		- input.ptr[12] * sqrt(gammaU.xx) 
		- input.ptr[17] * sqrt(gammaU.xx) 
		- 2. * input.ptr[29] 
		+ 2. * input.ptr[6])) / (2. * sqrt(gammaU.xx));
	dx.zz = (
		-(gammaU.xy * input.ptr[15] * 1. / sqrt(gammaU.xx) 
		- gammaU.xy * input.ptr[20] * 1. / sqrt(gammaU.xx) 
		- input.ptr[18] * sqrt(gammaU.xx) 
		- input.ptr[28] 
		+ input.ptr[5])) / sqrt(gammaU.xx);
	dy.xx = input.ptr[10];
	dy.xy = input.ptr[11];
	dy.xz = input.ptr[12];
	dy.yy = input.ptr[13];
	dy.yz = input.ptr[14];
	dy.zz = input.ptr[15];
	dz.xx = input.ptr[16];
	dz.xy = input.ptr[17];
	dz.xz = input.ptr[18];
	dz.yy = input.ptr[19];
	dz.yz = input.ptr[20];
	dz.zz = input.ptr[21];
	K.xx = (gammaU.xx * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[26] 
		- gammaU.xx * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[26] * f 
		- gammaU.xx * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[3] 
		+ gammaU.xx * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[3] * f 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[29] 
		+ 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[29] * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[29] * gammaU.xx * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[29] * f 
		+ 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[29] * f * gammaU.xx * gammaU.xx 
		- 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[29] * f * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[6] 
		+ 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[6] * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[6] * gammaU.xx * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * input.ptr[6] * f 
		+ 2. * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[6] * f * gammaU.xx * gammaU.xx 
		- 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[6] * f * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[25] * gammaU.xx * sqrt_gUxx 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[25] * sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[25] * gammaU.xx * gammaU.xx * sqrt_gUxx 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[25] * sqrt(gammaU.xx) * f 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[25] * gammaU.xx * sqrt_gUxx * f 
		+ gammaU.xy * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[25] * gammaU.xx * gammaU.xx * sqrt_gUxx * f 
		+ gammaU.xy * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[2] * gammaU.xx * gammaU.xx * sqrt_gUxx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[2] * gammaU.xx * sqrt_gUxx 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[2] * sqrt(gammaU.xx) 
		- gammaU.xy * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[2] * f * gammaU.xx * gammaU.xx * sqrt_gUxx 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * input.ptr[2] * f * sqrt(gammaU.xx) 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.yy * input.ptr[2] * f * gammaU.xx * sqrt_gUxx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.yz * input.ptr[29] 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		- 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * gammaU.yy * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * gammaU.yy * gammaU.yy * f * gammaU.xx * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.yz * input.ptr[29] * f 
		+ 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] * f * gammaU.yy * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.yz * input.ptr[6] 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		- 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * gammaU.yy * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * gammaU.yy * gammaU.yy * f * gammaU.xx * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.yz * input.ptr[6] * f 
		+ 4. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] * f * gammaU.yy * gammaU.xx 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.zz * input.ptr[28] 
		+ gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * gammaU.yy * gammaU.xx 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.zz * input.ptr[28] * f 
		- gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * f * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[28] * f * gammaU.yy * gammaU.xx 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.zz * input.ptr[5] 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * gammaU.yy * gammaU.xx 
		+ gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.zz * input.ptr[5] * f 
		- gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * f * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.zz * input.ptr[5] * f * gammaU.yy * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * f * input.ptr[27] 
		- 5. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f * input.ptr[27] * gammaU.yy * gammaU.xx 
		+ 4. * gammaU.xy * gammaU.xy * f * input.ptr[27] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * f * input.ptr[4] 
		+ 4. * gammaU.xy * gammaU.xy * f * input.ptr[4] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		- 5. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f * input.ptr[4] * gammaU.yy * gammaU.xx 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * input.ptr[26] * sqrt(gammaU.xx) 
		- 4. * gammaU.xy * gammaU.xy * input.ptr[26] * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy 
		+ 5. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[26] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		+ 4. * gammaU.xy * gammaU.xy * input.ptr[26] * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * f 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * input.ptr[26] * sqrt(gammaU.xx) * f 
		- 5. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[26] * gammaU.xx * sqrt_gUxx * f * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[27] * gammaU.yy * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * input.ptr[27] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * input.ptr[3] * sqrt(gammaU.xx) 
		- 5. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[3] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		+ 4. * gammaU.xy * gammaU.xy * input.ptr[3] * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * input.ptr[3] * f * sqrt(gammaU.xx) 
		- 4. * gammaU.xy * gammaU.xy * input.ptr[3] * f * gammaU.xx * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy 
		+ 5. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[3] * f * gammaU.xx * sqrt_gUxx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[4] * gammaU.yy * gammaU.xx 
		+ 2. * gammaU.xy * gammaU.xy * input.ptr[4] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		+ gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[1] * gammaU.xx * gammaU.xx * sqrt_gUxx 
		- 2. * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[1] * gammaU.xy * gammaU.xy * gammaU.xx * sqrt_gUxx 
		+ gammaU.xz * gammaU.yy * input.ptr[1] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[1] * f * gammaU.xx * gammaU.xx * sqrt_gUxx 
		+ 2. * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[1] * f * gammaU.xy * gammaU.xy * gammaU.xx * sqrt_gUxx 
		- gammaU.xz * gammaU.yy * input.ptr[1] * f * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[24] * gammaU.xx * gammaU.xx * sqrt_gUxx 
		+ 2. * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[24] * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.xy 
		- gammaU.xz * gammaU.yy * input.ptr[24] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[24] * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.xy * f 
		+ gammaU.xz * gammaU.yy * input.ptr[24] * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f 
		+ gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[24] * gammaU.xx * gammaU.xx * sqrt_gUxx * f 
		- gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[28] * gammaU.xx * gammaU.xx 
		- gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[28] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		+ 2. * gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[28] * gammaU.xy * gammaU.xy * gammaU.xx 
		+ gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[28] * f * gammaU.xx * gammaU.xx 
		+ gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[28] * f * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[28] * f * gammaU.xy * gammaU.xy * gammaU.xx 
		- gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[5] * gammaU.xx * gammaU.xx 
		- gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[5] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		+ 2. * gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[5] * gammaU.xy * gammaU.xy * gammaU.xx 
		+ gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[5] * f * gammaU.xx * gammaU.xx 
		+ gammaU.xz * gammaU.xz * gammaU.yy * input.ptr[5] * f * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xz * gammaU.xz * gammaU.yy * gammaU.yy * input.ptr[5] * f * gammaU.xy * gammaU.xy * gammaU.xx 
		- gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[27] * gammaU.xx * gammaU.xx * gammaU.xx 
		- gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[4] * gammaU.xx * gammaU.xx * gammaU.xx 
		- f * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[27] * gammaU.xx * gammaU.xx * gammaU.xx 
		- f * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[4] * gammaU.xx * gammaU.xx * gammaU.xx 
		- f * m * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * input.ptr[27] 
		- 3. * f * m * gammaU.xy * gammaU.xy * input.ptr[27] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		+ 3. * f * m * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[27] * gammaU.yy * gammaU.xx 
		- f * m * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * input.ptr[4] 
		- 3. * f * m * gammaU.xy * gammaU.xy * input.ptr[4] * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx 
		+ 3. * f * m * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[4] * gammaU.yy * gammaU.xx 
		+ f * m * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[27] * gammaU.xx * gammaU.xx * gammaU.xx 
		+ f * m * gammaU.yy * gammaU.yy * gammaU.yy * input.ptr[4] * gammaU.xx * gammaU.xx * gammaU.xx 
		- input.ptr[0] * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * gammaU.yy 
		+ input.ptr[0] * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * gammaU.yy * f 
		+ input.ptr[0] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.xx 
		+ 3. * input.ptr[0] * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx * gammaU.xx 
		- 3. * input.ptr[0] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.xx * gammaU.xx 
		- input.ptr[0] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * f * gammaU.xx 
		+ 3. * input.ptr[0] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f * gammaU.yy * gammaU.xx * gammaU.xx 
		- 3. * input.ptr[0] * gammaU.xy * gammaU.xy * f * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx * gammaU.xx 
		- input.ptr[30] * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * gammaU.yy 
		+ input.ptr[30] * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * gammaU.yy * f 
		+ input.ptr[30] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * gammaU.xx 
		+ 3. * input.ptr[30] * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx * gammaU.xx 
		- 3. * input.ptr[30] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.xx * gammaU.xx 
		- input.ptr[30] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * f * gammaU.xx 
		- 3. * input.ptr[30] * gammaU.xy * gammaU.xy * f * gammaU.yy * gammaU.yy * gammaU.xx * gammaU.xx * gammaU.xx 
		+ 3. * input.ptr[30] * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f * gammaU.yy * gammaU.xx * gammaU.xx) / (gammaU.xx * (gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 
		- 3. * gammaU.xx * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yy 
		+ 3. * gammaU.xx * gammaU.xx * gammaU.xy * gammaU.xy * gammaU.yy * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.1 * f 
		+ 3. * gammaU.xx * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * f * gammaU.yy 
		- 3. * gammaU.xx * gammaU.xx * gammaU.xy * gammaU.xy * f * gammaU.yy * gammaU.yy 
		- gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * gammaU.yy 
		+ gammaU.xx * gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * gammaU.yy * f));
	K.xy = (2. * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[29] 
		- 2. * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.yz * input.ptr[29] * gammaU.yy 
		+ 2. * sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.yz * input.ptr[6] 
		- 2. * gammaU.xx * sqrt_gUxx * gammaU.xy * gammaU.yz * input.ptr[6] * gammaU.yy 
		- gammaU.xx * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[26] 
		+ gammaU.xx * gammaU.xx * gammaU.xy * input.ptr[26] * gammaU.yy 
		+ gammaU.xx * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[3] 
		- gammaU.xx * gammaU.xx * gammaU.xy * input.ptr[3] * gammaU.yy 
		+ gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * input.ptr[25] 
		- gammaU.xx * gammaU.yy * input.ptr[25] * gammaU.xy * gammaU.xy 
		- gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy * input.ptr[2] 
		+ gammaU.xx * gammaU.yy * input.ptr[2] * gammaU.xy * gammaU.xy 
		+ gammaU.xy * gammaU.xy * gammaU.xy * sqrt(gammaU.xx) * gammaU.zz * input.ptr[28] 
		- gammaU.xy * gammaU.xx * sqrt_gUxx * gammaU.zz * input.ptr[28] * gammaU.yy 
		+ gammaU.xy * gammaU.xy * gammaU.xy * sqrt(gammaU.xx) * gammaU.zz * input.ptr[5] 
		- gammaU.xy * gammaU.xx * sqrt_gUxx * gammaU.zz * input.ptr[5] * gammaU.yy 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[1] 
		- gammaU.xy * gammaU.xz * input.ptr[1] * gammaU.xx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[24] 
		+ gammaU.xy * gammaU.xz * input.ptr[24] * gammaU.xx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[28] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[28] * sqrt(gammaU.xx) * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[5] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * gammaU.xz * gammaU.xz * input.ptr[5] * sqrt(gammaU.xx) * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[27] * sqrt(gammaU.xx) 
		+ gammaU.xy * input.ptr[27] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		- gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[4] * sqrt(gammaU.xx) 
		+ gammaU.xy * input.ptr[4] * gammaU.xx * sqrt_gUxx * gammaU.yy 
		+ gammaU.xz * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[29] 
		+ gammaU.xz * gammaU.xx * sqrt_gUxx * gammaU.yy * gammaU.yy * input.ptr[6] 
		- gammaU.xz * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[29] * 1. / sqrt(gammaU.xx) 
		- gammaU.xz * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[6] * 1. / sqrt(gammaU.xx)) / (
		-sqrt(gammaU.xx) * (gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xx * gammaU.xy * gammaU.xy * gammaU.yy 
		+ gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy));
	K.xz = (
		-(gammaU.xy * input.ptr[29] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xy * input.ptr[6] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * input.ptr[28] * 1. / sqrt(gammaU.xx) 
		+ gammaU.xz * input.ptr[5] * 1. / sqrt(gammaU.xx) 
		- input.ptr[1] 
		+ input.ptr[24])) / sqrt(gammaU.xx);
	K.yy = (sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[25] 
		- gammaU.xx * sqrt_gUxx * gammaU.xy * input.ptr[25] * gammaU.yy 
		- sqrt(gammaU.xx) * gammaU.xy * gammaU.xy * gammaU.xy * input.ptr[2] 
		+ gammaU.xx * sqrt_gUxx * gammaU.xy * input.ptr[2] * gammaU.yy 
		- sqrt(gammaU.xx) * gammaU.xz * input.ptr[1] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * sqrt_gUxx * gammaU.xz * input.ptr[1] * gammaU.yy 
		+ sqrt(gammaU.xx) * gammaU.xz * input.ptr[24] * gammaU.xy * gammaU.xy 
		- gammaU.xx * sqrt_gUxx * gammaU.xz * input.ptr[24] * gammaU.yy 
		- 2. * gammaU.xx * gammaU.yz * input.ptr[29] * gammaU.xy * gammaU.xy 
		+ 2. * gammaU.xx * gammaU.xx * gammaU.yz * input.ptr[29] * gammaU.yy 
		- 2. * gammaU.xx * gammaU.yz * input.ptr[6] * gammaU.xy * gammaU.xy 
		+ 2. * gammaU.xx * gammaU.xx * gammaU.yz * input.ptr[6] * gammaU.yy 
		- gammaU.xx * gammaU.zz * input.ptr[28] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * gammaU.xx * gammaU.zz * input.ptr[28] * gammaU.yy 
		- gammaU.xx * gammaU.zz * input.ptr[5] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * gammaU.xx * gammaU.zz * input.ptr[5] * gammaU.yy 
		+ gammaU.xx * sqrt_gUxx * input.ptr[26] * gammaU.xy * gammaU.xy 
		- gammaU.xx * gammaU.xx * sqrt_gUxx * input.ptr[26] * gammaU.yy 
		+ gammaU.xx * input.ptr[27] * gammaU.xy * gammaU.xy 
		- gammaU.xx * gammaU.xx * input.ptr[27] * gammaU.yy 
		- gammaU.xx * sqrt_gUxx * input.ptr[3] * gammaU.xy * gammaU.xy 
		+ gammaU.xx * gammaU.xx * sqrt_gUxx * input.ptr[3] * gammaU.yy 
		+ gammaU.xx * input.ptr[4] * gammaU.xy * gammaU.xy 
		- gammaU.xx * gammaU.xx * input.ptr[4] * gammaU.yy 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[29] 
		- 2. * gammaU.xy * gammaU.xz * input.ptr[29] * gammaU.xx * gammaU.yy 
		+ 2. * gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xz * input.ptr[6] 
		- 2. * gammaU.xy * gammaU.xz * input.ptr[6] * gammaU.xx * gammaU.yy 
		- gammaU.xz * gammaU.xz * input.ptr[28] * gammaU.xx * gammaU.yy 
		+ gammaU.xz * gammaU.xz * input.ptr[28] * gammaU.xy * gammaU.xy 
		- gammaU.xz * gammaU.xz * input.ptr[5] * gammaU.xx * gammaU.yy 
		+ gammaU.xz * gammaU.xz * input.ptr[5] * gammaU.xy * gammaU.xy) / (
		-(gammaU.xx * gammaU.xx * gammaU.yy * gammaU.yy 
		+ gammaU.xy * gammaU.xy * gammaU.xy * gammaU.xy 
		- 2. * gammaU.xy * gammaU.xy * gammaU.xx * gammaU.yy));
	K.yz = input.ptr[29] 
		+ input.ptr[6];
	K.zz = input.ptr[28] 
		+ input.ptr[5];
	Theta = input.ptr[27] 
		+ input.ptr[4];
	Z.x = (
		-(gammaU.xy * input.ptr[22] 
		+ gammaU.xz * input.ptr[23] 
		- input.ptr[26] * gammaU.xx 
		- input.ptr[3] * gammaU.xx)) / gammaU.xx;
	Z.y = input.ptr[22] 
		+ input.ptr[25] 
		+ input.ptr[2];
	Z.z = input.ptr[1] 
		+ input.ptr[23] 
		+ input.ptr[24];

	<?=eqn.cons_t?> resultU;
	for (int i = 0; i < numStates; ++i) {
		resultU.ptr[i] = 0;
	}
	resultU.a = a;
	resultU.a = a;
	resultU.d = d;
	resultU.K = K;
	resultU.Theta = Theta;
	resultU.Z = Z;
	return resultU;
}

<?=eqn.cons_t?> eigen_fluxTransform_<?=side?>(
	<?=eqn.eigen_t?> eig,
	<?=eqn.cons_t?> input,
	real3 pt 
) {
	<?=eqn.cons_t?> result;
	for (int i = 0; i < numStates; ++i) {
		result.ptr[i] = 0;
	}
	
	result.ptr[0] = f * (gammaU.xx * input.ptr[21] 
		+ 2. * gammaU.xy * input.ptr[22] 
		+ 2. * gammaU.xz * input.ptr[23] 
		+ gammaU.yy * input.ptr[24] 
		+ 2. * gammaU.yz * input.ptr[25] 
		+ gammaU.zz * input.ptr[26] 
		- m * input.ptr[27]);
	result.ptr[1] = 0.;
	result.ptr[2] = 0.;
	result.ptr[3] = input.ptr[21];
	result.ptr[4] = input.ptr[22];
	result.ptr[5] = input.ptr[23];
	result.ptr[6] = input.ptr[24];
	result.ptr[7] = input.ptr[25];
	result.ptr[8] = input.ptr[26];
	result.ptr[9] = 0.;
	result.ptr[10] = 0.;
	result.ptr[11] = 0.;
	result.ptr[12] = 0.;
	result.ptr[13] = 0.;
	result.ptr[14] = 0.;
	result.ptr[15] = 0.;
	result.ptr[16] = 0.;
	result.ptr[17] = 0.;
	result.ptr[18] = 0.;
	result.ptr[19] = 0.;
	result.ptr[20] = 0.;
	result.ptr[21] = 
		-(gammaU.yy * input.ptr[10] 
		- gammaU.yy * input.ptr[6] 
		+ gammaU.yz * input.ptr[11] 
		+ gammaU.yz * input.ptr[16] 
		- 2. * gammaU.yz * input.ptr[7] 
		+ gammaU.zz * input.ptr[17] 
		- gammaU.zz * input.ptr[8] 
		- input.ptr[0] 
		+ 2. * input.ptr[28]);
	result.ptr[22] = (2. * gammaU.xy * input.ptr[10] 
		- 2. * gammaU.xy * input.ptr[6] 
		+ gammaU.xz * input.ptr[11] 
		+ gammaU.xz * input.ptr[16] 
		- 2. * gammaU.xz * input.ptr[7] 
		+ gammaU.yz * input.ptr[13] 
		- gammaU.yz * input.ptr[18] 
		+ gammaU.zz * input.ptr[14] 
		- gammaU.zz * input.ptr[19] 
		+ input.ptr[1] 
		- 2. * input.ptr[29]) / 2.;
	result.ptr[23] = (gammaU.xy * input.ptr[11] 
		+ gammaU.xy * input.ptr[16] 
		- 2. * gammaU.xy * input.ptr[7] 
		+ 2. * gammaU.xz * input.ptr[17] 
		- 2. * gammaU.xz * input.ptr[8] 
		- gammaU.yy * input.ptr[13] 
		+ gammaU.yy * input.ptr[18] 
		- gammaU.yz * input.ptr[14] 
		+ gammaU.yz * input.ptr[19] 
		+ input.ptr[2] 
		- 2. * input.ptr[30]) / 2.;
	result.ptr[24] = 
		-(gammaU.xx * input.ptr[10] 
		- gammaU.xx * input.ptr[6] 
		+ gammaU.xz * input.ptr[13] 
		- gammaU.xz * input.ptr[18]);
	result.ptr[25] = (
		-(gammaU.xx * input.ptr[11] 
		+ gammaU.xx * input.ptr[16] 
		- 2. * gammaU.xx * input.ptr[7] 
		- gammaU.xy * input.ptr[13] 
		+ gammaU.xy * input.ptr[18] 
		+ gammaU.xz * input.ptr[14] 
		- gammaU.xz * input.ptr[19])) / 2.;
	result.ptr[26] = 
		-(gammaU.xx * input.ptr[17] 
		- gammaU.xx * input.ptr[8] 
		- gammaU.xy * input.ptr[14] 
		+ gammaU.xy * input.ptr[19]);
	result.ptr[27] = 
		-(gammaU.xx * gammaU.yy * input.ptr[10] 
		- gammaU.xx * gammaU.yy * input.ptr[6] 
		+ gammaU.xx * gammaU.yz * input.ptr[11] 
		+ gammaU.xx * gammaU.yz * input.ptr[16] 
		- 2. * gammaU.xx * gammaU.yz * input.ptr[7] 
		+ gammaU.xx * gammaU.zz * input.ptr[17] 
		- gammaU.xx * gammaU.zz * input.ptr[8] 
		+ gammaU.xx * input.ptr[28] 
		- gammaU.xy * gammaU.xz * input.ptr[11] 
		- gammaU.xy * gammaU.xz * input.ptr[16] 
		+ 2. * gammaU.xy * gammaU.xz * input.ptr[7] 
		- gammaU.xy * gammaU.yz * input.ptr[13] 
		+ gammaU.xy * gammaU.yz * input.ptr[18] 
		- gammaU.xy * gammaU.zz * input.ptr[14] 
		+ gammaU.xy * gammaU.zz * input.ptr[19] 
		- gammaU.xy * gammaU.xy * input.ptr[10] 
		+ gammaU.xy * input.ptr[29] 
		+ gammaU.xy * gammaU.xy * input.ptr[6] 
		+ gammaU.xz * gammaU.yy * input.ptr[13] 
		- gammaU.xz * gammaU.yy * input.ptr[18] 
		+ gammaU.xz * gammaU.yz * input.ptr[14] 
		- gammaU.xz * gammaU.yz * input.ptr[19] 
		- gammaU.xz * gammaU.xz * input.ptr[17] 
		+ gammaU.xz * input.ptr[30] 
		+ gammaU.xz * gammaU.xz * input.ptr[8]);
	result.ptr[28] = gammaU.xy * input.ptr[22] 
		+ gammaU.xz * input.ptr[23] 
		+ gammaU.yy * input.ptr[24] 
		+ 2. * gammaU.yz * input.ptr[25] 
		+ gammaU.zz * input.ptr[26] 
		- input.ptr[27];
	result.ptr[29] = 
		-(gammaU.xx * input.ptr[22] 
		+ gammaU.xy * input.ptr[24] 
		+ gammaU.xz * input.ptr[25]);
	result.ptr[30] = 
		-(gammaU.xx * input.ptr[23] 
		+ gammaU.xy * input.ptr[25] 
		+ gammaU.xz * input.ptr[26]);

	return result;
}
<? end ?>

kernel void addSource(
	global <?=eqn.cons_t?>* derivBuf,
	const global <?=eqn.cons_t?>* UBuf)
{
#if 0
	SETBOUNDS_NOGHOST();
	const global <?=eqn.cons_t?>* U = UBuf + index;
	global <?=eqn.cons_t?>* deriv = derivBuf + index;

	const real xi = 1.;	//which is which parameter?  I alwasy forget .. m .. lambda ... xi ... always changing names

	real det_gamma = sym3_det(U->gamma);
	sym3 gammaU = sym3_inv(U->gamma, det_gamma);
	real f = calc_f(U->alpha);	//could be based on alpha...

	//K^i_j = gamma^ik K_kj
	real3x3 K_ul = (real3x3){
<? 
for i,xi in ipairs(xNames) do
?>		.<?=xi?> = (real3){
<? 	for j,xj in ipairs(xNames) do
?>			.<?=xj?> = 0.<?
		for k,xk in ipairs(xNames) do
		?> + gammaU.<?=sym(i,k)?> * U->K.<?=sym(k,j)?><? 
		end ?>,
<? 	end
?>		},
<? 
end
?>	};

	real tr_K = mat3_trace(K_ul);

	//TODO correct source terms
	//I'm taking this from the 2008 Yano et al "Flux-Vector Splitting..."
	//which itself references (for the source terms) the 2005 Bona et al "Geometrically Motivated ..." 
	//but notice, 2005 Bona paper shows the flux as densitized, so the eigenvalues without any gamma influence

	//alpha,t + ... = alpha beta^k a_k - alpha^2 f (K - 2 Theta)
	deriv->alpha += -U->alpha * U->alpha * f * (tr_K - 2. * U->Theta);

	//a_i,t + ... = b_i^k a_k - b_k^k a_i

	//beta^i_,t + ... = beta^k b_k^i - alpha Q^i
	//Q^i = alpha (a^i - d^i + 2 V^i)
	//V^i = d^i - e^i - Z^i
	
	//gamma_ij,t + ... = 2 beta^k d_kij + b_ji + b_ij - 2 alpha K_ij
	deriv->gamma = sym3_add(deriv->gamma, sym3_scale(U->K, -2. * U->alpha));

	//d_kij,t + ... = b_k^l d_lij - b_l^l d_kij

	//conn_ijk = .5 * (g_ij,k + g_ik,j - g_jk,i) 
	//= d_kij + d_jik - d_ijk
	_3sym3 conn_lll = {
<? 
for i,xi in ipairs(xNames) do
?>		.<?=xi?> = (sym3){
<? 	for jk,xjk in ipairs(symNames) do 
		local j,k = from6to3x3(jk)
		local xj,xk = xNames[j],xNames[k]
?>			.<?=xjk?> = U->d.<?=xk?>.<?=sym(i,j)?> + U->d.<?=xj?>.<?=sym(i,k)?> - U->d.<?=xi?>.<?=sym(j,k)?>,
<? 	end 
?>		},
<? 
end
?>	};

	_3sym3 conn_ull = sym3_3sym3_mul(gammaU, conn_lll);
	_3sym3 d_ull = sym3_3sym3_mul(gammaU, U->d);

	//conn^ij_k = gamma^jl conn^i_lk
	_3sym3 conn_uul = {
<? 
	for i,xi in ipairs(xNames) do
?>
		.<?=xi?> = {
<? 
		for jk,xjk in ipairs(symNames) do
			local j,k = from6to3x3(jk)
?>			.<?=xjk?> = 0. <?
			for l,xl in ipairs(xNames) do
				?> + gammaU.<?=sym(l,j)?> * conn_ull.<?=xi?>.<?=sym(l,k)?><?
			end	?>,
<? end		
?>		},
<? 
	end
?>	};

	//d_ijk conn^ij_l gamma^kl
	real d_dot_conn = 0.<?
for i,xi in ipairs(xNames) do
	for j,xj in ipairs(xNames) do
		for k,xk in ipairs(xNames) do
			for l,xl in ipairs(xNames) do
?> + U->d.<?=xi?>.<?=sym(j,k)?> * conn_uul.<?=xi?>.<?=sym(j,k)?> * gammaU.<?=sym(k,l)?><?
			end
		end
	end
end
?>;

	//d_i = d_ik^k
	real3 d = (real3){
<? for i,xi in ipairs(xNames) do
?>		.<?=xi?> = sym3_dot(U->d.<?=xi?>, gammaU),
<? end
?>	};
	
	//e_i = d^k_ki
	real3 e = (real3){
<? for i,xi in ipairs(xNames) do
?>		.<?=xi?> = 0. <?
	for j,xj in ipairs(xNames) do
?> + d_ull.<?=xj?>.<?=sym(j,i)?><?
	end
?>,
<? end
?>	};

	real3 d_u = sym3_real3_mul(gammaU, d);
	real3 e_u = sym3_real3_mul(gammaU, e);
	real3 a_u = sym3_real3_mul(gammaU, U->a);
	real3 Z_u = sym3_real3_mul(gammaU, U->Z);

	//connSq_ij = conn^k_li conn^l_kj
	real connSq_ll[3][3] = {
<? for i,xi in ipairs(xNames) do 
?>		{
<?	for j,xj in ipairs(xNames) do
?>
			0. <?
		for k,xk in ipairs(xNames) do
			for l,xl in ipairs(xNames) do
				?> + conn_ull.<?=xk?>.<?=sym(l,i)?> * conn_ull.<?=xl?>.<?=sym(k,j)?><?
			end
		end
	?>,
<? end 
?>		},
<? end
?>	};

	//K_ik K^k_j
	sym3 KSq_ll = sym3_mat3_to_sym3_mul(U->K, K_ul);

	real tr_KSq = sym3_dot(KSq_ll, gammaU);

	//dsq_ij = d_ikl gamma^lm d^k_mj
	real3x3 dsq = {
<? 
for i,xi in ipairs(xNames) do
?>
		.<?=xi?> = {
<?	for j,xj in ipairs(xNames) do
?>			.<?=xj?> = 
				0.<?
		for k,xk in ipairs(xNames) do
			for l,xl in ipairs(xNames) do
				for m,xm in ipairs(xNames) do
					?> + U->d.<?=xi?>.<?=sym(j,l)?> * gammaU.<?=sym(l,m)?> * d_ull.<?=xk?>.<?=sym(m,j)?>
<?
				end
			end
		end	
?>			,
<? 	end
?>		},
<? 
end
?>	};

	/*
	K_ij,t + ... = -K_ij b_k^k + K_ik b_j^k + K_jk b_i^k 
		+ alpha ( 1/2 (1 + xi) ( - a_k Gamma^k_ij + 1/2 (a_i d_j + a_j d_i))
			+ 1/2 (1 - xi) (a_k d^k_ij - 1/2 (a_j (2 e_i - d_i) + a_i (2 e_j - d_j))
				+ 2 (d_ir^m d^r_mj + d_jr^m d^r_mi) - 2 e_k (d_ij^k + d_ji^k)
			)
			+ (d_k + a_k - 2 Z_k) Gamma^k_ij - Gamma^k_mj Gamma^m_ki - (a_i Z_j + a_j Z_i)
			- 2 K^k_i K_kj + (K - 2 Theta) K_ij
		) - 8 pi alpha (S_ij - 1/2 (S - tau) gamma_ij)
	*/
<? for ij,xij in ipairs(symNames) do 
	local i,j = from6to3x3(ij)
	local xi,xj = xNames[i], xNames[j]
?>
	deriv->K.<?=xij?> += 
		//TODO shift terms
	U->alpha * (
		.5 * (1. + xi) * (
		<? for k,xk in ipairs(xNames) do ?> 
			-U->a.<?=xk?> * conn_ull.<?=xk?>.<?=xij?>
		<? end ?>
			+ .5 * (U->a.<?=xi?> * d.<?=xj?> + U->a.<?=xj?> * d.<?=xi?>)
		)
		+ .5 * (1. - xi) * (0.
		<? for k,xk in ipairs(xNames) do ?> 
			+ a_u.<?=xk?> * U->d.<?=xk?>.<?=xij?>
		<? end ?>
			- .5 * ( 
				U->a.<?=xj?> * (2. * e.<?=xi?> - d.<?=xi?>) 
				+ U->a.<?=xi?> * (2. * e.<?=xj?> - d.<?=xj?>)
			)
			+ 2. * (dsq.v[<?=i-1?>].s[<?=j-1?>] + dsq.v[<?=j-1?>].s[<?=i-1?>])
		<? for k,xk in ipairs(xNames) do ?> 
			- 2. * e_u.<?=xk?> * (U->d.<?=xi?>.<?=sym(j,k)?> + U->d.<?=xj?>.<?=sym(i,k)?>)
		<? end ?>
		)
		<? for k,xk in ipairs(xNames) do ?> 
		+ (d.<?=xk?> + U->a.<?=xk?> - 2. * U->Z.<?=xk?>) * conn_ull.<?=xk?>.<?=xij?>
		<? end ?>
		- connSq_ll[<?=j-1?>][<?=i-1?>]
		- U->a.<?=xi?> * U->Z.<?=xj?>
		- U->a.<?=xj?> * U->Z.<?=xi?>
		- 2. * KSq_ll.<?=xij?>
		+ U->K.<?=xij?> * (tr_K - 2. * U->Theta)
	)
		// TODO source terms
	;
<? end
?>
		
	/*
	Theta,t + ... = 
		-Theta b_k^k 
		+ 1/2 alpha (
			2 a_k (d^k - e^k - 2 Z^k) 
			+ d_krs Gamma^krs 
			- d^k (d_k - 2 Z_k)
			- K^k_r K^r_k 
			+ K (K - 2 Theta)
		)
		- 8 pi alpha tau
	
	d_ijk conn^ijk
	= d_ijk (d^kij + d^jik - d^ijk)
	*/
	deriv->Theta += .5 * U->alpha * (0. 
		<? for k,xk in ipairs(xNames) do ?> 
		+ 2. * U->a.<?=xk?> * (d_u.<?=xk?> - e_u.<?=xk?> - 2. * Z_u.<?=xk?>)
		- d_u.<?=xk?> * (d.<?=xk?> - 2. * U->Z.<?=xk?>)
		<? end ?>	
		+ d_dot_conn
		- tr_KSq
		+ tr_K * (tr_K - 2. * U->Theta)
	);

	// K^k_j Gamma^j_ki
	real3 K_times_conn = (real3){
<? 
for i,xi in ipairs(xNames) do
?>		.<?=xi?> = 0.<?
	for j,xj in ipairs(xNames) do
		for k,xk in ipairs(xNames) do
?> + K_ul.v[<?=k-1?>].s[<?=j-1?>] * conn_ull.<?=xj?>.<?=sym(k,i)?><?
		end
	end	?>,
<? 
end
?>	};

	/*
	Z_i,t + ... = 
		-Z_i b_k^k 
		+ Z_k b_i^k 
		- 8 pi alpha S_i
		+ alpha (
			a_i (K - 2 Theta) 
			- a_k K^k_i 
			- K^k_r Gamma^r_ki 
			+ K^k_i (d_k - 2 Z_k)
		)
	*/
	<? for i,xi in ipairs(xNames) do ?> 
	deriv->Z.<?=xi?> += U->alpha * (
		U->a.<?=xi?> * (tr_K - 2. * U->Theta)
		<? for k,xk in ipairs(xNames) do ?> 
		- a_u.<?=xk?> * U->K.<?=sym(i,k)?>
		+ U->K.<?=sym(i,k)?> * (d_u.<?=xk?> - 2. * Z_u.<?=xk?>)
		<? end ?>
		- K_times_conn.<?=xi?>
	);
	<? end ?>

#endif

}
