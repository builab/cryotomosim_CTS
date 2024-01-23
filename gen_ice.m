function [iced, ice] = gen_ice(vol,pix)
%is amorphous ice .94g/cm3? or is it lower density?
denspix = (.90/18)*6e23*(pix/1e8)^3; %d = (d/mass)*mol*(pixel/m-a conv)^3 average atom/pix for ice ~.94g/cm3
%computed density might be a bit high, vitreous may be lower than .94g/cm3.
%without solvation exclusion, borders do get very hazy - good for rad damage
%~.03 water per A^3, or 33A^3 per H20, a bit more than a 3x3A cube

%ice too thick/noisy at very high resolution?

atomfrac = exp(-pix/6); %fraction as points rather than flat background
%does compressing it into fewer points of higher density work without screwing the noise?
densfrac = 10/(20+pix*2)*1+0; %scalar to distribute extra intensity to particles to reduce number required
w = 8+2;
mol = round(denspix*numel(vol)*atomfrac*densfrac); % atomfrac% of ice mass randomly distributed as molecules
ice = round(vol*0+denspix*(1-atomfrac)*w); % 1-atomfrac% of ice mass as flat background for speed
w = w/densfrac; %scaled intensity for water psuedo-molecules (atomic number until i find e- opacties)

pts = rand(3,mol).*size(vol)'; ix = round(pts+0.5); %fast pregeneration of all points
for i=1:mol
    co = ix(:,i); x = co(1); y = co(2); z = co(3); %slightly faster column indexing
    ice(x,y,z) = ice(x,y,z)+w*1;
end

% how to make solvation layer?
% take min of smoothed vol+ice for a halo?

%{
%alternate maybe easier binarization method
solv = imbinarize(rescale(vol)); 
map = imgaussfilt3(single(~solv),3);%,'FilterSize',3);
%for camk at 6A, ~2 sig, 3 too high and 1 too little SNR. probably need more radiation effect
%for actin at 13A, ~2 sig, 1 SNR is crap - =<2 needs more noise (maybe also more rad damage via noise)
%just do a scaling binarization, maybe with dilation at high mag?
%map = rescale(imcomplement(solv)); %rescaling nonviable, beads bork scaling hard
ice = ice.*map;
iced = vol+ice;
%}
%orig straight up floor by ice globally
%iced = max(ice,vol); %for some reason the ice is much too dense with test TMD placement output

%new ice
bb = imgaussfilt3(vol,1);
%ice=ice*0.4;
icesc = max(ice*0.6-(bb),ice*0.5);
%iced = max(ice-sqrt(vol)-0*max(sqrt(vol)/4-pix*0,ice*0.8),vol);
iced = max(vol,icesc);
end