//needs Eqn.hasFluxFromCons=true
<? for side=0,solver.dim-1 do ?>
<?=eqn.cons_t?> fluxFromCons_<?=side?>(<?=eqn.cons_t?> U) {
	<?=eqn.prim_t?> W = primFromCons(U);
	real vj = W.v.s<?=side?>;
	real HTotal = U.ETotal + W.P;
	
	<?=eqn.cons_t?> F;
	F.rho = U.m.s<?=side?>;
	F.m = real3_scale(U.m, vj);
	F.m.s<?=side?> += W.P;
	F.ETotal = HTotal * vj;
	F.ePot = 0;
	return F;
}
<? end ?>

<? for side=0,solver.dim-1 do ?>
range_t calcCellMinMaxEigenvalues_<?=side?>(
	const global <?=eqn.cons_t?>* U
) {
	<?=eqn.prim_t?> W = primFromCons(*U);
	real Cs = calc_Cs(&W);
	return (range_t){.min=W.v.s<?=side?> - Cs, .max=W.v.s<?=side?> + Cs};	
}
<? end ?>

//used for interface eigen basis
void eigen_forSide(
	global <?=eqn.eigen_t?>* eig,
	global const <?=eqn.cons_t?>* UL,
	global const <?=eqn.cons_t?>* UR
) {
	<?=eqn.prim_t?> WL = primFromCons(*UL);
	real sqrtRhoL = sqrt(WL.rho);
	real3 vL = WL.v;
	real hTotalL = calc_hTotal(WL.rho, WL.P, UL->ETotal);
	
	<?=eqn.prim_t?> WR = primFromCons(*UR);
	real sqrtRhoR = sqrt(UR->rho);
	real3 vR = WR.v;
	real hTotalR = calc_hTotal(WR.rho, WR.P, UR->ETotal);
	
	real invDenom = 1./(sqrtRhoL + sqrtRhoR);
	
	//Roe-averaged
	real rho = sqrtRhoL * sqrtRhoR;
	real3 v = real3_add(
			real3_scale(vL, sqrtRhoL * invDenom),
			real3_scale(vR, sqrtRhoR * invDenom));
	real hTotal = invDenom * (sqrtRhoL * hTotalL + sqrtRhoR * hTotalR);
	
	//derived:
	real vSq = coordLenSq(v);
	real eKin = .5 * vSq;
	real CsSq = (heatCapacityRatio - 1.) * (hTotal - eKin);
	real Cs = sqrt(CsSq);
	
	eig->rho = rho; 
	eig->v = v;
	eig->hTotal = hTotal;
	eig->vSq = vSq;
	eig->Cs = Cs;
}

//this is also used by PLM for cell-centered waves
//that's why it is split out
//its use there could replace calcCellMinMaxEigenvalues
//which is called by the default calcDT
<?
for _,addr0 in ipairs{'', 'global'} do
	for _,addr1 in ipairs{'', 'global'} do
		for side=0,solver.dim-1 do
?>
void eigen_calcWaves_<?=side?>_<?=addr0?>_<?=addr1?>(
	<?=addr0?> real* wave,
	<?=addr1?> const <?=eqn.eigen_t?>* eig
) {
	real v_n = eig->v.s[<?=side?>];
	wave[0] = v_n - eig->Cs;
	wave[1] = v_n;
	wave[2] = v_n;
	wave[3] = v_n;
	wave[4] = v_n + eig->Cs;
}
<?		end
	end
end
?>

kernel void calcEigenBasis(
	global real* waveBuf,			//[volume][dim][numWaves]
	global <?=eqn.eigen_t?>* eigenBuf,		//[volume][dim]
	<?= solver.getULRArg ?>
) {
	SETBOUNDS(2,1);
	int indexR = index;
	
	<? for side=0,solver.dim-1 do ?>{
		const int side = <?=side?>;
		
		int indexL = index - stepsize[side];
	
		<?= solver.getULRCode ?>
		
		int intindex = side + dim * index;	

		global <?=eqn.eigen_t?>* eig = eigenBuf + intindex;
		eigen_forSide(eig, UL, UR);
		
		global real* wave = waveBuf + numWaves * intindex;
		eigen_calcWaves_<?=side?>_global_global(wave, eig);
	}<? end ?>
}

<?
for _,addr0 in ipairs{'', 'global'} do
	for _,addr1 in ipairs{'', 'global'} do
		for _,addr2 in ipairs{'', 'global'} do
			for side=0,solver.dim-1 do 
				local prefix
				if side == 0 then
					prefix = [[
	const real nx = 1, ny = 0, nz = 0;
	const real n1x = 0, n1y = 1, n1z = 0;
	const real n2x = 0, n2y = 0, n2z = 1;
	real v_n = v.x, v_n1 = v.y, v_n2 = v.z;
]] 
				elseif side == 1 then
					prefix = [[
	const real nx = 0, ny = 1, nz = 0;
	const real n1x = 0, n1y = 0, n1z = 1;
	const real n2x = 1, n2y = 0, n2z = 0;
	real v_n = v.y, v_n1 = v.z, v_n2 = v.x;
]] 
				elseif side == 2 then
					prefix = [[
	const real nx = 0, ny = 0, nz = 1;
	const real n1x = 1, n1y = 0, n1z = 0;
	const real n2x = 0, n2y = 1, n2z = 0;
	real v_n = v.z, v_n1 = v.x, v_n2 = v.y;
]]
				end
				prefix = [[
	real3 v = eig->v;
	real hTotal = eig->hTotal;
	real vSq = eig->vSq;
	real Cs = eig->Cs;
]] .. prefix
?>

void eigen_leftTransform_<?=side?>_<?=addr0?>_<?=addr1?>_<?=addr2?>(
	<?=addr0?> real* y,
	<?=addr1?> const <?=eqn.eigen_t?>* eig,
	<?=addr2?> const real* x
) { 
	<?=prefix?>

	real invDenom = .5 / (Cs * Cs);
	y[0] = (x[0] * ((heatCapacityRatio - 1.) * .5 * vSq + Cs * v_n)
		+ x[1] * -(nx * Cs + (heatCapacityRatio - 1.) * v.x) 
		+ x[2] * -(ny * Cs + (heatCapacityRatio - 1.) * v.y)
		+ x[3] * -(nz * Cs + (heatCapacityRatio - 1.) * v.z)
		+ x[4] * (heatCapacityRatio - 1.)
	) * invDenom;
	y[1] = (x[0] * (2.*Cs*Cs - (heatCapacityRatio - 1.) * vSq)
		+ x[1] * (heatCapacityRatio - 1.) * v.x * 2
		+ x[2] * (heatCapacityRatio - 1.) * v.y * 2
		+ x[3] * (heatCapacityRatio - 1.) * v.z * 2
		+ x[4] * -(heatCapacityRatio - 1.) * 2
	) * invDenom;
	y[2] = x[0] * -v_n1 + x[1] * n1x + x[2] * n1y + x[3] * n1z;
	y[3] = x[0] * -v_n2 + x[1] * n2x + x[2] * n2y + x[3] * n2z;
	y[4] = (x[0] * ((heatCapacityRatio - 1.) * .5 * vSq - Cs * v_n) 
		+ x[1] * (nx * Cs - (heatCapacityRatio - 1.) * v.x) 
		+ x[2] * (ny * Cs - (heatCapacityRatio - 1.) * v.y) 
		+ x[3] * (nz * Cs - (heatCapacityRatio - 1.) * v.z) 
		+ x[4] * (heatCapacityRatio - 1.)
	) * invDenom;
}

void eigen_rightTransform_<?=side?>_<?=addr0?>_<?=addr1?>_<?=addr2?>(
	<?=addr0?> real* y,
	<?=addr1?> const <?=eqn.eigen_t?>* eig,
	<?=addr2?> const real* x
) {
	<?=prefix?>

	y[0] = x[0] + x[1] + x[4];
	y[1] = x[0] * (v.x - nx * Cs) + x[1] * v.x + x[2] * n1x + x[3] * n2x + x[4] * (v.x + nx * Cs);
	y[2] = x[0] * (v.y - ny * Cs) + x[1] * v.y + x[2] * n1y + x[3] * n2y + x[4] * (v.y + ny * Cs);
	y[3] = x[0] * (v.z - nz * Cs) + x[1] * v.z + x[2] * n1z + x[3] * n2z + x[4] * (v.z + nz * Cs);
	y[4] = x[0] * (hTotal - v_n * Cs) + x[1] * .5 * vSq + x[2] * v_n1 + x[3] * v_n2 + x[4] * (hTotal + v_n * Cs);
}

<?	if solver.checkFluxError then ?>
void eigen_fluxTransform_<?=side?>_<?=addr0?>_<?=addr1?>_<?=addr2?>(
	<?=addr0?> real* y,
	<?=addr1?> const <?=eqn.eigen_t?>* eig,
	<?=addr2?> const real* x
) {
	<?=prefix?>
	
	y[0] = x[1] * nx + x[2] * ny + x[3] * nz;
	y[1] = x[0] * (-v_n * v.x + (heatCapacityRatio - 1.) * .5 * vSq * nx)
		+ x[1] * (v.x * nx - (heatCapacityRatio - 1.) * nx * v.x + v_n)
		+ x[2] * (v.x * ny - (heatCapacityRatio - 1.) * nx * v.y)
		+ x[3] * (v.x * nz - (heatCapacityRatio - 1.) * nx * v.z)
		+ x[4] * (heatCapacityRatio - 1.) * nx;
	y[2] = x[0] * (-v_n * v.y + (heatCapacityRatio - 1.) * .5 * vSq * ny)
		+ x[1] * (v.y * nx - (heatCapacityRatio - 1.) * ny * v.x)
		+ x[2] * (v.y * ny - (heatCapacityRatio - 1.) * ny * v.y + v_n)
		+ x[3] * (v.y * nz - (heatCapacityRatio - 1.) * ny * v.z)
		+ x[4] * (heatCapacityRatio - 1.) * ny;
	y[3] = x[0] * (-v_n * v.z + (heatCapacityRatio - 1.) * .5 * vSq * nz)
		+ x[1] * (v.z * nx - (heatCapacityRatio - 1.) * nz * v.x)
		+ x[2] * (v.z * ny - (heatCapacityRatio - 1.) * nz * v.y)
		+ x[3] * (v.z * nz - (heatCapacityRatio - 1.) * nz * v.z + v_n)
		+ x[4] * (heatCapacityRatio - 1.) * nz;
	y[4] = x[0] * v_n * ((heatCapacityRatio - 1.) * .5 * vSq - hTotal)
		+ x[1] * (-(heatCapacityRatio - 1.) * v_n * v.x + nx * hTotal)
		+ x[2] * (-(heatCapacityRatio - 1.) * v_n * v.y + ny * hTotal)
		+ x[3] * (-(heatCapacityRatio - 1.) * v_n * v.z + nz * hTotal)
		+ x[4] * heatCapacityRatio * v_n;
}
<?
				end
			end
		end
	end
end
?>


// used by PLM


<? for side=0,solver.dim-1 do ?>
<?=eqn.cons_t?> fluxForCons_<?=side?>(<?=eqn.cons_t?> U) {
	<?=eqn.prim_t?> W = primFromCons(U);
	real mi = U.m.s<?=side?>;
	return (<?=eqn.cons_t?>){
		.rho = mi,
		.m = (real3){
			.x = mi * W.v.x<?= side==0 and ' + W.P' or ''?>,
			.y = mi * W.v.y<?= side==1 and ' + W.P' or ''?>,
			.z = mi * W.v.z<?= side==2 and ' + W.P' or ''?>,
		},
		.ETotal = (U.ETotal + W.P) * W.v.s<?=side?>,
		.ePot = 0.,
	};
}
<? end ?>

<? for side=0,solver.dim-1 do ?>
void eigen_forCell_<?=side?>(
	<?=eqn.eigen_t?>* eig,
	global const <?=eqn.cons_t?>* U
) {
	<?=eqn.prim_t?> W = primFromCons(*U);
	real vSq = coordLenSq(W.v);
	real eKin = .5 * vSq;
	real hTotal = calc_hTotal(W.rho, W.P, U->ETotal);
	real CsSq = (heatCapacityRatio - 1.) * (hTotal - eKin);
	real Cs = sqrt(CsSq);
	eig->rho = W.rho;
	eig->v = W.v;
	eig->hTotal = hTotal;
	eig->vSq = vSq;
	eig->Cs = Cs;
}
<? end ?>

void apply_dU_dW(<?=eqn.cons_t?>* y, const <?=eqn.prim_t?>* W, const <?=eqn.prim_t?>* x) {
	*y = (<?=eqn.cons_t?>){
		.rho = x->rho,
		.m = real3_add(real3_scale(W->v, x->rho), real3_scale(x->v, W->rho)),
		.ETotal = x->rho * .5 * coordLenSq(W->v) + W->rho * real3_dot(x->v, W->v) + x->P / (heatCapacityRatio - 1.) + x->ePot,
	};
}

void apply_dW_dU(<?=eqn.prim_t?>* y, const <?=eqn.prim_t?>* W, const <?=eqn.cons_t?>* x) {
	*y = (<?=eqn.prim_t?>){
		.rho = x->rho,
		.v = real3_sub(real3_scale(x->m, 1./W->rho), real3_scale(W->v, x->rho / W->rho)),
		.P = (heatCapacityRatio - 1.) * (x->ETotal + .5 * coordLenSq(W->v) * x->rho - real3_dot(x->m, W->v) - x->ePot),
	};
}
