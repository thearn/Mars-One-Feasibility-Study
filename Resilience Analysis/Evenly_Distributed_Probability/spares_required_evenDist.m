%
% spares_required_evenDist.m
%
% Creator: Andrew Owens
% Last updated: 2014-09-02
%
% This script performs a spares analysis for the Mars One ECLSS; the end
% result is the mass of spares required to obtain the minimum probability
% input in the solution parameters section.
%
% The implemented methodology is based on the semi-Markov analysis
% techniques described in
%   Owens, A. C., 'Quantitative Probabilistic Modeling of Environmental
%       Control and Life Support System Resilience for Long-Duration Human
%       Spaceflight,' S.M. Thesis, Massachusetts Institute of Technology,
%       2014.
%
% Assumptions:
%   1) Buffers are sized to be sufficiently large to isolate failures (i.e.
%      failed components are repaired before the buffers they manage
%      deplete)
%   2) Repair is implemented via replacement of the failed component with
%      an identical spare, which returns the system to good-as-new
%   3) Components exhibit exponential failure distributions (constant
%      failure rate)
%

% SEE IF YOU CAN FIND PACKING MASS/VOLUME FRACTION
% Plant growth area is not redundant, so the lights aren't either
% solar cells 3000m^2 (340kW)
% Figure out multiple components

% add the SMP solver modules to the path
addpath SMP_modules_evenDist

%% Set solution parameters

% Required probability for the entire system
overallProbability = 0.99;

% cutoff probability; probabilities less than this will be considered to be
% effectively 0
cutoff = 1e-9;

% time between resupply missions [h]
duration = 2*365*24;

% discretization size
dt = 0.05;

% define processor sets; processors are comprised of the components in rows
% startRow:endRow as encoded in each row of this matrix
processorSets = [1, 7;  % OGA
    8, 16; % CDRA and ORA
    17, 26; % CCAA x4
    27, 33; % UPA
    34, 49; % WPA
    50, 56; % CRA
    57, 57]; % GLS (this must always be the last one)

% encode the number of instances of each processor
numInstances = [1; % OGA
    2; % CDRA and ORA are the same
    4; % CCAA in each cabin
    1; % UPA
    1; % WPA
    1; % CRA
    1]; % GLS

%% Set up and solve SMP for each processor
% Processors are comprised of subassemblies. Since all processors are
% separated by buffers, each can be considered independently. Failure of a
% subassembly within a processor takes the entire processor online until
% the failed subassembly is replaced with a spare, at which point the
% processor is brought back to nominal working condition.

% load component data
% col 1 is mass [kg], col 2 is MTBF [h], col 3 is number in system [-]
componentData = csvread('componentData.csv',0,1);

% create mass vector and vector indicating the number of each component
massVector = [];
numVector = [];
for j = 1:size(processorSets,1)
    massVector = [massVector; ...
        componentData(processorSets(j,1):processorSets(j,2),1)];
    numVector = [numVector; ...
        componentData(processorSets(j,1):processorSets(j,2),3)];
end

% create result storage for the number of spares for each subassembly and
% the resulting probability for that number of spares
subassemSpares = [];
subassemProbs = [];

% determine number of subassemblies in system
% remember to add in subassemblies for the processors that have multiple
% instances in the system (CRDA x2, CCAA x4)
nSubassem = 0;
for j = 1:length(numInstances)
    nSubassem = nSubassem + sum(numVector(processorSets(j,1):...
        processorSets(j,2)))*numInstances(j);
end

% calculate probability for each subassembly required to obtain overall
% probability requirement
subassemProbability = overallProbability^(1/nSubassem);

% for each processor (not the growth lights yet)
tic
for j = 1:size(processorSets,1)-1
    % give status
    disp(['Calculating for Processor ' num2str(j)])
    
    % set up and solve the SMP to get the number of spares required for
    % this processor to obtain the required probability, as well as the
    % value of that probability and the expected downtime for this
    % processor
    [thisSpares, thisProbabilities, thisDowntime] = getProcessorSpares(...
        componentData(processorSets(j,1):processorSets(j,2),2),...
        numVector(processorSets(j,1):processorSets(j,2)),...
        subassemProbability,cutoff,duration,dt);
    
    % store results
    subassemSpares = [subassemSpares; thisSpares];
    subassemProbs = [subassemProbs; thisProbabilities];
    downtime(j) = thisDowntime;
    
    % give status
    thisTime = toc;
    disp(['     Total Elapsed Time: ' num2str(thisTime)])
end

% Growth lights are a large array of identical elements. We can just count
% the number of renewals for the minimum of the exponential processes.
% Downtime here has no effect on the rest of the system (because there is
% no redundant growth system), so we don't need to count it.
disp('Calculating for GLS')

% find MTBF for the whole array
mtbf_gls = componentData(end,2);
mtbf_glsArray = 1/(numVector(end)*(1/mtbf_gls));
[thisSpares, thisProbabilities, ~] = getProcessorSpares(mtbf_glsArray,1,...
    subassemProbability,cutoff,duration,dt);
% store results
subassemSpares = [subassemSpares; thisSpares];
subassemProbs = [subassemProbs; thisProbabilities];
downtime(j) = 0;

% give status
thisTime = toc;
disp(['     Total Elapsed Time: ' num2str(thisTime)])

% calculate total mass and probability, accounting for multiple instances

% calculate true number of spares, as well as probability, taking into
% account multiple instances
trueSpares = zeros(size(subassemSpares));
totalProb = 1;
for j = 1:length(numInstances)
    % true number of spares
    trueSpares(processorSets(j,1):processorSets(j,2)) = ...
        subassemSpares(processorSets(j,1):processorSets(j,2)).* ...
        numInstances(j);
    
    % probability
    thisProb = prod(subassemProbs(processorSets(j,1):processorSets(j,2)));
    totalProb = totalProb*(thisProb^numInstances(j));
end

% calculate total mass
totalMass = massVector'*trueSpares;

% write individual subassembly results to file
csvwrite('RESULTS.csv',trueSpares);

% display outputs
disp('----- RESULTS -----')
disp(['For overall probability of ' num2str(overallProbability) ':'])
disp(['Total mass of spares: ' num2str(totalMass)])
disp(['Resulting Probability: ' num2str(totalProb)])
disp('Subassembly spares counts have been written to RESULTS.csv')
disp('-------------------')