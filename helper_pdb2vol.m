function [vol,data] = helper_pdb2vol(pdb,pix,trim,savemat)
%
%
%
%
arguments
    pdb
    pix
    trim = 0 %by default, don't trim (singles still automatically trimmed)
    savemat = 1 %by default, save a .mat file if possible as a much faster alternative
end
%if nargin<2, error('requires both pdb and pixel size inputs'), end

%pdb to atoms
[path,file,ext] = fileparts(pdb);
if strcmp(ext,'.mat') %if .mat, load the data from the file
    try q = load(pdb); data = q.data;
    catch warning('Input is not a pdb2vol-generated .mat file'); end %#ok<SEPEX>
elseif ismember(ext,{'.cif','.mmcif'})
    data = internal_cifparse(pdb);
elseif ismember(ext,{'.pdb','.pdb1'}) %if .pdb, parse the file into a data variable
    data = internal_pdbparse(pdb);
end
vol = internal_volbuild(data,pix,trim);

if savemat==1
    outsave = fullfile(path,append(file,'.mat'));
   % a2 = strrep(pdb,'.pdb','.mat'); %using strrep because fullfile was slower for unknown reason
    if isfile(outsave)
        fprintf(' .mat exists, '); 
    else
        fprintf(' saving .mat... ')
        save(outsave,'data','-nocompression'); %don't compress to save a bit of time saving+loading
    end
end

end


function [data] = internal_pdbparse(pdb)
fid = fileread(pdb); 
text = textscan(fid,'%s','delimiter','\n'); %slightly faster to not parse remarks at all
%text = textscan(fid,'%s','delimiter','\n','CommentStyle',{'REMARK'}); %import each line individually
text = text{1}; %fix being inside a 1x1 cell array

%delete terminator and temperature/ANISOU records that mess with model reading and parsing
ix = strncmp(text,'REMARK',6); text(ix) = []; %clear terminator lines
ix = strncmp(text,'TER',3); text(ix) = []; %clear terminator lines
ix = strncmp(text,'ANISOU',6); text(ix) = []; %delete temp records
ix = strncmp(text,'HETATM',6); text(ix) = []; %delete heteroatoms for sanity

modstart = find(strncmp(text,'MODEL ',6)); %find start of each model entry
modend = find(strncmp(text,'ENDMDL',6)); %find the end of each model entry

if isempty(modstart) %if single-model, extract start and end of atom lines
    modstart = find(strncmp(text(1:round(end/2)),'ATOM  ',6)); modstart = modstart(1);
    endatm = find(strncmp(text(modstart:end),'ATOM  ',6)); endatm = endatm(end);
    endhet = find(strncmp(text(modstart:end),'HETATMjj',6)); %disabled by jj, hetatm currently ignored
    if ~isempty(endhet), endhet = endhet(end); else endhet = 0; end %#ok<SEPEX>
    modend = max(endatm,endhet)+modstart-1; %adjust for having searched only part of the list for speed
    model{1} = text(modstart:modend); models = 1;
elseif numel(modstart)==numel(modend) %if counts match, populate model counts
    models = numel(modstart); model = cell(models,1);
    for i=1:models %extract lines for each individual model
        model{i} = text(modstart(i)+1:modend(i)-1);
    end
elseif numel(modstart)~=numel(modend) %check if model numbers are the same
    error('failed to determine model numbers')
end

data = cell(numel(model),2);
for i=1:models
    chararray = char(model{i}); %convert to char array to make column operable
    chararray(:,[1:30,55:76]) = []; %delete columns outside coords and atom id, faster than making new array
    
    atomvec = upper(strtrim(string(chararray(:,25:26)))); %process atom ids to only letters
    %atomvec1 = chararray(:,25:26); atomvec1 = upper(strrep(string(atomvec1),' ','')); %slightly slower
    data{i,1} = atomvec; %store atoms
    
    coords = [str2num(chararray(:,1:8)),str2num(chararray(:,9:16)),str2num(chararray(:,17:24))]'; %#ok<ST2NM>
    %using str2num because str2double won't operate on 2d arrays, and can't add spaces while vectorized
    data{i,2} = coords; %store coordinates
end

end

function [data] = internal_cifparse(pdb)
fid = fileread(pdb); 
text = textscan(fid,'%s','delimiter','\n'); %read in each line of the text file as strings
%tst = readlines(fid); %readlines from 2020b, compat problems
text = text{1}; %fix being inside a 1x1 cell array

ix = strncmp(text,'HETATM',6); text(ix) = []; %clear hetatm lines to keep CNOPS atoms only

headstart = find(strncmp(text,'_atom_site.group_PDB',20)); %header id start
headend = find(strncmp(text,'_atom_site.pdbx_PDB_model_num',29)); %header id end
loopend = find(strncmp(text,'loop_',5)); %all loop ends

data = cell(numel(headstart),2);
for i=1:numel(headstart)
    loopend(loopend<headstart(i)) = []; %remove loop ends before current block
    header = text( headstart(i):headend(i) )'; %pull header lines
    header = replace(header,{'_atom_site.',' '},{'',''}); %clean bad chars from headers
    model = text( headend(i)+1:loopend(1)-2 ); %pull model lines from after header to loop end
    
    q = textscan([model{:}],'%s','Delimiter',' ','MultipleDelimsAsOne',1); %read strings into cells
    %qq = sscanf([model{:}],'%s',[numel(header) inf]) %lumps everything for some reason
    q = reshape(q{1},numel(header),[])'; %reshape cells to row per atom
    t = cell2table(q,'VariableNames',header); %generate table from atoms using extracted headers
    
    atoms = t.type_symbol;
    
    x = char(t.Cartn_x); y = char(t.Cartn_y); z = char(t.Cartn_z);
    coord = [str2num(x),str2num(y),str2num(z)]';  %#ok<ST2NM>
    
    data{i,1} = atoms; data{i,2} = coord;
end

end

function vol = internal_volbuild(data,pix,trim)

%initialize atomic magnitude information
%mag = struct('H',0,'C',6+1.3,'N',7+1.1,'O',8+0.2,'P',15,'S',16+0.6);
edat = {'H',0;'C',6+1.3;'N',7+1.1;'O',8+0.2;'P',15;'S',16+0.6};
elements = edat(:,1);
op = cell2mat(edat(:,2));

%{
%shang/sigworth numbers (HCNOSP): backwards C and N?
25, 108,  130, 97,  100 and 267   V��3
 0, 1.55, 1.7, 2.0, 1.8 and 1.8 radii
interaction parameters for voltage 100=.92 200=.73 300=.65 mrad/(V*A) (multiply to get real value?)
% hydrogens per atom of c=1.3, n=1.1, o=0.2, s=0.6 to bypass needing to add hydrogens manually

%messy heteroatom version
%mag = struct('H',0,'C',6,'N',7,'O',8,'P',15,'S',16,...
%    'MG',12,'ZN',30,'MN',25,'F',9,'CL',17,'CA',20);

%hydrogen intensity instead shifted onto average H per organic atom, because PDB inconsistently use H records
%currently using atomic number, should use a more accurate scattering factor measure
%}

%faster, vectorized adjustments and limits to coordinates and bounding box
[a,b] = bounds(horzcat(data{:,2}),2); %bounds of all x/y/z in row order
adj = max(a*-1,0)+pix; %coordinate adjustment to avoid indexing below 1
lim = round( (adj+b)/pix +1); %array size to place into, same initial box for all models

models = numel(data(:,2)); emvol = cell(models,1); %pre-allocate stuff
if models==1, trim=1; end
for i=1:models
    atomid = data{i,1}; %single column, hopefully for speed
    coords = round((data{i,2}+adj)./pix); %vectorized computing rounded atom bins outside the loop
    
    %convert atomic labels into atom opacity information outside the loop for speed
    [~,c] = ismember(atomid,elements); % get index for each atom indicating what reference it is
    
    atomint = op(c); %logical index the atom data relative to the atomic symbols
    
    em = zeros(lim'); %initialize empty volume for the model
    
    for j=1:numel(atomint) %faster loop, use vectorized converted atomic info faster than struct reference
        x=coords(1,j); y=coords(2,j); z=coords(3,j);
        em(x,y,z) = em(x,y,z)+atomint(j);
    end
    
    %{
    for j=1:numel(atomid) %slower loop, key-value struct is slow (but almost the fastest method)
        opacity = mag.(atomid{j}); %get atom mag from record - this is the slow step (faster than inline though)
        x=coords(1,j); y=coords(2,j); z=coords(3,j); %parse coords manually, no method to split vector
        %tmp = num2cell(coords(:,j)); [x1,y1,z1] = tmp{:}; %works but is much slower
        em(x,y,z) = em(x,y,z)+opacity; %write mag to the model vol
    end
    %}
    
    if trim==1 %trim empty planes from the border of the model (for everything except .complex models)
        em = em(:,any(em ~= 0,[1 3]),:); 
        em = em(any(em ~= 0,[2 3]),:,:); 
        em = em(:,:,any(em ~= 0,[1 2]));
    end
    emvol{i} = em;
end

vol = reshape(emvol,1,numel(emvol)); %make list horizontal because specifying it initially doesn't work
end