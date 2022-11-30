function [iced, ice] = gen_ice(vol,pix)
%is amorphous ice .94g/cm3? or is it lower density?
denspix = (.94/18)*6e23*(pix/1e8)^3; %d = (d/mass)*mol*(pixel/m-a conv)^3 average atom/pix for ice ~.94g/cm3
%computed density might be a bit high, vitreous may be lower than .94g/cm3.
%without solvation exclusion, borders do get very hazy - good for rad damage

atomfrac = exp(-pix/3); %fraction as points rather than flat background
%does compressing it into fewer points of higher density work without screwing the noise?
%mol = round(denspix*numel(vol)*atomfrac); 

densfrac = 20/(20+pix)*1;
w = (8+2)/densfrac; %scaled intensity for water psuedo-molecules (atomic number until i find e- opacties)
mol = round(denspix*numel(vol)*atomfrac*densfrac); % atomfrac% of ice mass randomly distributed as molecules
ice = round(vol*0+denspix*(1-atomfrac)*w); % 1-atomfrac% of ice mass as flat background for speed

pts = rand(3,mol).*size(vol)'; ix = round(pts+0.5); %fast pregeneration of all points
for i=1:mol
    co = ix(:,i); x = co(1); y = co(2); z = co(3); %slightly faster column indexing
    ice(x,y,z) = ice(x,y,z)+w*1;
end

% how to make solvation layer?
% take min of smoothed vol+ice for a halo?

%orig straight up floor by ice globally
iced = max(ice,vol);

%
%alternate maybe easier binarization method
solv = imbinarize(rescale(vol)); map = imgaussfilt3(single(~solv),4);%,'FilterSize',3);
%for camk at 6A, ~2 sig, 3 too high and 1 too little SNR. probably need more radiation effect
%for actin at 13A, ~2 sig, 1 SNR is crap - =<2 needs more noise (maybe also more rad damage via noise)

%just do a scaling binarization, maybe with dilation at high mag?
%map = rescale(imcomplement(solv)); %rescaling nonviable, beads bork scaling hard
ice = ice.*map;
iced = vol+ice;
%}

end