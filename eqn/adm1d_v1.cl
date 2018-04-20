<? for side=0,solver.dim-1 do ?>
range_t calcCellMinMaxEigenvalues_<?=side?>(
	const global <?=eqn.cons_t?>* U,
	real3 x
) {
	real f = calc_f(U->alpha);
	real lambda = U->alpha * sqrt(f / U->gamma_xx);
	return (range_t){.min=-lambda, .max=lambda};
}
<? end ?>

<? for side=0,solver.dim-1 do ?>
<?=eqn.eigen_t?> eigen_forSide_<?=side?>(
	const global <?=eqn.cons_t?>* UL,
	const global <?=eqn.cons_t?>* UR,
	real3 x
) {
	real alpha = .5 * (UL->alpha + UR->alpha);
	return (<?=eqn.eigen_t?>){
		.alpha = alpha,
		.gamma_xx = .5 * (UL->gamma_xx + UR->gamma_xx),
		.f = calc_f(alpha),
	};
}
<? end ?>

kernel void calcEigenBasis(
	global <?=eqn.eigen_t?>* eigenBuf,
	<?= solver.getULRArg ?>
) {
	SETBOUNDS(numGhost,numGhost-1);
	real3 x = cell_x(i);
	int indexR = index;
	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;
		int indexL = index - stepsize.s<?=side?>;
	
		<?= solver.getULRCode ?>
		
		int indexInt = side + dim * index;
		global <?=eqn.eigen_t?>* eig = eigenBuf + indexInt;
		*eig = eigen_forSide_<?=side?>(UL, UR, x);
	}<? end ?>
}

<? for side=0,solver.dim-1 do ?>
<?=eqn.waves_t?> eigen_leftTransform_<?=side?>(
	<?=eqn.eigen_t?> eig,
	<?=eqn.cons_t?> x,
	real3 pt
) {
	real sqrt_f = sqrt(eig.f);
	return (<?=eqn.waves_t?>){.ptr={
		(x.ptr[2] / eig.f - x.ptr[4] / sqrt_f) / 2.,
		-2. * x.ptr[2] / eig.f + x.ptr[3],
		(x.ptr[2] / eig.f + x.ptr[4] / sqrt_f) / 2.,
	}};
}

<?=eqn.cons_t?> eigen_rightTransform_<?=side?>(
	<?=eqn.eigen_t?> eig,
	<?=eqn.waves_t?> x,
	real3 pt 
) {
	return (<?=eqn.cons_t?>){.ptr={
		0,
		0,
		(x.ptr[0] + x.ptr[2]) * eig.f,
		2. * (x.ptr[0] + x.ptr[2]) + x.ptr[1],
		sqrt(eig.f) * (x.ptr[2] - x.ptr[0]),
	}};
}

<?=eqn.cons_t?> eigen_fluxTransform_<?=side?>(
	<?=eqn.eigen_t?> eig,
	<?=eqn.cons_t?> x,
	real3 pt 
) {
	real alpha_over_sqrt_gamma_xx = eig.alpha / sqrt(eig.gamma_xx);
	return (<?=eqn.cons_t?>){.ptr={
		0,
		0,
		x.ptr[4] * eig.f * alpha_over_sqrt_gamma_xx,
		x.ptr[4] * 2. * alpha_over_sqrt_gamma_xx,
		x.ptr[2] * alpha_over_sqrt_gamma_xx,
	}};
}
<? end ?>

kernel void addSource(
	global <?=eqn.cons_t?>* derivBuf,
	const global <?=eqn.cons_t?>* UBuf
) {
	SETBOUNDS_NOGHOST();
	global <?=eqn.cons_t?>* deriv = derivBuf + index;
	const global <?=eqn.cons_t?>* U = UBuf + index;
	
	real alpha = U->alpha;
	real gamma_xx = U->gamma_xx;
	real a_x = U->a_x;
	real D_g = U->D_g;
	real KTilde = U->KTilde;
	
	real sqrt_gamma_xx = sqrt(gamma_xx);
	real K_xx = KTilde / sqrt_gamma_xx;
	real K = KTilde / sqrt_gamma_xx;

	real f = calc_f(alpha);
	real dalpha_f = calc_dalpha_f(alpha);
	
	deriv->alpha -= alpha * alpha * f * K;
	deriv->gamma_xx -= 2. * alpha * gamma_xx * K;
	deriv->a_x -= ((.5 * D_g - a_x) * f - alpha * dalpha_f * a_x) * alpha * K;
	deriv->D_g -= (.5 * D_g - a_x) * 2 * alpha * K;
	deriv->KTilde -= (.5 * D_g - a_x) * a_x * alpha / sqrt_gamma_xx;

	// and now for the first-order constraints
	
<? if eqn.guiVars.a_x_convCoeff.value ~= 0 then ?>
	// a_x = alpha,x / alpha <=> a_x += eta (alpha,x / alpha - a_x)
	real dx_alpha = (U[1].alpha - U[-1].alpha) / (2. * grid_dx0);
	deriv->a_x += a_x_convCoeff * (dx_alpha / alpha - a_x);
<? end -- eqn.guiVars.a_x_convCoeff.value  ?>
	
<? if eqn.guiVars.D_g_convCoeff.value ~= 0 then ?>
	// D_g = gamma_xx,x / gamma_xx <=> D_g += eta (gamma_xx,x / gamma_xx - D_g)
	real dx_gamma_xx = (U[1].gamma_xx - U[-1].gamma_xx) / (2. * grid_dx0);
	deriv->D_g += D_g_convCoeff * (dx_gamma_xx / gamma_xx - D_g);
<? end -- eqn.guiVars.D_g_convCoeff.value  ?>

	//Kreiss-Oligar diffusion, for stability's sake?
}


//used by PLM


<? for side=0,solver.dim-1 do ?>
<?=eqn.eigen_t?> eigen_forCell_<?=side?>(
	<?=eqn.cons_t?> U,
	real3 x
) {
	return (<?=eqn.eigen_t?>){
		.alpha = U.alpha,
		.gamma_xx = U.gamma_xx,
		.f = calc_f(U.alpha),
	};
}
<? end ?>
