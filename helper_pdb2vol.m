function [vol,sum,names,data] = helper_pdb2vol(pdb,pix,trim,savemat)
%[vol,data] = helper_pdb2vol(pdb,pix,trim,savemat)
%generates a EM density map(s) from an atomic structure definition file
%
%pdb - atomic structure file. valid types: .pdb/a, .cif/.mmcif, or .mat generated by this function
%pix - pixel size of the output density map in angstroms
%trim - trim empty space surrounding the EM density (default 0, always reverts to 1 for single models)
%savemat - save a .mat of atomic information, loads much faster than full structure files
%
%vol - cell array of EM density maps
%data - cell array of atomic IDs and coordinates, equivalent to the saved .mat
arguments
    pdb
    pix
    trim = 0 %by default, don't trim (singles still automatically trimmed)
    savemat = 1 %by default, save a .mat file if possible as a much faster alternative
end

[path,file,ext] = fileparts(pdb);
if strcmp(ext,'.mat') %if .mat, load the data from the file
    try q = load(pdb); data = q.data;
    catch warning('Input is not a pdb2vol-generated .mat file'); end %#ok<SEPEX>
elseif ismember(ext,{'.cif','.mmcif'})
    data = internal_cifparse(pdb);
elseif ismember(ext,{'.pdb','.pdb1'})
    data = internal_pdbparse(pdb);
end
[vol,sum,names] = internal_volbuild(data,pix,trim);

if savemat==1 %.mat saving and check if file already exists
    outsave = fullfile(path,append(file,'.mat'));
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

%pdb appear to have no means of storing model names
%mmcif DOES store model name, line is data_MODELNAME
%can use to detect the number of models and their names for cleaner files

%delete terminator and temperature/ANISOU records that mess with model reading and parsing
ix = strncmp(text,'REMARK',6); text(ix) = []; %clear terminator lines
ix = strncmp(text,'TER',3); text(ix) = []; %clear terminator lines
ix = strncmp(text,'ANISOU',6); text(ix) = []; %delete temp records
ix = strncmp(text,'CONECT',6); text(ix) = []; %delete bond information for now
%ix = strncmp(text,'HETATM',6); text(ix) = []; %delete heteroatoms for sanity

modstart = find(strncmp(text,'MODEL ',6)); %find start of each model entry
modend = find(strncmp(text,'ENDMDL',6)); %find the end of each model entry

if isempty(modstart) %if single-model, extract start and end of atom lines
    %new idea, doudble string search before find
    %modelspan = strncmp(text(1:round(end/2)),'ATOM  ',6)+strncmp(text(1:round(end/2)),'HETATM',6);
    modelspan = strncmp(text,'ATOM  ',6)+strncmp(text,'HETATM',6);
    modelspan = find(modelspan); 
    modstart = modelspan(1);
    modend = modelspan(end);
    %modspan = [modstart,modend]
    %{
    atomstart = find(strncmp(text(1:round(end/2)),'ATOM  ',6));
    atomend = find(strncmp(text(modstart:end),'ATOM  ',6));
    hetstart = find(strncmp(text(1:round(end/2)),'HETATM',6));
    hetend = find(strncmp(text(modstart:end),'HETATM',6));
    %modstart = find(strncmp(text(1:round(end/2)),'ATOM  ',6));
    
    try
        modstart = min(modstart(1),hetstart(1));
    catch
        %modstart = 
        atomend = atomend(end);
    end
    %}
    %need to refactor to intelligently find atom/hetatm segments
    %endhet = find(strncmp(text(modstart:end),'HETATM',6)); %disabled by jj, hetatm currently ignored
    %if ~isempty(endhet), endhet = endhet(end); else endhet = 0; end %#ok<SEPEX>
    %modend = max(atomend,endhet)+modstart-1; %adjust for having searched only part of the list for speed
    
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
    data{i,3} = 'NA';
end

end

function [data] = internal_cifparse(pdb)
fid = fileread(pdb); 
text = textscan(fid,'%s','delimiter','\n'); %read in each line of the text file as strings
%tst = readlines(fid); %readlines from 2020b, compat problems
text = text{1}; %fix being inside a 1x1 cell array

modnames = text(strncmp(text,'data_',5)); %retrieve lines storing model names
for i=1:numel(modnames) 
    modnames{i} = erase(modnames{i},'data_'); %clean name lines
end

%ix = strncmp(text,'HETATM',6); text(ix) = []; %clear hetatm lines to keep CNOPS atoms only

headstart = find(strncmp(text,'_atom_site.group_PDB',20)); %header id start
headend = find(strncmp(text,'_atom_site.pdbx_PDB_model_num',29)); %header id end
loopend = find(strncmp(text,'#',1)); %all loop ends

data = cell(numel(headstart),2);
for i=1:numel(headstart)
    loopend(loopend<headstart(i)) = []; %remove loop ends before current block
    header = text( headstart(i):headend(i) )'; %pull header lines
    header = replace(header,{'_atom_site.',' '},{'',''}); %clean bad chars from headers
    model = text( headend(i)+1:loopend(1)-1 ); %pull model lines from after header to loop end
    q = strrep(model,'" "','1'); %replace quoted spaces with 1 to fix blankspace errors
    
    q = textscan([q{:}],'%s','Delimiter',' ','MultipleDelimsAsOne',1); %read strings into cells
    q = reshape(q{1},numel(header),[])'; %reshape cells to row per atom
    t = cell2table(q,'VariableNames',header); %generate table from atoms using extracted headers
    
    atoms = t.type_symbol; %re-extract atom ID and coordinates from the temporary table
    x = char(t.Cartn_x); y = char(t.Cartn_y); z = char(t.Cartn_z);
    coord = [str2num(x),str2num(y),str2num(z)]';  %#ok<ST2NM> %merge coordinates into a single array
    
    data{i,1} = atoms; data{i,2} = coord; data{i,3} = modnames{i};
end


end

function [vol,sumvol,names] = internal_volbuild(data,pix,trim)
sumvol = 0; %stopgap until i implement centering and such things

%initialize atomic magnitude information
%mag = struct('H',0,'C',6+1.3,'N',7+1.1,'O',8+0.2,'P',15,'S',16+0.6);
edat = {'H',0;'C',6+1.3;'N',7+1.1;'O',8+0.2;'P',15;'S',16+0.6};
elements = edat(:,1);
atomdict = cell2mat(edat(:,2));

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

%dummy volume detector would go here to center stuff
%get lim and adj based on largest distances from the dummy origin, then remove the dummy model
names = data(:,3);
%oriindex = ~cellfun('isempty',strfind(names,'origin'));
%strfind(names,'origin')';
%strfind([names{:}],'origin')';
ix = find(contains(names,'origin')); %get the index, if any, of the name origin in the model
%find(ix); %get the index of the actual name
if ~isempty(ix) %&& 5==4
    trim=0; %don't trim if a centroid is imposed, need to revise input options
    [a,b] = bounds(horzcat(data{:,2}),2) %bounds of all x/y/z in row order
    origin = mean(data{ix,2},2);
    %origin = origin([2,1,3]) %get the origin coordinate to subtract if not already 0
    span = max(origin-a,b-origin) %get spans measured from the origin
    lim = ceil(span/pix+0.5)*2+1 %get pixel box from span, always off to ensure origin perfect center
    adj = (lim-1)/2+1
    %adj = span+pix/2; %calculate the adjustment to apply to coordinates to put them into the box
    %lim = round( (adj+b)/pix +1);
else
    %origin = mean(horzcat(data{:,2}),2); %get the geometric mean of atom coordinates
    [a,b] = bounds(horzcat(data{:,2}),2); %bounds of all x/y/z in row order
    origin = (a+b)/2; %get the box center of the points
    %span max-min for total distance, +safety whole pix?
    %adj value subtract min from values to shift centering to all positive?
    %origin-a
    span = max(origin-a,b-origin); %get spans measured from the origin
    %span = b-a+pix;
    %need to calculate span as largest distance in each dim from origin
    lim = ceil(span/pix)*2+1; %get pixel box from span, always off to ensure origin perfect center
    adj = span/2+1.5
    %adj = max(a*-1,0)+pix; %coordinate adjustment to avoid indexing below 1
    %lim = round( (adj+b)/pix +1); %array size to place into, same initial box for all models
    %faster, vectorized adjustments and limits to coordinates and bounding box
    
    trim = 1; %do trimming if origin not specified now that it won't break complexes
end

%data{3,2}
%maxxes = max(abs(data{3,2}),[],2)
%mean(data{3,2},2)
%data(3,2)
%centroid = mean(horzcat(data{:,2}),2);

models = numel(data(:,2)); emvol = cell(models,1); %pre-allocate stuff
%if models==1, trim=1; end %would break single-model memprots
for i=1:models
    atomid = data{i,1}; %single column, hopefully for speed
    
    %convert atomic labels into atom opacity information outside the loop for speed
    [~,c] = ismember(atomid,elements); % get index for each atom indicating what reference it is
    
    badentries = find(c<1); %find entries not in the element register
    c(badentries)=[]; data{i,2}(:,badentries) = []; %remove bad entries
    
    coords = round((data{i,2}+adj)./pix); %vectorized computing rounded atom bins outside the loop
    atomint = atomdict(c); %logical index the atom data relative to the atomic symbols
    %em = zeros(lim'); %initialize empty volume for the model
    em = zeros(lim');
    
    for j=1:numel(atomint) %faster loop, use vectorized converted atomic info faster than struct reference
        x=coords(1,j); y=coords(2,j); z=coords(3,j);
        [x,y,z]
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
    
    emvol{i} = em;
end

if trim==1 %trim empty planes from the border of the model (for everything except .complex models)
    emvol = ctsutil('trim',emvol);
end
sumvol = sum( cat(4,emvol{:}) ,4); %sum all volumes

vol = reshape(emvol,1,numel(emvol)); %make list horizontal because specifying it initially doesn't work
end