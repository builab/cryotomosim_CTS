function detect = helper_electrondetect(tilt,param)
%lazy temporary help
%tilt is a tilt series (ideally created by helper_ctf)
%param is a param struct created by cts_param, it's important
arguments
    tilt
    param
end
if param.dose<=0, detect=tilt; return; end %if dose 0, skip detection and return perfect detection/original

%tiltangs = param.tilt(1):param.tilt(2):param.tilt(3); %have cts_param parse the tilt angles, or sim?
tiltangs = param.tilt;
%might get weird multifunction tilt angles working by input a list of all angles to cts_param

arb = 1; %arbitrary scaling factor to make contrast look normal
%13.6   same as 12
%12     0.1 is high, 40e is only a bit worse than 120e, 0.01 is low, 40e almost pure noise
%8      0.01 garbo, 0.1 reasonably good, clear differences between 40/80/120
%5      0.1 maybe a bit low, terrible defocus main problem in test case
%5      0.1 very low contrast for CaMK2, 1 still meh contrast at 120

%too high a dose makes the image dominated by noise - is it reasonable? even 40e is blowing out 5a ribos
DQE = .84*arb; %doesn't change with tilts, not sure how to implement fourier space falloff


%tilt ordering
switch param.tiltscheme
    case 'symmetric'
        [~,ix] = sort(abs(tiltangs)); 
    otherwise %find and sort the data from the split between tilt directions
        mdist = max(abs(tiltangs-(param.tiltscheme))); %max dist from start angle where phase will switch
        metric = abs(tiltangs-param.tiltscheme)+mdist.*(tiltangs<param.tiltscheme); %calculate sorting metric
        [~,ix] = sort(metric);
end
tiltangs = tiltangs(ix); tilt = tilt(:,:,ix); %sort tilt angles and tilts
ixr(ix) = 1:numel(ix); %generate reverse sorting index

%dose weighting/distribution
dose = param.dose.*param.pix^2; %convert dose in e/A^2 to e/pixel
if numel(param.dose)==1
    dose = dose/size(tilt,3); %single dose distributed across tilts evenly
else
    dose = dose(ix); %for weighting just sort the weights to the tilts
end

thick = param.size(3)*param.pix; %compute thickness from depth of original model
IMFP = 3500; %inelastic mean free path, average distance before inelastic electron scatter (for water/ice)
%current scattering has a very large effect on signal at higher tilt angles, is IMFP the right scale?
%IMFP is estimated 350nm - just a real thickness and angle problem?
%vectorized, rather than within-loop calculations
electronpath = thick*(1+abs(tand(tiltangs))); %compute the path length of electrons through ice
thickscatter = exp(-(electronpath*param.scatter)/IMFP); %compute electrons not inelastically/lossly scattered
%change IMFP to instead be per pixel, so more electrons are lost at high density AND thickness?
%roughly 5*tilt works for 13.6 filaments, but won't scale due to pixel size. divide by pix^2?
%for 6A, *22 is required. not as big a difference as expected

dw = thickscatter.*dose*DQE;
accum = 0; %initialize accumulated dose of irradiation to 0
detect = tilt.*0; %pre-initialize output array for speed during the loop
for i=1:size(tilt,3)
    irad = tilt(:,:,i)+(randn(size(tilt(:,:,i)))*accum)*.005*param.raddamage; %radiation as 0-center noise
    %.005 rad is too much at 13.6, just wrecks the signal by end tilt
    %.01 is varguely useful for CaMK2, less is better
    %maybe do some masking procedure to blur out only densities near proteins?
    
    accum = accum+dw(i); %add to accumulated dose delivered
    detect(:,:,i) = poissrnd(irad*dw(i),size(irad));
end

detect = detect(:,:,ixr); %reverse the sort so the output tiltseries is a continuous rotation

end