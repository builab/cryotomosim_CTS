function [iced, ice] = gen_ice(vol,pix)
w = 8+2; %atomic number total in water molecule, until i can get electron opacity numbers
%amorphous ice density ~.94g/cm^3, but unit vol of liquid h20 molecule is 29.7a^3, estimate 20-30
%unit vol of water is 29.7a^3, dramatically larger than atoms, diameter ~2.75A.

%density = 0.90/(1e8)^3/18*6.022e23; %convert from cm3 to a3, then g to molecules via mol/dalton
%denspix = density*(pix^2.85);%/24; %^3 theoretical calculation correct, might be as low as 2.7

denspix = (.94*6e23/18)*(pix/1e8)^3; %d = (d*mol/mass)*(pixel/m-a conv)^3 average atom/pix for ice ~.94g/cm3
%corrected density is too high, losing quite a bit of protein under the water signal, models poor
%need to test how terrible the simulations are
%pretty bad, but not totally worthless

%different pixel size densities don't scale exactly cubic due to protein folding/surfacing

atomfrac = exp(-pix/3); %fraction as points rather than flat background
%does compressing it into fewer points of higher density work without screwing the noise?
mol = round(denspix*numel(vol)*atomfrac); % 20% of ice mass randomly distributed as molecules
ice = round(vol*0+denspix*(1-atomfrac)*w); %80% of ice mass as flat background for speed

densfrac = 20/(20+pix)*1+0;
mol = round(denspix*numel(vol)*atomfrac*densfrac);
%ice = ice*0;
w = w/densfrac;

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
%new half-assed weighted combination, might make a good solv layer
solv = imgaussfilt3(vol,150/(10+pix),'FilterSize',17);
map = (solv*-1)+max(solv,[],'all'); map = map/(pix^3);

%alternate maybe easier binarization method
solv = imbinarize(rescale(vol)); map = imgaussfilt3(single(~solv),4);%,'FilterSize',3);
%sigma of 0.5 is flat and noisy
%for camk at 6A, ~2 sig, 3 too high and 1 maybe to little SNR (maybe radiation rescale?)
%for actin at 13A, 

%just do a scaling binarization, maybe with dilation at high mag?
%map = rescale(imcomplement(solv)); %rescaling nonviable, beads bork scaling hard
ice = ice.*map;
iced = vol+ice;
%}

end