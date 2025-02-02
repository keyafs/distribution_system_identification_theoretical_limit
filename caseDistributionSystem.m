classdef caseDistributionSystem < handle
    % This is the class of distribution system
    
    properties
        caseName            % the name of the power system case
        mpc                 % the matpower struct of the power system
        numBus              % the number of buses
        numBranch           % the number of branches
        numSnap             % the number of snapshot
        range               % the struct of deviation range
        numFIM              % the struct representing the size of FIM matrix
        
        addressLoadRaw      % the address of raw load data
        addressLoad         % the address of preprocessed load data
        addressOutput       % the address of the output data
        
        loadP               % the active load of each bus
        loadQ               % the reactive load of each bus
        
        FIM                 % the fisher information matrix
        FIMP                % the (sparse) FIM of active power injection
        FIMQ                % the (sparse) FIM of reactive power injection
        FIMVm               % the (sparse) FIM of voltage magnitude
        FIMVa               % the (sparse) FIM of voltage angle
        
        data                % the data struct contains operation data
        sigma               % the variance of each meansurement noise
        isMeasure           % whether we have a specific measurement device
        
        bound               % the bound of different parameters
        bound1              % the bound with disturbance
        sparseOption        % we use the sparse option
        k                   % the enlarge factor to maintain the numerical stability
        tol                 % the tolerance of the modified Cholesky decomposition
        
        topoPrior           % the prior topology knowledge (if two buses are disconnected) true-has topo prior
        topoTol             % the tolerance of topology identification (forcing the small value to zero)
        boundIter           % the iteration history of the bounds
        acc                 % the accuracy of topology identification
        
        P_delta             % the delta value considering measurement noise
        Q_delta             % the delta value considering measurement noise
        
        M                   % the measurement matrix
        numMeasure          % the number of measurements
        
        mRow                % the row id of Measurement matrix
        mCol                % the col id of Measurement matrix
        mVal                % the value id of Measurement matrix
        spt                 % the point of the sparse vectors
        
        idGB                % the address of G and B matrix
        idVmVa              % the id of Vm and Va
        idVm                % the id of Vm
        idVa                % the id of Va
        
        isAnalyze           % if we analyze the contribution from different measurements
    end
    
    methods
        function obj = caseDistributionSystem(caseName, numSnap, range)
            % the construction function
            obj.caseName = caseName;
            obj.addressLoadRaw = '.\data\file1csv.csv';
            obj.addressLoad = '.\data\dataLoad.csv';
            obj.addressOutput = ['.\output\bound',caseName,'.csv'];
            
            % load the distribution system
            obj.mpc = loadcase(caseName);
            obj.numBus = size(obj.mpc.bus, 1);
            obj.numBranch = size(obj.mpc.branch, 1);
            obj.numSnap = numSnap;
            obj.range = range;
                       
        end
        
        function readLoadRaw(obj)
            % this method read and process the raw load data
            
            numDay = 20;            % we read 20 days of load data
            numCustomer = 979;      % the number of costomer of the first day
            loadRaw = xlsread(obj.addressLoadRaw);
            % read the data by rows
            load = zeros(numCustomer, numDay*48);
            idCustomer = loadRaw(1:numCustomer, 1);
            numRow = size(loadRaw, 1);
            idDay = 0;
            for i = 1:numRow
                if loadRaw(i, 2) > idDay % read the data of a new day
                    idDay = loadRaw(i, 2);
                end
                idRow = find(idCustomer == loadRaw(i, 1));
                if ~isempty(idRow)
                    rangeDay = (idDay-195)*48+1 : (idDay-194)*48;
                    load(idRow, rangeDay) = loadRaw(i, 3:end);
                end
            end
            % output the preprocessed load data
            xlswrite(obj.addressLoad, load);
        end
        
        function obj = readLoad(obj)
            % this method read the prepocessed load data, aggregate the
            % data, and cut the data into the appropriate size
            numAggregation = 5;     % aggregate serveral loads together 5
            loadRead = xlsread(obj.addressLoad);
            [numCust, numSnapRaw] = size(loadRead);
            numCustAggre = fix(numCust / numAggregation);
            load = zeros(numCustAggre, numSnapRaw);
            
            % aggregate and normalize the data
            idRow = 1;
            for i = 1:numCust
                if (mod(i,numAggregation) == 0)
                    custRange = i-numAggregation+1:i;
                    thisLoad = sum(loadRead(custRange,:));
                    load(idRow,:) = thisLoad/max(thisLoad);
                    idRow = idRow + 1;
                end
            end
            
            % cut the data
            load(obj.numBus:end,:) = []; % exclude the source bus
            load(:,obj.numSnap+1:end) = [];
            
            % rescale the data
            load = 1 - obj.range.P/3 + load*obj.range.P; % 2
            obj.loadP = load;
            
            % generate the reactive load data
            rng(1);
            randQ = rand(size(load)) * obj.range.Q + 1 - obj.range.Q/2;
            obj.loadQ = load .* randQ;
        end
        
        function obj = genOperateData(obj)
            % this method generate the steady state operation data by
            % running power flow equations
            data_.P = zeros(obj.numBus, obj.numSnap);
            data_.Q = zeros(obj.numBus, obj.numSnap);
            data_.Vm = zeros(obj.numBus, obj.numSnap);
            data_.Va = zeros(obj.numBus, obj.numSnap);
            data_.PF = zeros(obj.numBranch, obj.numSnap);
            data_.PT = zeros(obj.numBranch, obj.numSnap);
            data_.QF = zeros(obj.numBranch, obj.numSnap);
            data_.QT = zeros(obj.numBranch, obj.numSnap);
            isSuccess = ones(obj.numSnap, 1);
            
            define_constants;
            
            for i = 1:obj.numSnap
                mpcThis = obj.mpc;
                % update active and reactive load
                mpcThis.bus(2:end,3) = mpcThis.bus(2:end,3) .* obj.loadP(:, i);
                if strcmp(obj.caseName, 'case123_R')
                    mpcThis.bus(2:end,4) = mpcThis.bus(2:end,4) .* obj.loadQ(:, i) * 2; %2
                else
                    mpcThis.bus(2:end,4) = mpcThis.bus(2:end,4) .* obj.loadQ(:, i);
                end
                % run power flow
                mpopt = mpoption('verbose',0,'out.all',0);
                mpcThis = runpf(mpcThis, mpopt);
                isSuccess(i, 1) = mpcThis.success;
                % output the data
                inject = makeSbus(mpcThis.baseMVA, mpcThis.bus, mpcThis.gen);
                data_.P(:,i) = real(inject);
                data_.Q(:,i) = imag(inject);
                data_.Vm(:,i) = mpcThis.bus(:, VM);
                data_.Va(:,i) = mpcThis.bus(:, VA)/180*pi;
                data_.PF(:,i) = mpcThis.branch(:, PF);
                data_.PT(:,i) = mpcThis.branch(:, PT);
                data_.QF(:,i) = mpcThis.branch(:, QF);
                data_.QT(:,i) = mpcThis.branch(:, QT);
            end
            
            % assert that all the power flow converge
            assert(isempty(find(isSuccess == 0, 1)));
            
            % calculate the active and reactive current injection
            data_.IP = data_.P ./ data_.Vm;
            data_.IQ = data_.Q ./ data_.Vm;
            
            % generate the G and B matrix
            Y = makeYbus(obj.mpc);
            data_.G = real(full(Y));
            data_.B = imag(full(Y));
            data_.GBzero = data_.G == 0;
            
            obj.data = data_;
        end
        
        function obj = setTopo(obj)
            % This function set the prior topology
            obj.topoPrior = false(obj.numBus, obj.numBus);
            
            switch obj.caseName
                case 'case3_dist'
                    obj.topoPrior = true(obj.numBus, obj.numBus);
                    obj.topoPrior(obj.data.G ~= 0) = false;
                    idBranchOptional = obj.mpc.branch(:, 11) == 0;
                    idRow = obj.mpc.branch(idBranchOptional, 1);
                    idCol = obj.mpc.branch(idBranchOptional, 2);
                    for i = 1:length(idRow)
                        obj.topoPrior(idRow(i), idCol(i)) = false;
                        obj.topoPrior(idCol(i), idRow(i)) = false;
                    end
                case 'case33bw'
                    obj.topoPrior = true(obj.numBus, obj.numBus);
                    obj.topoPrior(obj.data.G ~= 0) = false;
                    idBranchOptional = obj.mpc.branch(:, 11) == 0;
                    idRow = obj.mpc.branch(idBranchOptional, 1);
                    idCol = obj.mpc.branch(idBranchOptional, 2);
                    for i = 1:length(idRow)
                        obj.topoPrior(idRow(i), idCol(i)) = false;
                        obj.topoPrior(idCol(i), idRow(i)) = false;
                    end
                case 'case123_R'
                    obj.topoPrior = true(obj.numBus, obj.numBus);
                    obj.topoPrior(obj.data.G ~= 0) = false;
                    idBranchOptional = obj.mpc.branch(:, 11) == 0;
                    idRow = obj.mpc.branch(idBranchOptional, 1);
                    idCol = obj.mpc.branch(idBranchOptional, 2);
                    for i = 1:length(idRow)
                        obj.topoPrior(idRow(i), idCol(i)) = false;
                        obj.topoPrior(idCol(i), idRow(i)) = false;
                    end
                otherwise
                    obj.topoPrior = true(obj.numBus, obj.numBus);
                    obj.topoPrior(obj.data.B ~= 0) = false;
                    idBranchOptional = obj.mpc.branch(:, 11) == 0;
                    idRow = obj.mpc.branch(idBranchOptional, 1);
                    idCol = obj.mpc.branch(idBranchOptional, 2);
                    for i = 1:length(idRow)
                        obj.topoPrior(idRow(i), idCol(i)) = false;
                        obj.topoPrior(idCol(i), idRow(i)) = false;
                    end
            end
            
%             obj.topoPrior = false(obj.numBus, obj.numBus); % do not consider any topology priors
        end
        
        function obj = setAccuracy(obj, varargin)
            % This method set the accuracy of the measurement device and
            % generate the measurement noise. This method also set whether
            % we have the measurement of a certain state.
            
            % we first set the relative noise ratio, we assume the noise
            % ratio is the sigma/mean value
            if nargin == 3
                ratio = varargin{1};
                seed = varargin{2};
            elseif nargin == 2
                ratio = varargin{1};
                seed = 0;
            elseif nargin == 1
                ratio.P = 0.005;
                ratio.Q = 0.005;
                ratio.Vm = 0.005; % 0.0000001 0.00001
                ratio.Va = 0.005;
                seed = 0;
            end
            % we then configure where are the measurement devices
            obj.isMeasure.P = true(obj.numBus, 1);
            obj.isMeasure.Q = true(obj.numBus, 1);
            obj.isMeasure.Vm = true(obj.numBus, 1);
            obj.isMeasure.Va = false(obj.numBus, 1); % false
            obj.isMeasure.Vm(1) = false;
            obj.isMeasure.Va(1) = false;
%             obj.isMeasure.Va(3) = false;
%             obj.isMeasure.Va(4) = false;
%             obj.isMeasure.Va(2:5) = true(length(2:5), 1);
%             obj.isMeasure.Q(2:3) = false(2, 1);
%             obj.isMeasure.P(6:7) = false(2, 1);
            % Set the tolerance of the modified Cholesky decomposition
            if any(obj.isMeasure.Va) % we have the measurement of Va
                obj.tol = 0.45;
            else
                obj.tol = 0.77;
            end
            % We assume there is no noise in the source bus. We set the
            % enlarge ratio of each rows of measurement noise.
%             obj.sigma.P = max(abs(obj.data.P),[], 2) * ratio.P; %  mean(abs(obj.data.P), 2) * ratio.P;
%             obj.sigma.Q = max(abs(obj.data.Q),[], 2) * ratio.Q; % mean
            switch obj.caseName
                case 'case141'
                    isZeroInj = mean(abs(obj.data.P), 2)==0;
                    obj.sigma.P = ones(obj.numBus, 1) * mean(mean(abs(obj.data.P), 2)) * ratio.P * 10; %  mean(abs(obj.data.P), 2) * ratio.P;
                    obj.sigma.Q = ones(obj.numBus, 1) * mean(mean(abs(obj.data.Q), 2)) * ratio.Q * 10; % mean(abs(obj.data.Q), 2) * ratio.Q;
                    obj.sigma.P(isZeroInj) = 0;
                    obj.sigma.Q(isZeroInj) = 0;
                    obj.sigma.Vm = mean(abs(obj.data.Vm), 2) * ratio.Vm;
                    obj.sigma.Va = ones(obj.numBus, 1) * pi / 1800  * ratio.Va;
                otherwise
                    obj.sigma.P = mean(abs(obj.data.P), 2) * ratio.P;
                    obj.sigma.Q = mean(abs(obj.data.Q), 2) * ratio.Q;  
%                     obj.sigma.P = max(obj.sigma.P, ratio.Pmin * obj.sigma.P(1));
%                     obj.sigma.Q = max(obj.sigma.Q, ratio.Qmin * obj.sigma.Q(1));
                    obj.sigma.Vm = mean(abs(obj.data.Vm), 2) * ratio.Vm;
                    obj.sigma.Va = ones(obj.numBus, 1) * pi / 1800  * ratio.Va;
            end
            
%             obj.sigma.Va = mean(abs(obj.data.Va), 2) * ratio.Va;
            obj.sigma.Vm(1) = 0;
            obj.sigma.Va(1) = 0;

            % we generate the measurement noise
            rng(seed+1000);
            obj.data.P_noise = randn(obj.numBus, obj.numSnap);
            obj.data.P_noise = bsxfun(@times, obj.data.P_noise, obj.sigma.P);
            rng(seed+2000);
            obj.data.Q_noise = randn(obj.numBus, obj.numSnap);
            obj.data.Q_noise = bsxfun(@times, obj.data.Q_noise, obj.sigma.Q);
            rng(seed+3000);
            obj.data.Vm_noise = randn(obj.numBus, obj.numSnap);
            obj.data.Vm_noise = bsxfun(@times, obj.data.Vm_noise, obj.sigma.Vm);
            rng(seed+4000);
            obj.data.Va_noise = randn(obj.numBus, obj.numSnap);
            obj.data.Va_noise = bsxfun(@times, obj.data.Va_noise, obj.sigma.Va);
            
            % the measurement data
            obj.data.P_noised = obj.data.P + obj.data.P_noise;
            obj.data.Q_noised = obj.data.Q + obj.data.Q_noise;
            obj.data.Vm_noised = obj.data.Vm + obj.data.Vm_noise;
            obj.data.Va_noised = obj.data.Va + obj.data.Va_noise;
            
            % we calculate the noise of current injections
            obj.data.IP_noised = obj.data.P_noised ./ obj.data.Vm_noised;
            obj.data.IQ_noised = obj.data.Q_noised ./ obj.data.Vm_noised;
            obj.data.IP_noise = obj.data.IP_noised - obj.data.IP;
            obj.data.IQ_noise = obj.data.IQ_noised - obj.data.IQ;
            obj.sigma.IP = std(obj.data.IP_noise, 0, 2);
            obj.sigma.IQ = std(obj.data.IQ_noise, 0, 2);
            
            % in case we have some zero injections
            obj.sigma.P(obj.sigma.P==0) = mean(obj.sigma.P) * 1e-1;
            obj.sigma.Q(obj.sigma.Q==0) = mean(obj.sigma.Q) * 1e-1;
        end
        
        function obj = buildFIM(obj, varargin)
            % This method build the fisher information matrix (FIM). We
            % build the FIM in the order of measurement device or
            % measurement functions.
            if nargin == 2
                obj.k = varargin{1};
            elseif nargin == 1
                obj.k.G = 1;
                obj.k.B = 1;
                obj.k.vm = 1;
                obj.k.va = 1;
            end
            % initialize the FIM matrix
            obj.numFIM.G = (obj.numBus - 1) * obj.numBus / 2;
            obj.numFIM.B = (obj.numBus - 1) * obj.numBus / 2;
            obj.numFIM.Vm = obj.numSnap * (obj.numBus - 1); % exclude the source bus
            obj.numFIM.Va = obj.numSnap * (obj.numBus - 1);
            obj.numFIM.Sum = obj.numFIM.G + obj.numFIM.B + obj.numFIM.Vm + obj.numFIM.Va;
            
            %initialize the sparsify measurement matrix
            numVector = obj.numSnap * obj.numBus * ((obj.numBus-1)*4*2 + 2);
            obj.mRow = zeros(1, numVector);
            obj.mCol = zeros(1, numVector);
            obj.mVal = zeros(1, numVector);
            obj.spt = 1;
            
            % Initialize the idGB
            obj.idGB = zeros(obj.numBus, obj.numBus);
            id = 1;
            for i = 1:obj.numBus
                obj.idGB(i, i+1:end) = id:id+obj.numBus-i-1;
                obj.idGB(i+1:end, i) = id:id+obj.numBus-i-1;
                id = id+obj.numBus-i;
            end
            
%             obj.FIM = zeros(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.FIMP = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.FIMQ = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.FIMVm = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.FIMVa = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
            
            obj.numMeasure = obj.numSnap *...
                sum([obj.isMeasure.P;obj.isMeasure.Q;obj.isMeasure.Vm;obj.isMeasure.Va]);
%             obj.M = zeros(obj.numFIM.Sum, obj.numMeasure);
            pt = 1;
            % calculate the sub-matrix of P of all snapshots and all buses
            for j = 1:obj.numSnap
                % the id of Vm and Va
                obj.idVm = 2*(obj.numBus-1)*(j-1)+1 : 2*(obj.numBus-1)*(j-1)+obj.numBus-1;
                obj.idVa = 2*(obj.numBus-1)*(j-1)+obj.numBus : 2*(obj.numBus-1)*(j-1)+2*obj.numBus-2;
                for i = 1:obj.numBus
                    if obj.isMeasure.P(i)
%                         profile on;
                        obj = buildFIMP(obj, i, j, pt);
                        pt = pt + 1;
%                         profile off;
%                         profile viewer;
                    end
                end
            end
%             obj.FIM = obj.FIM + full(obj.FIMP);
            % calculate the sub-matrix of Q of all snapshots and all buses
            for j = 1:obj.numSnap
                % the id of Vm and Va
                obj.idVm = 2*(obj.numBus-1)*(j-1)+1 : 2*(obj.numBus-1)*(j-1)+obj.numBus-1;
                obj.idVa = 2*(obj.numBus-1)*(j-1)+obj.numBus : 2*(obj.numBus-1)*(j-1)+2*obj.numBus-2;
                for i = 1:obj.numBus
                    if obj.isMeasure.Q(i)
                        obj = buildFIMQ(obj, i, j, pt);
                        pt = pt + 1;
                    end
                end
            end
%             obj.FIM = obj.FIM + full(obj.FIMQ);
            % calculate the sub-matrix of Vm of all snapshots and all buses
            for j = 1:obj.numSnap
                % the id of Vm and Va
                obj.idVm = 2*(obj.numBus-1)*(j-1)+1 : 2*(obj.numBus-1)*(j-1)+obj.numBus-1;
                for i = 1:obj.numBus
                    if obj.isMeasure.Vm(i)
                        obj = buildFIMVm(obj, i, j, pt);
                        pt = pt + 1;
                    end
                end
            end
%             obj.FIM = obj.FIM + full(obj.FIMVm);
            % calculate the sub-matrix of Va of all snapshots and all buses
            for j = 1:obj.numSnap
                % the id of Vm and Va
                obj.idVa = 2*(obj.numBus-1)*(j-1)+obj.numBus : 2*(obj.numBus-1)*(j-1)+2*obj.numBus-2;
                for i = 1:obj.numBus
                    if obj.isMeasure.Va(i)
                        obj = buildFIMVa(obj, i, j, pt);
                        pt = pt + 1;
                    end
                end
            end
%             obj.FIM = obj.FIM + full(obj.FIMVa);
            obj.mRow(obj.spt:end) = [];
            obj.mCol(obj.spt:end) = [];
            obj.mVal(obj.spt:end) = [];
            obj.mVal(isnan(obj.mVal)) = 0;
            Ms = sparse(obj.mRow, obj.mCol, obj.mVal, obj.numFIM.Sum, obj.numMeasure);
%             Ms = sparse(obj.M);
            obj.FIM = Ms * Ms';
        end
        
        function obj = buildFIMP(obj, bus, snap, pt)
            % This method build the P part of FIM a selected bus and a selected snapshot. 
            % We first build a matrix, then we reshape the matrix to a vector. At
            % last we add up the FIM matrix. We conduct both G and B
            % matrix. Note that the state variables of G and B form a half
            % triangle, while the measurement function forms a whole
            % matrix.
            
            h = zeros(obj.numFIM.Sum, 1);
            theta_ij = obj.data.Va(bus, snap) - obj.data.Va(:, snap);
            Theta_ij = repmat(obj.data.Va(:, snap), 1, obj.numBus) - repmat(obj.data.Va(:, snap)', obj.numBus, 1);
            % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
            GBThetaP = obj.data.G .* cos(Theta_ij) + obj.data.B .* sin(Theta_ij);
            % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
            GBThetaQ = obj.data.G .* sin(Theta_ij) - obj.data.B .* cos(Theta_ij);
            
            % verify the PF calculation
            P = (GBThetaP * obj.data.Vm(:, snap)) .* obj.data.Vm(:, snap);
            deltaP = P - obj.data.P(:, snap);
            assert (sum(abs(deltaP)) <= 1e-6 );
            Q = (GBThetaQ * obj.data.Vm(:, snap)) .* obj.data.Vm(:, snap);
            deltaQ = Q - obj.data.Q(:, snap);
            assert (sum(abs(deltaQ)) <= 1e-6 );
 
%             % this code was used to test the scale of the noise
%             Theta_ij_ = repmat(obj.data.Va_noised(:, snap), 1, obj.numBus) - repmat(obj.data.Va_noised(:, snap)', obj.numBus, 1);
%             % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
%             GBThetaP_ = obj.data.G .* cos(Theta_ij_) + obj.data.B .* sin(Theta_ij_);
%             % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
%             GBThetaQ_ = obj.data.G .* sin(Theta_ij_) - obj.data.B .* cos(Theta_ij_);

%             P_ = (GBThetaP_ * obj.data.Vm_noised(:, snap)) .* obj.data.Vm_noised(:, snap);
%             deltaP_ = P_ - obj.data.P(:, snap);
%             obj.P_delta = [obj.P_delta deltaP_];
%             Q_ = (GBThetaQ_ * obj.data.Vm_noised(:, snap)) .* obj.data.Vm_noised(:, snap);
%             deltaQ_ = Q_ - obj.data.Q(:, snap);
%             obj.Q_delta = [obj.Q_delta deltaQ_];
            
            % G matrix
%             H_G = zeros(obj.numBus, obj.numBus);
            h_GG = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* cos(theta_ij') / obj.k.G;
            h_GG = h_GG -  obj.data.Vm(bus, snap)^2 / obj.k.G;
            h(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
%             H_G(bus, :) = h_GG;
%             h_G = obj.matToColDE(H_G);
%             assert (length(h_G) == obj.numFIM.G);
%             h(1:obj.numFIM.G) = h_G;
            
            % B matrix
%             H_B = zeros(obj.numBus, obj.numBus);
            h_BB = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* sin(theta_ij') / obj.k.B;
            h(obj.numFIM.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
%             H_B(bus, :) = h_BB;
%             h_B = obj.matToColDE(H_B);
%             assert (length(h_B) == obj.numFIM.B);
%             h(obj.numFIM.G+1:obj.numFIM.G+obj.numFIM.B) = h_B;
            
            % Vm
            % the first order term of other Vm
%             H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.data.Vm(bus, snap) * GBThetaP(:, bus) / obj.k.vm;
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.data.Vm(bus, snap) * GBThetaP(bus, bus) / obj.k.vm;
            % the first order term of Vm(bus)
            fOrderVm = obj.data.Vm(:, snap) .* GBThetaP(:, bus) / obj.k.vm;
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            h(obj.numFIM.G+obj.numFIM.B+obj.idVm) = h_Vm(2:end);
%             H_Vm(:, snap) = h_Vm;
            % remove the source bus whose magnitude is not the state variable
%             H_Vm(1, :) = []; 
%             h_VmLarge = reshape(H_Vm, [], 1);
%             h(obj.numFIM.G+obj.numFIM.B+1:obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm) = h_VmLarge;
            
            % Va
%             H_Va = zeros(obj.numBus, obj.numSnap);
            h_Va = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap) .* GBThetaQ(:, bus) / obj.k.va;
            h_Va(bus) = ( - obj.data.Vm(bus, snap)^2 * obj.data.B(bus, bus)...
                       - obj.data.Q(bus, snap)) / obj.k.va;
            h(obj.numFIM.G+obj.numFIM.B+obj.idVa) = h_Va(2:end);
%             H_Va(:, snap) = h_Va;
            % remove the source bus whose magnitude is not the state variable
%             H_Va(1, :) = []; 
%             h_VaLarge = reshape(H_Va, [], 1);
%             h(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1:end) = h_VaLarge;
            
            % build FIMP
            h = h / obj.sigma.P(bus);
            [row,col,val] = find(h);
            l = length(val);
            obj.mRow(obj.spt:obj.spt+l-1) = row;
            obj.mCol(obj.spt:obj.spt+l-1) = col*pt;
            obj.mVal(obj.spt:obj.spt+l-1) = val;
            obj.spt = obj.spt + l;
%             obj.M(:, pt) = h;
%             FIMPThis = h * h';
%             obj.FIMP = obj.FIMP + FIMPThis;
        end
        
        function obj = buildFIMQ(obj, bus, snap, pt)
            % This method build the Q part of FIM a selected bus and a selected snapshot. 
            
            h = zeros(obj.numFIM.Sum, 1);
            theta_ij = obj.data.Va(bus, snap) - obj.data.Va(:, snap);
            Theta_ij = repmat(obj.data.Va(:, snap), 1, obj.numBus) - repmat(obj.data.Va(:, snap)', obj.numBus, 1);
            % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
            GBThetaP = obj.data.G .* cos(Theta_ij) + obj.data.B .* sin(Theta_ij);
            % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
            GBThetaQ = obj.data.G .* sin(Theta_ij) - obj.data.B .* cos(Theta_ij);
            
            % G matrix
%             H_G = zeros(obj.numBus, obj.numBus);
            h_GG = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* sin(theta_ij') / obj.k.G;
            h(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
%             H_G(bus, :) = h_GG;
%             h_G = obj.matToColDE(H_G);
%             h(1:obj.numFIM.G) = h_G;
            
            % B matrix
%             H_B = zeros(obj.numBus, obj.numBus);
            h_BB =  - obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* cos(theta_ij') / obj.k.B;
            h_BB = h_BB + obj.data.Vm(bus, snap)^2 / obj.k.B; % the equivilance of diagonal elements
            h(obj.numFIM.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
%             H_B(bus, :) = h_BB;
%             h_B = obj.matToColDE(H_B);
%             h(obj.numFIM.G+1:obj.numFIM.G+obj.numFIM.B) = h_B;
            
            % Vm
            % the first order term of other Vm
%             H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.data.Vm(bus, snap) * GBThetaQ(:, bus) / obj.k.vm;
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.data.Vm(bus, snap) * GBThetaQ(bus, bus) / obj.k.vm;
            % the first order term of Vm(bus)
            fOrderVm = obj.data.Vm(:, snap) .* GBThetaQ(:, bus) / obj.k.vm;
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            h(obj.numFIM.G+obj.numFIM.B+obj.idVm) = h_Vm(2:end);
%             H_Vm(:, snap) = h_Vm;
%             % remove the source bus whose magnitude is not the state variable
%             H_Vm(1, :) = []; 
%             h_VmLarge = reshape(H_Vm, [], 1);
%             h(obj.numFIM.G+obj.numFIM.B+1:obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm) = h_VmLarge;
            
            % Va
%             H_Va = zeros(obj.numBus, obj.numSnap);
            h_Va = - obj.data.Vm(bus, snap) * obj.data.Vm(:, snap) .* GBThetaP(:, bus) / obj.k.va;
            h_Va(bus) = (- obj.data.Vm(bus, snap)^2 * obj.data.G(bus, bus) ...
                        + obj.data.P(bus, snap)) / obj.k.va;
            h(obj.numFIM.G+obj.numFIM.B+obj.idVa) = h_Va(2:end);
%             H_Va(:, snap) = h_Va;
            % remove the source bus whose magnitude is not the state variable
%             H_Va(1, :) = []; 
%             h_VaLarge = reshape(H_Va, [], 1);
%             h(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1:end) = h_VaLarge;
            
            % build FIMQ
            h = h / obj.sigma.Q(bus);
            [row,col,val] = find(h);
            l = length(val);
            obj.mRow(obj.spt:obj.spt+l-1) = row;
            obj.mCol(obj.spt:obj.spt+l-1) = col*pt;
            obj.mVal(obj.spt:obj.spt+l-1) = val;
            obj.spt = obj.spt + l;
%             FIMQThis = h * h';
%             obj.FIMQ = obj.FIMQ + FIMQThis;
        end
        
        function obj = buildFIMVm(obj, bus, ~, pt)
            % This method build the Vm part of FIM a selected bus. 
%             h = sparse(obj.numFIM.Sum, 1);
%             H_Vm = sparse(obj.numBus, obj.numSnap);
%             H_Vm(bus, snap) = 1 / obj.sigma.Vm(bus) / obj.k.vm;
%             % remove the source bus whose magnitude is not the state variable
%             H_Vm(1, :) = []; 
%             h_VmLarge = reshape(H_Vm, [], 1);
%             h(obj.numFIM.G+obj.numFIM.B+1:obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm) = h_VmLarge;
%             
% %             obj.M(:, pt) = h;
%             [col,row,val] = find(h');
            l = 1;
            obj.mRow(obj.spt:obj.spt+l-1) = obj.numFIM.G+obj.numFIM.B+obj.idVm(bus-1);
            obj.mCol(obj.spt:obj.spt+l-1) = pt;
            obj.mVal(obj.spt:obj.spt+l-1) = obj.sigma.Vm(bus).^(-1);
            obj.spt = obj.spt + l;
%             FIMVmThis = h * h';
%             obj.FIMVm = obj.FIMVm + FIMVmThis;
        end
        
        function obj = buildFIMVa(obj, bus, ~, pt)
            % This method build the Va part of FIM a selected bus. 
%             h = sparse(obj.numFIM.Sum, 1);
%             H_Va = sparse(obj.numBus, obj.numSnap);
%             H_Va(bus, snap) = 1 / obj.sigma.Va(bus) / obj.k.va;
%             % remove the source bus whose magnitude is not the state variable
%             H_Va(1, :) = []; 
%             h_VaLarge = reshape(H_Va, [], 1);
%             h(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1:end) = h_VaLarge;
%             
%             [col,row,val] = find(h');
            l = 1;
            obj.mRow(obj.spt:obj.spt+l-1) = obj.numFIM.G+obj.numFIM.B+obj.idVa(bus-1);
            obj.mCol(obj.spt:obj.spt+l-1) = pt;
            obj.mVal(obj.spt:obj.spt+l-1) = obj.sigma.Va(bus).^(-1);
            obj.spt = obj.spt + l;
%             obj.M(:, pt) = h;
%             FIMVaThis = h * h';
%             obj.FIMVa = obj.FIMVa + FIMVaThis;
        end
        
        function obj = calBound(obj, varargin)
            % this method calculate the bound from the FIM matrix;
            obj.isAnalyze = false; % we analyze the contribution
            if nargin == 3
                obj.sparseOption = varargin{1};
                obj.topoPrior = varargin{2};
            elseif nargin == 2
                obj.sparseOption = varargin{1};
                obj.topoPrior = false(obj.numBus, obj.numBus);
            elseif nargin == 1
                obj.sparseOption = true;
                obj.topoPrior = false(obj.numBus, obj.numBus);
            end
            
            % build the indexes we really care about
            delCols = [obj.matToColDE(obj.topoPrior)>1e-4;obj.matToColDE(obj.topoPrior)>1e-4];
            obj.numFIM.index = true(obj.numFIM.Sum, 1);
            obj.numFIM.index(delCols) = false;
            obj.numFIM.del = sum(delCols)/2;
            
            % for [A B; B' C], we calculate A-B/C*B'
            if obj.sparseOption
%                 profile on;
                
                idCell = 2*(obj.numBus-1) * ones(1, obj.numSnap);
                Cell = mat2cell(obj.FIM(obj.numFIM.index, obj.numFIM.index), ...
                    [obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del obj.numFIM.Vm+obj.numFIM.Va], ...
                    [obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del obj.numFIM.Vm+obj.numFIM.Va]);
%                 Cell{1,1} = full(Cell{1,1});
%                 Cell{1,2} = full(Cell{1,2});
                Cell{1,2} = mat2cell(Cell{1,2},...
                    obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del, idCell);
                Cell{2,2} = mat2cell(Cell{2,2}, ...
                    idCell, idCell);
                
                % get the inversion of Cell{2,2}, we separate it into a
                % single function
                Cell{2,2} = obj.cell2diag(Cell{2,2});
                % [D E; E' F]
                disp('calculating invC22');
                invC22 = cellfun(@inv, Cell{2,2},'UniformOutput',false);
                
                % calculate the inv(A-B/CB')
                disp('calculating (A-B/CB)^-1');
                BCB = obj.cellMulSum(Cell{1,2}, invC22, Cell{1,2});

                ABC = pinv(full(Cell{1,1}) - BCB); % inv(A-B/CB')
                diagABC = diag(ABC);
                % Calculate the diag of C
                diagC = obj.cellGetDiag(invC22);
                % Calculate the var
                var = [diagABC; diagC];
                % Analyze the contributions
                if obj.isAnalyze
                    obj = analyzeContribution(obj, full(Cell{1,1}), BCB);
                end
%                 profile off;
%                 profile viewer;
            else
                var = diag(full(obj.FIM(obj.numFIM.index, obj.numFIM.index))\eye(sum(obj.numFIM.index)));
%                 % use the svd method
%                 [u,s,v] = svd(obj.FIM);
%                 cov2 = v * diag(1./diag(s)) * u';
%                 var2 = diag(cov2);
            end
            if min(var) < 0
                var = abs(var);
                fprintf('We use the absolute value of the variance.\n');
            end
%             while min(var) < 0
%                 fprintf('The bound has negative value.');
%                 fprintf('The first var value is %f.\n', var(1))
%                 fprintf('We use the modified Cholesky decomposition instead.');
%                 
%                 try
%                     eigen = eig(obj.FIM);
%                     fprintf('The current tolerance is %f.\n', eigen(1)*obj.tol);
%                     U = chol(obj.FIM+abs(eigen(1)*obj.tol)*eye(size(obj.FIM)));
%                     Uinv = inv(U);
%                     var = diag(Uinv * Uinv');
%                 catch
%                     obj.tol = obj.tol * 1.1;
%                 end
%             end
            
%             [~,s,~] = svd(obj.FIM);
%             S = diag(s);
%             tol = S(end-50);
%             while min(var) < 0
%                 obj.bound.total = var;
%                 fprintf('The bound has negative value.\n');
%                 fprintf('We use pseudo inverse instead.\n');
%                 var = diag(pinv(obj.FIM, tol));
%                 tol = tol * 1.5;
%             end
            obj.bound.total = sqrt(var);
            obj.bound.total(obj.bound.total>obj.prior.Gmax) = obj.prior.Gmax;
            
            boundG = zeros(obj.numFIM.G, 1);
            boundG(obj.numFIM.index(1:obj.numFIM.G)) = obj.bound.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.bound.total(1:obj.numFIM.G-obj.numFIM.del) = obj.bound.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.bound.G = obj.colToMatDE(boundG, obj.numBus);
            
            boundB = zeros(obj.numFIM.B, 1);
            boundB(obj.numFIM.index(1:obj.numFIM.G)) = ...
                obj.bound.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.bound.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) = ...
                obj.bound.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.bound.B = obj.colToMatDE(boundB, obj.numBus);
            
            obj.bound.G_relative = abs(obj.bound.G ./ repmat(diag(obj.data.G), 1, obj.numBus));
            obj.bound.B_relative = abs(obj.bound.B ./ repmat(diag(obj.data.B), 1, obj.numBus));
            obj.bound.G_relative_col = reshape(obj.bound.G_relative, [], 1);
            obj.bound.B_relative_col = reshape(obj.bound.B_relative, [], 1);
            
            obj.bound.VmVa = reshape(obj.bound.total(obj.numFIM.G+obj.numFIM.B+1-2*obj.numFIM.del:end), 2*(obj.numBus-1), obj.numSnap);
            obj.bound.Vm = reshape(obj.bound.VmVa(1:obj.numBus-1, :), [], 1) / obj.k.vm;
            obj.bound.VmBus = mean(obj.bound.VmVa(1:obj.numBus-1, :), 2);
            obj.bound.Va = reshape(obj.bound.VmVa(obj.numBus:end, :), [], 1) / obj.k.vm;
            obj.bound.VaBus = mean(obj.bound.VmVa(obj.numBus:end, :), 2);
        end
        
        function obj = analyzeContribution(obj, A, B)
            % This function analyze the theoretical contribution between
            % two fisher information matrices A and B, the default is A-B
            [Va,Da] = eig(A,'nobalance');
            da = diag(Da);
            tempA = Va * Da * Va';
            trA = sum(1./da);
            [Vb,Db] = eig(B,'nobalance');
            db = diag(Db);
            trB = sum(1./db);
            Vab = Va'*Vb;
            impact = Vab * Db * Vab';
            result = Da - impact;
            
            [V,D] = eig(A-B,'nobalance');
            tr = sum(1./diag(D));
        end
        
        function obj = outputBound(obj)
            % this method output the bound to excel
            xlswrite(obj.addressOutput, obj.bound.total, 'total');
            xlswrite(obj.addressOutput, obj.bound.G, 'G');
            xlswrite(obj.addressOutput, obj.bound.B, 'B');
            xlswrite(obj.addressOutput, obj.bound.G_relative, 'G_relative');
            xlswrite(obj.addressOutput, obj.bound.B_relative, 'B_relative');
            if ~obj.sparseOption
                xlswrite(obj.addressOutput, obj.bound.Vm, 'Vm');
                xlswrite(obj.addressOutput, obj.bound.Va, 'Va');
            end
        end
        
        function obj = updateTopo(obj, varargin)
            % This method update the topology and calculate the bound again
            if nargin == 4
                obj.topoPrior = varargin{1};
                obj.topoTol = varargin{2};
                obj.sparseOption = varargin{3};
            elseif nargin == 3
                obj.topoPrior = varargin{1};
                obj.topoTol = varargin{2};
                obj.sparseOption = true;
            elseif nargin == 2
                obj.topoPrior = varargin{1};
                obj.topoTol = 0.05;
                obj.sparseOption = true;
            elseif nargin == 1
                obj.topoPrior = false(obj.numBus, obj.numBus);
                obj.topoTol = 0.05;
                obj.sparseOption = true;
            end
            numDisconnect = 1;
            % we should use measurement data to calculate the bound to
            % guarantee we don't disconnect some real branches
            while (numDisconnect > 1e-4)
                obj = calBound(obj, obj.sparseOption, obj.topoPrior);
                obj.boundIter = [obj.boundIter; obj.bound];
                diagEle = sum(abs(obj.data.G)) / 2;
                ratio1 = abs(bsxfun(@rdivide, obj.bound.G, diagEle));
                ratio2 = abs(bsxfun(@rdivide, obj.bound.G, diagEle'));
                ratio = min(ratio1, ratio2);
                topoPriorNext = ratio < obj.topoTol;
                topoPriorNext = obj.data.GBzero & topoPriorNext;
%                 topoPriorNext = obj.data.GBzero & (obj.bound.G_relative < obj.topoTol);
                numDisconnect = sum(sum(triu(topoPriorNext) - triu(obj.topoPrior)));
                fprintf('We disconnect %d branches\n', numDisconnect);
                obj.topoPrior = triu(topoPriorNext) | triu(topoPriorNext, -1)';
%                 obj.topoPrior = topoPriorNext;
            end
            obj.acc = sum(sum(obj.data.G~=0))/sum(sum(obj.bound.G~=0));
            fprintf('The theoretical topology identification limit is %f\n', obj.acc);
        end
        
        function obj = taylorFIM(obj, varargin)
            % This method use the taylor function to approximate the FIM,
            % given a small change
            if nargin == 2
                delta = varargin{1};
            elseif nargin == 1
                delta = 0.1;
            end
%             FIM1 = (1+delta * randn(size(obj.FIM))) .* obj.FIM;
            FIM1 = (1+delta) * obj.FIM;
            var1 = diag(FIM1(obj.numFIM.index, obj.numFIM.index)\eye(sum(obj.numFIM.index)));
            if min(var1) < 0
                var1 = abs(var1);
                fprintf('We use the absolute value of the variance.\n');
            end
            
            obj.bound1.total = sqrt(var1);
            boundG = zeros(obj.numFIM.G, 1);
            boundG(obj.numFIM.index(1:obj.numFIM.G)) = obj.bound1.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.bound1.total(1:obj.numFIM.G-obj.numFIM.del) = obj.bound1.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.bound1.G = colToMat(boundG, obj.numBus);
            
            boundB = zeros(obj.numFIM.B, 1);
            boundB(obj.numFIM.index(1:obj.numFIM.G)) = ...
                obj.bound1.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.bound1.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) = ...
                obj.bound1.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.bound1.B = colToMat(boundB, obj.numBus);
            
            obj.bound1.G_relative = abs(obj.bound1.G ./ repmat(diag(obj.data.G), 1, obj.numBus));
            obj.bound1.B_relative = abs(obj.bound1.B ./ repmat(diag(obj.data.B), 1, obj.numBus));
        end
        
    end
    
    methods (Static)
        function h = matToColDE(H)
            % This method transform the matrix into the column of the half
            % triangle. This method is only used as the matrix formulated
            % by rows. We add the upper and the lower part together because 
            % we have to derive the summation of the gradients. The name DE
            % denotes diagonal exclude, which means we consider the
            % diagonal elements as the negative summation of the rest elements.
%             H_up = tril(H, -1)'+triu(H);
%             n = size(H, 1);
%             trueMat = true(n, n);
%             trueMat = triu(trueMat, 1);
%             h = H_up(trueMat);
            
            H_up = tril(H, -1)'+triu(H);
            n = size(H, 1);
            N = (n - 1) * n / 2;
            h = zeros(N, 1);
            pt = 1;
            for i = 1:n
                h(pt:pt+n-i-1) = H_up(i, i+1:end);
                pt = pt+n-i;
            end
        end
        
        function h = matToCol(H)
            % This method transform the matrix into the column of the half
            % triangle. This method is only used as the matrix formulated
            % by rows. We add the upper and the lower part together because 
            % we have to derive the summation of the gradients.
            H_up = tril(H, -1)'+triu(H);
            n = size(H, 1);
            N = (n + 1) * n / 2;
            h = zeros(N, 1);
            pt = 1;
            for i = 1:n
                h(pt:pt+n-i) = H_up(i, i:end);
                pt = pt+n-i+1;
            end
        end
        
        function H = colToMat(h, n)
            % This method transform the column of half triangle to a
            % symmetric matrix
            H = zeros(n, n);
            pt = 1;
            for i = 1:n
                H(i, i:end) = h(pt:pt+n-i);
                pt = pt+n-i+1;
            end
            H = H + triu(H, 1)';
        end
        
        function H = colToMatDE(h, n)
            % This method transform the column of half triangle to a
            % symmetric matrix. The name DE denotes diagonal exclude.
            H = zeros(n, n);
            pt = 1;
            for i = 1:n
                H(i, i+1:end) = h(pt:pt+n-i-1);
                pt = pt+n-i;
            end
            H = H + triu(H, 1)';
            D = - diag(sum(H));
            H = H + D;
        end
        
        function Cout = cell2diag(Cin)
            % This method extracts the diagonal elements from the cell
            n = size(Cin, 1);
            Cout = cell(1, n);
            for i = 1:n
                Cout{i} = Cin{i, i};
            end
        end
        
        function Cout = diag2cell(Cout, Cin)
            % This method build the cell from the diagonal elements
            n = size(Cout, 1);
            for i = 1:n
                Cout{i,i} = Cin{i};
            end
        end
        
        function Mout = cellSum(Cin)
            % This method sum the matrices in the cell, it is row based
            n = size(Cin, 2);
            Mout = zeros(size(Cin{1}));
            for i = 1:n
                Mout = Mout + Cin{i};
            end
        end
        
        function Cout = cellMulSum(Ca, Cb, Cc)
            % This function do the multiplication and the summation of the
            % cells
            Snap = length(Ca);
            Branch = size(Ca{1},1);
            Cout = zeros(Branch);
            for i = 1:Snap
                Cout = Cout + full(Ca{i}) * full(Cb{i}) * full(Cc{i}');
            end
        end
        
        function diagEle = cellGetDiag(Cin)
            % This method get the diagonal elements from the Cin
            Snap = length(Cin);
            Bus = size(Cin{1,1}, 1);
            diagEle = zeros(Bus * Snap, 1);
            for i = 1:Snap
                diagEle((i-1)*Bus+1:i*Bus) = diag(full(Cin{i}));
            end
        end
    end
end

