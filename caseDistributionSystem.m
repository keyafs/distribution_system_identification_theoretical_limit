classdef caseDistributionSystem < handle
    % This is the class of distribution system
    
    properties
        caseName            % the name of the power system case
        mpc                 % the matpower struct of the power system
        numBus              % the number of bus
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
        bound1               % the bound with disturbance
        admittanceOnly      % only calculate the G and B bound
        k                   % the enlarge factor to maintain the numerical stability
        tol                 % the tolerance of the modified Cholesky decomposition
        
        topoPrior           % the prior topology knowledge (if two buses are disconnected) true-has topo prior
        topoTol             % the tolerance of topology identification (forcing the small value to zero)
        boundIter           % the iteration history of the bounds
        acc                 % the accuracy of topology identification
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
            isSuccess = ones(obj.numSnap, 1);
            
            for i = 1:obj.numSnap
                mpcThis = obj.mpc;
                % update active and reactive load
                mpcThis.bus(2:end,3) = mpcThis.bus(2:end,3) .* obj.loadP(:, i);
                mpcThis.bus(2:end,4) = mpcThis.bus(2:end,4) .* obj.loadQ(:, i);
                % run power flow
                mpopt = mpoption('verbose',0,'out.all',0);
                mpcThis = runpf(mpcThis, mpopt);
                isSuccess(i, 1) = mpcThis.success;
                % output the data
                inject = makeSbus(mpcThis.baseMVA, mpcThis.bus, mpcThis.gen);
                data_.P(:,i) = real(inject);
                data_.Q(:,i) = imag(inject);
                data_.Vm(:,i) = mpcThis.bus(:, 8);
                data_.Va(:,i) = mpcThis.bus(:, 9)/180*pi;
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
        
        function obj = setAccuracy(obj, varargin)
            % This method set the accuracy of the measurement device and
            % generate the measurement noise. This method also set whether
            % we have the measurement of a certain state.
            
            % we first set the relative noise ratio, we assume the noise
            % ratio is the sigma/mean value
            if nargin == 2
                ratio = varargin{1};
            elseif nargin == 1
                ratio.P = 0.005;
                ratio.Q = 0.005;
                ratio.Vm = 0.005; % 0.0000001 0.00001
                ratio.Va = 0.005;
            end
            % we then configure where are the measurement devices
            obj.isMeasure.P = true(obj.numBus, 1);
            obj.isMeasure.Q = true(obj.numBus, 1);
            obj.isMeasure.Vm = true(obj.numBus, 1);
            obj.isMeasure.Va = true(obj.numBus, 1); % false
            obj.isMeasure.Vm(1) = false;
            obj.isMeasure.Va(1) = false;
            % Set the tolerance of the modified Cholesky decomposition
            if any(obj.isMeasure.Va) % we have the measurement of Va
                obj.tol = 0.45;
            else
                obj.tol = 0.77;
            end
            % We assume there is no noise in the source bus. We set the
            % enlarge ratio of each rows of measurement noise.
            obj.sigma.P = max(abs(obj.data.P),[], 2) * ratio.P; %  mean(abs(obj.data.P), 2) * ratio.P;
            obj.sigma.Q = max(abs(obj.data.Q),[], 2) * ratio.Q; % mean
            obj.sigma.P = max(obj.sigma.P, ratio.Pmin * obj.sigma.P(1));
            obj.sigma.Q = max(obj.sigma.Q, ratio.Qmin * obj.sigma.Q(1));
            obj.sigma.Vm = mean(abs(obj.data.Vm), 2) * ratio.Vm;
            obj.sigma.Va = ones(obj.numBus, 1) * pi / 1800  * ratio.Va;
%             obj.sigma.Va = mean(abs(obj.data.Va), 2) * ratio.Va;
            obj.sigma.Vm(1) = 0;
            obj.sigma.Va(1) = 0;
            
            % we generate the measurement noise
            rng(1);
            obj.data.P_noise = randn(obj.numBus, obj.numSnap);
            obj.data.P_noise = bsxfun(@times, obj.data.P_noise, obj.sigma.P);
            rng(2);
            obj.data.Q_noise = randn(obj.numBus, obj.numSnap);
            obj.data.Q_noise = bsxfun(@times, obj.data.Q_noise, obj.sigma.Q);
            rng(3);
            obj.data.Vm_noise = randn(obj.numBus, obj.numSnap);
            obj.data.Vm_noise = bsxfun(@times, obj.data.Vm_noise, obj.sigma.Vm);
            rng(4);
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
        end
        
        function obj = buildFIM(obj, varargin)
            % This method build the fisher information matrix (FIM). We
            % build the FIM in the order of measurement device or
            % measurement functions.
            if nargin == 2
                obj.k = varargin{1};
            elseif nargin == 1
                obj.k.G = 5;
                obj.k.B = 10;
                obj.k.vm = 10;
                obj.k.va = 1000;
            end
            % initialize the FIM matrix
            obj.numFIM.G = (1 + obj.numBus) * obj.numBus / 2;
            obj.numFIM.B = (1 + obj.numBus) * obj.numBus / 2;
            obj.numFIM.Vm = obj.numSnap * (obj.numBus - 1); % exclude the source bus
            obj.numFIM.Va = obj.numSnap * (obj.numBus - 1);
            obj.numFIM.Sum = obj.numFIM.G + obj.numFIM.B + obj.numFIM.Vm + obj.numFIM.Va;
            
            obj.FIM = zeros(obj.numFIM.Sum, obj.numFIM.Sum);
            obj.FIMP = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
            obj.FIMQ = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
            obj.FIMVm = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
            obj.FIMVa = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
            
            % calculate the sub-matrix of P of all snapshots and all buses
            for i = 1:obj.numBus
                if obj.isMeasure.P(i)
                    for j = 1:obj.numSnap
                        obj = buildFIMP(obj, i, j);
                    end
                end
            end
            obj.FIM = obj.FIM + full(obj.FIMP);
            % calculate the sub-matrix of Q of all snapshots and all buses
            for i = 1:obj.numBus
                if obj.isMeasure.Q(i)
                    for j = 1:obj.numSnap
                        obj = buildFIMQ(obj, i, j);
                    end
                end
            end
            obj.FIM = obj.FIM + full(obj.FIMQ);
            % calculate the sub-matrix of Vm of all snapshots and all buses
            for i = 1:obj.numBus
                if obj.isMeasure.Vm(i)
                    for j = 1:obj.numSnap
                        obj = buildFIMVm(obj, i, j);
                    end
                end
            end
            obj.FIM = obj.FIM + full(obj.FIMVm);
            % calculate the sub-matrix of Va of all snapshots and all buses
            for i = 1:obj.numBus
                if obj.isMeasure.Va(i)
                    for j = 1:obj.numSnap
                        obj = buildFIMVa(obj, i, j);
                    end
                end
            end
            obj.FIM = obj.FIM + full(obj.FIMVa);
        end
        
        function obj = buildFIMP(obj, bus, snap)
            % This method build the P part of FIM a selected bus and a selected snapshot. 
            % We first build a matrix, then we reshape the matrix to a vector. At
            % last we add up the FIM matrix. We conduct both G and B
            % matrix. Note that the state variables of G and B form a half
            % triangle, while the measurement function forms a whole
            % matrix.
            
            h = sparse(obj.numFIM.Sum, 1);
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
            
            % G matrix
            H_G = zeros(obj.numBus, obj.numBus);
            H_G(bus, :) = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* cos(theta_ij') / obj.k.G;
            h_G = obj.matToCol(H_G);
            assert (length(h_G) == obj.numFIM.G);
            h(1:obj.numFIM.G) = h_G;
            
            % B matrix
            H_B = zeros(obj.numBus, obj.numBus);
            H_B(bus, :) = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* sin(theta_ij') / obj.k.B;
            h_B = obj.matToCol(H_B);
            assert (length(h_B) == obj.numFIM.B);
            h(obj.numFIM.G+1:obj.numFIM.G+obj.numFIM.B) = h_B;
            
            % Vm
            % the first order term of other Vm
            H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.data.Vm(bus, snap) * GBThetaP(:, bus) / obj.k.vm;
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.data.Vm(bus, snap) * GBThetaP(bus, bus) / obj.k.vm;
            % the first order term of Vm(bus)
            fOrderVm = obj.data.Vm(:, snap) .* GBThetaP(:, bus) / obj.k.vm;
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            H_Vm(:, snap) = h_Vm;
            % remove the source bus whose magnitude is not the state variable
            H_Vm(1, :) = []; 
            h_VmLarge = reshape(H_Vm', [], 1);
            h(obj.numFIM.G+obj.numFIM.B+1:obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm) = h_VmLarge;
            
            % Va
            H_Va = zeros(obj.numBus, obj.numSnap);
            h_Va = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap) .* GBThetaQ(:, bus) / obj.k.va;
            h_Va(bus) = h_Va(bus)-sum(obj.data.Vm(bus, snap) * obj.data.Vm(:, snap) .* GBThetaQ(:, bus)) / obj.k.va;
            H_Va(:, snap) = h_Va;
            % remove the source bus whose magnitude is not the state variable
            H_Va(1, :) = []; 
            h_VaLarge = reshape(H_Va', [], 1);
            h(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1:end) = h_VaLarge;
            
            % build FIMP
            h = h / obj.sigma.P(bus);
            FIMPThis = h * h';
            obj.FIMP = obj.FIMP + FIMPThis;
        end
        
        function obj = buildFIMQ(obj, bus, snap)
            % This method build the Q part of FIM a selected bus and a selected snapshot. 
            
            h = sparse(obj.numFIM.Sum, 1);
            theta_ij = obj.data.Va(bus, snap) - obj.data.Va(:, snap);
            Theta_ij = repmat(obj.data.Va(:, snap), 1, obj.numBus) - repmat(obj.data.Va(:, snap)', obj.numBus, 1);
            % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
            GBThetaP = obj.data.G .* cos(Theta_ij) + obj.data.B .* sin(Theta_ij);
            % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
            GBThetaQ = obj.data.G .* sin(Theta_ij) - obj.data.B .* cos(Theta_ij);
            
            % G matrix
            H_G = zeros(obj.numBus, obj.numBus);
            H_G(bus, :) = obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* sin(theta_ij') / obj.k.G;
            h_G = obj.matToCol(H_G);
            h(1:obj.numFIM.G) = h_G;
            
            % B matrix
            H_B = zeros(obj.numBus, obj.numBus);
            H_B(bus, :) = - obj.data.Vm(bus, snap) * obj.data.Vm(:, snap)' .* cos(theta_ij') / obj.k.B;
            h_B = obj.matToCol(H_B);
            h(obj.numFIM.G+1:obj.numFIM.G+obj.numFIM.B) = h_B;
            
            % Vm
            % the first order term of other Vm
            H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.data.Vm(bus, snap) * GBThetaQ(:, bus) / obj.k.vm;
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.data.Vm(bus, snap) * GBThetaQ(bus, bus) / obj.k.vm;
            % the first order term of Vm(bus)
            fOrderVm = obj.data.Vm(:, snap) .* GBThetaQ(:, bus) / obj.k.vm;
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            H_Vm(:, snap) = h_Vm;
            % remove the source bus whose magnitude is not the state variable
            H_Vm(1, :) = []; 
            h_VmLarge = reshape(H_Vm', [], 1);
            h(obj.numFIM.G+obj.numFIM.B+1:obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm) = h_VmLarge;
            
            % Va
            H_Va = zeros(obj.numBus, obj.numSnap);
            h_Va = - obj.data.Vm(bus, snap) * obj.data.Vm(:, snap) .* GBThetaP(:, bus) / obj.k.va;
            h_Va(bus) = h_Va(bus)+sum(obj.data.Vm(bus, snap) * obj.data.Vm(:, snap) .* GBThetaP(:, bus)) / obj.k.va;
            H_Va(:, snap) = h_Va;
            % remove the source bus whose magnitude is not the state variable
            H_Va(1, :) = []; 
            h_VaLarge = reshape(H_Va', [], 1);
            h(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1:end) = h_VaLarge;
            
            % build FIMQ
            h = h / obj.sigma.Q(bus);
            FIMQThis = h * h';
            obj.FIMQ = obj.FIMQ + FIMQThis;
        end
        
        function obj = buildFIMVm(obj, bus, snap)
            % This method build the Vm part of FIM a selected bus. 
            h = sparse(obj.numFIM.Sum, 1);
            H_Vm = sparse(obj.numBus, obj.numSnap);
            H_Vm(bus, snap) = 1 / obj.sigma.Vm(bus) / obj.k.vm;
            % remove the source bus whose magnitude is not the state variable
            H_Vm(1, :) = []; 
            h_VmLarge = reshape(H_Vm', [], 1);
            h(obj.numFIM.G+obj.numFIM.B+1:obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm) = h_VmLarge;
            
            FIMVmThis = h * h';
            obj.FIMVm = obj.FIMVm + FIMVmThis;
        end
        
        function obj = buildFIMVa(obj, bus, snap)
            % This method build the Va part of FIM a selected bus. 
            h = sparse(obj.numFIM.Sum, 1);
            H_Va = sparse(obj.numBus, obj.numSnap);
            H_Va(bus, snap) = 1 / obj.sigma.Va(bus) / obj.k.va;
            % remove the source bus whose magnitude is not the state variable
            H_Va(1, :) = []; 
            h_VaLarge = reshape(H_Va', [], 1);
            h(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1:end) = h_VaLarge;
            
            FIMVaThis = h * h';
            obj.FIMVa = obj.FIMVa + FIMVaThis;
        end
        
        function obj = calBound(obj, varargin)
            % this method calculate the bound from the FIM matrix;

            if nargin == 3
                obj.admittanceOnly = varargin{1};
                obj.topoPrior = varargin{2};
            elseif nargin == 2
                obj.admittanceOnly = varargin{1};
                obj.topoPrior = false(obj.numBus, obj.numBus);
            elseif nargin == 1
                obj.admittanceOnly = false;
                obj.topoPrior = false(obj.numBus, obj.numBus);
            end
            
            % build the indexes we really care about
            delCols = [obj.matToCol(obj.topoPrior)>1e-4;obj.matToCol(obj.topoPrior)>1e-4];
            obj.numFIM.index = true(obj.numFIM.Sum, 1);
            obj.numFIM.index(delCols) = false;
            obj.numFIM.del = sum(delCols)/2;
            
            % for [A B; B' C], we calculate A-B/C*B'
            if obj.admittanceOnly
                obj.numFIM.index = obj.numFIM.index(1:obj.numFIM.G+obj.numFIM.B);
                A = obj.FIM(1:obj.numFIM.G+obj.numFIM.B, 1:obj.numFIM.G+obj.numFIM.B);
                B = obj.FIM(1:obj.numFIM.G+obj.numFIM.B, obj.numFIM.G+obj.numFIM.B+1:end);
                C = obj.FIM(obj.numFIM.G+obj.numFIM.B+1:end, obj.numFIM.G+obj.numFIM.B+1:end);
                obj.FIM = A - B/C*B';
                var = diag(obj.FIM(obj.numFIM.index, obj.numFIM.index)\eye(sum(obj.numFIM.index)));
            else
                var = diag(obj.FIM(obj.numFIM.index, obj.numFIM.index)\eye(sum(obj.numFIM.index)));
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
            
            boundG = zeros(obj.numFIM.G, 1);
            boundG(obj.numFIM.index(1:obj.numFIM.G)) = obj.bound.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.bound.total(1:obj.numFIM.G-obj.numFIM.del) = obj.bound.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.bound.G = obj.colToMat(boundG, obj.numBus);
            
            boundB = zeros(obj.numFIM.B, 1);
            boundB(obj.numFIM.index(1:obj.numFIM.G)) = ...
                obj.bound.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.bound.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) = ...
                obj.bound.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.bound.B = obj.colToMat(boundB, obj.numBus);
            
            obj.bound.G_relative = abs(obj.bound.G ./ repmat(diag(obj.data.G), 1, obj.numBus));
            obj.bound.B_relative = abs(obj.bound.B ./ repmat(diag(obj.data.B), 1, obj.numBus));
            obj.bound.G_relative_col = reshape(obj.bound.G_relative, [], 1);
            obj.bound.B_relative_col = reshape(obj.bound.B_relative, [], 1);
            
            if ~obj.admittanceOnly
                obj.bound.Vm = ...
                    obj.bound.total(obj.numFIM.G+obj.numFIM.B+1-2*obj.numFIM.del...
                    :obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm-2*obj.numFIM.del) / obj.k.vm;
                obj.bound.total(obj.numFIM.G+obj.numFIM.B+1-2*obj.numFIM.del...
                    :obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm-2*obj.numFIM.del)...
                    = obj.bound.Vm;
                obj.bound.Va = ...
                    obj.bound.total(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1-2*obj.numFIM.del...
                    :obj.numFIM.Sum-2*obj.numFIM.del) / obj.k.va;
                obj.bound.total(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1-2*obj.numFIM.del...
                    :obj.numFIM.Sum-2*obj.numFIM.del)...
                    = obj.bound.Va;
            end
        end
        
        function obj = outputBound(obj)
            % this method output the bound to excel
            xlswrite(obj.addressOutput, obj.bound.total, 'total');
            xlswrite(obj.addressOutput, obj.bound.G, 'G');
            xlswrite(obj.addressOutput, obj.bound.B, 'B');
            xlswrite(obj.addressOutput, obj.bound.G_relative, 'G_relative');
            xlswrite(obj.addressOutput, obj.bound.B_relative, 'B_relative');
            if ~obj.admittanceOnly
                xlswrite(obj.addressOutput, obj.bound.Vm, 'Vm');
                xlswrite(obj.addressOutput, obj.bound.Va, 'Va');
            end
        end
        
        function obj = updateTopo(obj, varargin)
            % This method update the topology and calculate the bound again
            if nargin == 3
                obj.topoTol = varargin{1};
                obj.admittanceOnly = varargin{2};
            elseif nargin == 2
                obj.topoTol = varargin{1};
                obj.admittanceOnly = false;
            elseif nargin == 1
                obj.topoTol = 0.05;
                obj.admittanceOnly = false;
            end
            obj.topoPrior = false(obj.numBus, obj.numBus);
            numDisconnect = 1;
            % we should use measurement data to calculate the bound to
            % guarantee we don't disconnect some real branches
            while (numDisconnect > 1e-4)
                obj = calBound(obj, obj.admittanceOnly, obj.topoPrior);
                obj.boundIter = [obj.boundIter; obj.bound];
                topoPriorNext = obj.data.GBzero & (obj.bound.G_relative < obj.topoTol);
                numDisconnect = sum(sum(triu(topoPriorNext) - triu(obj.topoPrior)));
                fprintf('We disconnect %d branches\n', numDisconnect);
                obj.topoPrior = triu(topoPriorNext) | triu(topoPriorNext, -1)';
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
        
        function h = matToCol(H)
            % this method transform the matrix into the column of the half
            % triangle.
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
    end
end

