classdef caseDistributionSystem
    % This is the class of distribution system
    
    properties
        caseName            % the name of the power system case
        mpc                 % the matpower struct of the power system
        numBus              % the number of bus
        numSnap             % the number of snapshot
        range               % % the deviation range
        
        addressLoadRaw      % the address of raw load data
        addressLoad         % the address of preprocessed load data
        
        loadP               % the active load of each bus
        loadQ               % the reactive load of each bus
        
        data                % the data struct contains operation data
        sigma               % the variance of each meansurement noise
        isMeasure           % whether we have a specific measurement device
    end
    
    methods
        function obj = caseDistributionSystem(caseName, numSnap, range)
            % the construction function
            obj.caseName = caseName;
            obj.addressLoadRaw = '.\data\file1csv.csv';
            obj.addressLoad = '.\data\dataLoad.csv';
            
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
            numAggregation = 5;     % aggregate serveral loads together
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
            load = 1 - obj.range.P/2 + load*obj.range.P;
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
                data_.P(:,i) = mpcThis.bus(:, 3);
                data_.Q(:,i) = mpcThis.bus(:, 4);
                data_.Vm(:,i) = mpcThis.bus(:, 8);
                data_.Va(:,i) = mpcThis.bus(:, 9)/180*pi;
            end
            
            % assert that all the power flow converge
            assert(isempty(find(isSuccess == 0, 1)));
            obj.data = data_;
        end
        
        function obj = setAccuracy(obj)
            % This method set the accuracy of the measurement device and
            % generate the measurement noise. This method also set whether
            % we have the measurement of a certain state.
            
            % we first set the relative noise ratio, we assume the noise
            % ratio is the sigma/mean value
            ratio.P = 0.005;
            ratio.Q = 0.005;
            ratio.Vm = 0.001;
            ratio.Va = 0.001;
            % we then have to set whether we have the measurement device
            obj.isMeasure.P = true(obj.numBus, 1);
            obj.isMeasure.Q = true(obj.numBus, 1);
            obj.isMeasure.Vm = true(obj.numBus, 1);
            obj.isMeasure.Va = false(obj.numBus, 1);
            
            % We assume there is no noise in the source bus. We set the
            % enlarge ratio of each rows of measurement noise.
            obj.sigma.P = mean(abs(obj.data.P), 2) * ratio.P;
            obj.sigma.Q = mean(abs(obj.data.Q), 2) * ratio.Q;
            obj.sigma.Vm = mean(abs(obj.data.Vm), 2) * ratio.Vm;
            obj.sigma.Va = mean(abs(obj.data.Vm), 2) * ratio.Vm;
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
        end
        
        function obj = buildFIM(obj)
            % This method build the fisher information matrix (FIM). We
            % build the FIM in the order of measurement device or
            % measurement functions.
            
        end
    end
end

