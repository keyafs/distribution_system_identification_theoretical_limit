% This is the main code of the theoretical limit of distribution system
% identification.
% This code require the package of Matpower and OpenDss

%% We set some hyper parameters
clear;clc;
warning off
caseName = 'case123_R';     % the case name    'case3_dist' 'case33bw'  'case123_R' 'case141'
numSnap = 200;             % the number of snapshot
range.P = 1.2;               % the deviation range of active load 0.6
range.Q = 0.3;             % the deviation range of reactive load to active load 0.2

% the accuracy of measurement device
ratio.P = 0.0001;%0.005
ratio.Q = 0.0001;
ratio.Vm = 0.0001;%0.00001  0.00000001
ratio.Va = 0.0001;%0.000005

% if we use the sparse option
sparseOption = true;

% the tolerance of setting a branch to be zero
topoTol = 0.05;

% the prior knowledge of G and B matrix
switch caseName
    case 'case33bw'
        prior.Gmin = 0.3;
        prior.Bmin = 0.3;
        prior.Gmax = 500;
        prior.Bmax = 500;
    case 'case123_R'
        prior.Gmin = 3;
        prior.Bmin = 3;
        prior.Gmax = 200;
        prior.Bmax = 200;
    case 'case141'
        prior.Gmin = 10;
        prior.Bmin = 10;
        prior.Gmax = 20000;
        prior.Bmax = 20000;
    otherwise
        prior.Gmin = 0.1;
        prior.Bmin = 0.1;
        prior.Gmax = 1000;
        prior.Bmax = 1000;
end

% % the delta value of FIM matrix
% delta = 0.1;

% the enlarge factor to maintain the numerical stability
switch caseName
    case 'case33bw'
        k.G = 1;%50;%5;%1000;
        k.B = 1;%100;%10;%5000;
        k.vm = 1;%1000;%100;%100000;
        k.va = 1;%10000;%1000;%1000000;
        ratio.Pmin = 0.05; % the minimum P measurement noise compared with the source bus
        ratio.Qmin = 0.05;
    otherwise
        k.G = 1;
        k.B = 1;
        k.vm = 1;
        k.va = 1;
        ratio.Pmin = 0.01; % the minimum P measurement noise compared with the source bus
        ratio.Qmin = 0.01;
end

% profile on;
%% We generate the power flow data
caseDS = caseDistributionSystemMeasure(caseName, numSnap, range);
caseDS = caseDS.readLoad;
caseDS = caseDS.genOperateData;

%% We evaluate the bound
% set the accuracy of the measurement device, and set whether we have the
% measurement device of a certain state
caseDS = caseDS.setAccuracy(ratio);
caseDS = caseDS.setTopo;
% profile on
caseDS.prior = prior;
caseDS = caseDS.buildFIM;
% caseDS = caseDS.calBound(caseDS.topoPrior);
caseDS = caseDS.updateTopo(caseDS.topoPrior);
% profile off
% profile viewer
% caseDS = caseDS.iterateY;
caseDS = caseDS.setTopo;
caseDS = caseDS.preEvaluation(prior);
caseDS = caseDS.approximateFIM(k);
caseDS = caseDS.calABound(true, caseDS.topoPrior);

% caseDS = caseDS.initValue;
% caseDS = caseDS.identifyMCMCEIO;
% caseDS = caseDS.identifyMCMCEIV;
% caseDS = caseDS.identifyOptNLP;
% caseDS = caseDS.identifyOptGradient;
caseDS = caseDS.identifyLineSearch;
% caseDS = caseDS.identifyOptLMPower;
caseDS = caseDS.evalErr;
% caseDS = caseDS.identifyOptNewton;
% caseDS = caseDS.buildFIM(k);
% caseDS = caseDS.updateTopo(topoTol, sparseOption);
% profile off;
% profile viewer;