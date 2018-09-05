function extractNetlist4FITEM(filename,msh,Meps,Msigma,Mnu,Isetting,analysis,ipePEC,varargin)
% EXTRACTNETLIST4FITEM automatically generates the netlist describing
% an electromagnetic field problem discretized by the finite integration
% technique (FIT) by means of a circuit. The described circuit consists of
% resistors, inductors, capacitors, controlled sources and impressed
% sources.
%
% Input:
%   filename     name of file to save netlist in
%   msh          struct as defined by src/msh.txt
%                required fields: np,C,ipeGhost
%   Meps         capacitance matrix (3np-by-3np)
%   Msigma       conductance matrix (3np-by-3np)
%   Mnu          reluctance matrix (3np-by-3np)
%   Isetting     struct defining the excitation
%       .pos     indices of the excitation within the mesh
%       .typ     type of current used as excitation
%                {'e':electric,'pwl':piecewise linear}
%       .amp     vector containing the amplitudes of the impressed current
%                sources in the circuit. (3np-by-1)
%   ipePEC       indices of PEC edges (no circuit stamp required for these)
%   optAnalysis  options to pass directly to the SPICE analysis directive
%
% authors:
% Thorben Casper, David Duque, Victoria Heinz, Abdul Moiz,
% Herbert De Gersem, Sebastian Schoeps
% Institut fuer Theorie Elektromagnetischer Felder
% Graduate School of Computational Engineering
% Technische Universitaet Darmstadt

tstart = tic;
fprintf('extracting electromagnetic netlist ...\n');

% compute inductances (3np-by-1)
L = fit2ind(msh,Mnu);

% compute current gain for CCCSs (3np-by-3np)
gI = fit2cccs(msh,Mnu,L);

% impressed current sources
if strcmp(Isetting.type,'e')
    Ii = sparse(3*msh.np,1);
    Ii(Isetting.pos,1) = Isetting.amp;
elseif strcmp(Isetting.type,'pwl')
    Ii = Isetting.amp;
else
    error('type of impressed source is not implemented');
end

% open netlist file
fileID = fopen([filename,'.cir'],'w');
fprintf(fileID,'This electromagnetic netlist was generated by ANTHEM (https://github.com/tc88/ANTHEM)\n');

% iterate over edges Lm of the grid (algorithm 2)
for m = 1:3*msh.np
    % only run this iteration if m is not a ghost nor PEC edge
    if ~ismember(m,msh.ipeGhost) && ~ismember(m,ipePEC)

        % resistor
        if Msigma(m,m) ~= 0
            Rm = full(1/Msigma(m,m));
            fprintf(fileID,'%s%d\t%d\t%d\t%-25.10e\n','R',m,m,0,Rm);
        end

        % inductor (requires auxiliar node 'nodef' to insert ammeter)
        nodef = sprintf('%d%c',m,'f');
        fprintf(fileID,'%s%d\t%d\t%s\t%-25.10e\t%s\n','L',m,m,nodef,L(m),'ic=0');
        % ammeter (modeled as independent voltage sources of zero amplitude)
        fprintf(fileID,'%s%d%c\t%d\t%s\t%s\t%d\n','V',m,'f',0,nodef,'AC',0);

        % capacitor
        Cm = full(Meps(m,m));
        if Cm ~= 0
            fprintf(fileID,'%s%d\t%d\t%d\t%-25.10e\t%s\n','C',m,m,0,Cm,'ic=0');
        end

        % impressed current sources
        if ~iscell(Ii)
            if Ii(m) ~= 0
                fprintf(fileID,'%s%d\t%d\t%d\t%s\t%-25.10e\n','I',m,0,m,'AC',full(Ii(m)));
            end
        elseif ~isempty(Ii{m})
            fprintf(fileID,'%s%d\t%d\t%d\t%s\tfile=%s\n','I',m,0,m,'PWL',Ii{m});
        end

        % CCCSs (first finding non-zero gain of CCCS relevant for edge m)
        nVec = find(gI(m,:));
        for n = nVec
            % check if edge n belongs to PEC edges
            if ~ismember(n,ipePEC)
                % get gain from edge n to edge m
                gImkn = full(gI(m,n));
                % print controlled current stamp
                fprintf(fileID,'%s%d%c%d\t%d\t%d\t%s%d%c\t%-25.10e\n','F',m,'_',n,0,m,'V',n,'f',gImkn);
            end
        end
    end
end

% circuit analysis options
analysisString = createAnalysis(analysis,varargin{:});
fprintf(fileID,'%s\n',analysisString);

% disable direct Newton iteration and Gmin stepping for faster init DC solution
fprintf(fileID,'.option noopiter gminsteps 0');

% close netlist file
fclose(fileID);

fprintf('finished extracting electromagnetic netlist after %d seconds.\n',toc(tstart));

end