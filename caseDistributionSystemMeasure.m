classdef caseDistributionSystemMeasure < caseDistributionSystem
    % This is the class of distribution system. We assume all the
    % evaluations are conducted under practical measurements
    
    properties
        dataE               % the estimated data
        dataO               % the process data in the optimization iterations
        boundA              % the approximated bound
        sigmaReal           % the deviation of the real state variables
        prior               % the prior assumptions of the G and B matrix
        
        A_FIM               % the approximated fisher information matrix
        A_FIMP              % the (sparse) FIM of active power injection
        A_FIMQ              % the (sparse) FIM of reactive power injection
        
        initPar             % the initial estimation of parameters and state variables
        truePar             % the ground truth of the parameters
        
        grad                % the gradient vector
        gradChain           % the chain of the gradients
        gradP               % the gradient vector from the measurement of P
        gradQ               % the gradient vector from the measurement of Q
        gradVm              % the gradient vector from the measurement of Vm
        gradVa              % the gradient vector from the measurement of Va
        numGrad             % the number of the gradient elements
        loss                % the sum-of-squares loss function
        lossChain           % the chain of the loss functions
        parChain            % the chain of the parameters
        
        kZero               % the ratio that we set nondiagonal elements to zero
        maxIter             % the maximum iteration in the gradient-based methods
        step                % the step length of the iterations
        stepInit            % the initial step
        stepMin             % the minimum step length
        stepMax             % the maximum step length
        stepChain           % the chain of the step length
        iter                % the current iteration step
        updateStepFreq      % the frequency to update the step length
        
        momentRatio         % the part we maintain from the past gradient
        momentRatioMax      % the maximum momentRatio
        momentRatioMin      % the minimum momentRatio
        vmvaWeight          % the additional weight to the vm and va
        isConverge          % if the iteration concerges
        isGB                % whether to iterate the GB part
        
        H                   % the Hessian matrix
        HP                  % the P part
        HQ                  % the Q part
        HVm                 % the Vm part
        HVa                 % the Va part
        
        J                   % the Jacobian matrix
        Topo                % the topology matrix
        Tvec                % the topology vector
        thsTopo             % the threshold of Topology
        
        lambda              % the damping ratio of LM algorithm
        lambdaMax           % the maximum value
        lambdaMin           % the minimum value
        lambdaChain         % the chain of lambda ratio, the first order ratio
        gradOrigin          % the original gradient in LM algorithm
        gradPast            % the gradient of the last step
        lossMin             % the theoretical minimum loss
        momentLoss          % the moment of loss
        ratioMax            % the ratio of second order / first order (final value)
        ratioMaxMax         % the maximum of ratioMax
        ratioMaxMin         % the minimum of ratioMin
        ratioMaxChain       % the chain of ratioMax
        ratioChain          % the chain of ratio
        lambdaCompen        % the additional compensate when second order is too large
        
%         idGB                % the address of G and B matrix
%         idVmVa              % the id of Vm and Va
        isBoundChain        % if attain the bound that Hessian is too large
        deRatio             % ratio of step and lambda when loss decreases
        inRatio             % ratio of step and lambda when loss increases
        
        isSecond            % the mode of second order
        isFirst             % whether we force the mode to be the first order
        lastState           % we temporally save the last state for the second order mode
        regretRatio         % the regret ratio in the second mode
        second              % the absolute proportion of second order
        secondChain         % the chain of second
        secondMax           % the maximum value of second
        secondMin           % the minimum value of second
        
        tuneGrad            % whether tune grad
        boundTuned          % the tuned bound
        ratioMaxConst       % the constant of ratio max
        
        err                 % the evaluation errors
        vaPseudoWeight      % the enlarge sigma of the va pseudo measurement
        vaPseudoWeightInit  % the initial value of vaPseudoWeight
        vaPseudoMax         % the maximum value of vaPseudoWeight
        vaPseudoMin         % the minimum value of vaPseudoWeight
        startPF             % the loss value to start PF calculation log10(loss/lossMin)
        maxD2Chain          % the chain of maxD2
        maxD2Upper          % the upper bound of maxD2
        maxD2Lower          % the lower bound of maxD2
        D2D1Chain           % the chain of D2/D1
        
        updateStart         % the start iteration number to update the topology
        updateStep          % the number of steps we calculate the judge whether stop iteration
        updateRatio         % the long term ratio and the short term ratio to stop iteration
        updateLast          % the last update step
        updateLastLoss      % the last loss function
        updateRatioLast     % the last topology update ratio
        
        isLBFGS             % whether we use the LBFGS method or the newton method
        numStore            % the number of parameters we want to store in our memory
        numEstH             % the number of history we use to estimate the H
        sChain              % the Chain of s_k = x_k+1 - x_k
        yChain              % the Chain of y_k = g_k+1 - g_k
        rhoChain            % the Chain of rho_k = 1/(y_k^T * s_k)
        
        isLHinv             % whether we use the low memory version to get the inverse
        isPHinv             % whether we use the pseudo inverse
        isIll               % whether it is ill-conditioned
        
        ls_c                % the c value of line search c*alpha*g'*d
        ls_alpha            % the alpha ratio of line search c*alpha*g'*d
        ls_maxTry           % the maximum try numbers of the line search
    end
    
    methods
        function obj = caseDistributionSystemMeasure(caseName, numSnap, range)
            % the construction function
            obj = obj@caseDistributionSystem(caseName, numSnap, range);
        end
        
        function obj = preEvaluation(obj, varargin)
            % This method evaluate the parameters before approximating the
            % FIM. The evaluated value has low accuracy. We only use one
            % snapshot for the Vm and Va.
            
            if nargin == 2
                obj.prior = varargin{1};
            elseif nargin == 1
                obj.prior.Gmin = 0.1;
                obj.prior.Bmin = 0.1;
                obj.prior.ratio = 0.05;
                obj.prior.Gmax = 1000;
                obj.prior.Bmax = 1000;
            end
            
            % we first evaluate the vm and the va
%             obj.dataE.Vm = obj.data.Vm;%_noised;
%             obj.dataE.Va = obj.data.Va;%_noised;

            obj.sigmaReal.Vm = cov(obj.data.Vm');
            mu = mean(obj.data.Vm, 2);
            rng(5);
            obj.dataE.Vm = mvnrnd(mu, obj.sigmaReal.Vm, obj.numSnap)';
            
            obj.sigmaReal.Va = cov(obj.data.Va');
            mu = mean(obj.data.Va, 2);
            rng(6);
            obj.dataE.Va = mvnrnd(mu, obj.sigmaReal.Va, obj.numSnap)';
            
%             obj.dataE.Vm = obj.data.Vm;%_noised;
            
            % We then evaluate the G and B. 
%             obj.dataE.G = obj.data.G;
%             obj.dataE.B = obj.data.B;
            
            obj = approximateY(obj);
            
            obj.dataE.Va = zeros(obj.numBus, obj.numSnap);
            obj.dataE.Va(2:end, :) = - pinv(obj.dataE.G(2:end, 2:end)) * obj.data.P_noised(2:end, :);
            if any(any(isnan(obj.dataE.Va)))
                obj.dataE.Va = zeros(obj.numBus, obj.numSnap);
            end
%             mu = mean(obj.data.Va, 2);
%             obj.sigmaReal.P = cov(obj.data.P');
%             obj.sigmaReal.Va = zeros(obj.numBus, obj.numBus);
%             obj.sigmaReal.Va(2:end, 2:end) = ...
%                 ((1.5*obj.dataE.G(2:end, 2:end)) \ obj.sigmaReal.P(2:end, 2:end)) / (1.5*obj.dataE.G(2:end, 2:end));
%             rng(7);
%             obj.dataE.Va = mvnrnd(mu, obj.sigmaReal.Va, obj.numSnap)';
%             obj.dataE.Va(2:end, :) = -obj.dataE.G(2:end, 2:end) \ obj.data.P_noised(2:end, :);
        end
        
        function obj = approximateFIM(obj, varargin)
            % This method approximate the fisher information matrix based
            % on the pre-evaluation results of the parameters.
            if nargin == 2
                obj.k = varargin{1};
            elseif nargin == 1
                obj.k.G = 5;
                obj.k.B = 10;
                obj.k.vm = 10;
                obj.k.va = 1000;
            end
            % initialize the A_FIM matrix
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
            
            obj.numMeasure = obj.numSnap *...
                sum([obj.isMeasure.P;obj.isMeasure.Q;obj.isMeasure.Vm;obj.isMeasure.Va]);
%             obj.M = zeros(obj.numFIM.Sum, obj.numMeasure);
%             obj.A_FIM = zeros(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.A_FIMP = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.A_FIMQ = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.FIMVm = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
%             obj.FIMVa = sparse(obj.numFIM.Sum, obj.numFIM.Sum);
            
            pt = 1;
            % calculate the sub-matrix of P of all snapshots and all buses
            for j = 1:obj.numSnap
                % the id of Vm and Va
                obj.idVm = 2*(obj.numBus-1)*(j-1)+1 : 2*(obj.numBus-1)*(j-1)+obj.numBus-1;
                obj.idVa = 2*(obj.numBus-1)*(j-1)+obj.numBus : 2*(obj.numBus-1)*(j-1)+2*obj.numBus-2;
                for i = 1:obj.numBus
                    if obj.isMeasure.P(i)
%                         profile on
                        obj = approximateFIMP(obj, i, j, pt);
                        pt = pt + 1;
%                         profile off
%                         profile viewer
                    end
                end
            end
%             obj.A_FIM = obj.A_FIM + full(obj.A_FIMP);
            % calculate the sub-matrix of Q of all snapshots and all buses
            for j = 1:obj.numSnap
                % the id of Vm and Va
                obj.idVm = 2*(obj.numBus-1)*(j-1)+1 : 2*(obj.numBus-1)*(j-1)+obj.numBus-1;
                obj.idVa = 2*(obj.numBus-1)*(j-1)+obj.numBus : 2*(obj.numBus-1)*(j-1)+2*obj.numBus-2;
                for i = 1:obj.numBus
                    if obj.isMeasure.Q(i)
                        obj = approximateFIMQ(obj, i, j, pt);
                        pt = pt + 1;
                    end
                end
            end
%             obj.A_FIM = obj.A_FIM + full(obj.A_FIMQ);
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
%             obj.A_FIM = obj.A_FIM + full(obj.FIMVm);
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
%             obj.A_FIM = obj.A_FIM + full(obj.FIMVa);
            obj.mRow(obj.spt:end) = [];
            obj.mCol(obj.spt:end) = [];
            obj.mVal(obj.spt:end) = [];
            obj.mVal(isnan(obj.mVal)) = 0;
            Ms = sparse(obj.mRow, obj.mCol, obj.mVal, obj.numFIM.Sum, obj.numMeasure);
%             Ms = sparse(obj.M);
            obj.A_FIM = Ms * Ms';
        end
        
        function obj = approximateFIMP(obj, bus, snap, pt)
            % This method approximate the P part of FIM. We ignore the sin
            % part of the power flow equations.
            h = zeros(obj.numFIM.Sum, 1);
            theta_ij = obj.dataE.Va(bus, snap) - obj.dataE.Va(:, snap);
%             Theta_ij = repmat(obj.dataE.Va(:, snap), 1, obj.numBus) - repmat(obj.dataE.Va(:, snap)', obj.numBus, 1);
%             % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
%             GBThetaP = obj.dataE.G .* cos(Theta_ij) + obj.dataE.B .* sin(Theta_ij);
%             % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
%             GBThetaQ = obj.dataE.G .* sin(Theta_ij) - obj.dataE.B .* cos(Theta_ij);
            
            % G matrix
%             H_G = zeros(obj.numBus, obj.numBus);
            h_GG = obj.dataE.Vm(bus, snap) * obj.dataE.Vm(:, snap)' / obj.k.G;
            h_GG = h_GG -  obj.dataE.Vm(bus, snap)^2 / obj.k.G;
            h(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
%             H_G(bus, :) = h_GG; % .* cos(theta_ij')
%             h_G = obj.matToColDE(H_G);
%             h(1:obj.numFIM.G) = h_G;
            
            % B matrix
%             H_B = zeros(obj.numBus, obj.numBus);
            h_BB = obj.dataE.Vm(bus, snap) * obj.dataE.Vm(:, snap)' .* sin(theta_ij') / obj.k.B;
            h(obj.numFIM.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
%             H_B(bus, :) = h_BB;
%             h_B = obj.matToColDE(H_B);
%             h(obj.numFIM.G+1:obj.numFIM.G+obj.numFIM.B) = h_B;
            
            % Vm
            % the first order term of other Vm
%             H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.dataE.Vm(bus, snap) * obj.dataE.G(:, bus) / obj.k.vm; % obj.dataE.G(:, bus)
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.dataE.Vm(bus, snap) * obj.dataE.G(bus, bus) / obj.k.vm; % obj.dataE.G(bus, bus)
            % the first order term of Vm(bus)
            fOrderVm = obj.dataE.Vm(:, snap) .* obj.dataE.G(:, bus) / obj.k.vm; % obj.dataE.G(:, bus)
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
            h_Va = obj.dataE.Vm(bus, snap) * obj.dataE.Vm(:, snap) .* (- obj.dataE.B(:, bus)) / obj.k.va; % (- obj.dataE.B(:, bus))
            h_Va(bus) = ( - obj.dataE.Vm(bus, snap)^2 * obj.dataE.B(bus, bus)...
                       - obj.data.Q_noised(bus, snap)) / obj.k.va;
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
%             obj.A_FIMP = obj.A_FIMP + FIMPThis;
        end
        
        function obj = approximateFIMQ(obj, bus, snap, pt)
            % This method approximate the Q part of FIM. We ignore the sin
            % part of the power flow equations.
            h = zeros(obj.numFIM.Sum, 1);
            theta_ij = obj.dataE.Va(bus, snap) - obj.dataE.Va(:, snap);
%             Theta_ij = repmat(obj.dataE.Va(:, snap), 1, obj.numBus) - repmat(obj.dataE.Va(:, snap)', obj.numBus, 1);
%             % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
%             GBThetaP = obj.dataE.G .* cos(Theta_ij) + obj.dataE.B .* sin(Theta_ij);
%             % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
%             GBThetaQ = obj.dataE.G .* sin(Theta_ij) - obj.dataE.B .* cos(Theta_ij);
            
            % G matrix
%             H_G = zeros(obj.numBus, obj.numBus);
            h_GG = obj.dataE.Vm(bus, snap) * obj.dataE.Vm(:, snap)' .* sin(theta_ij') / obj.k.G;
            h(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
%             H_G(bus, :) = h_GG;
%             h_G = obj.matToColDE(H_G);
%             h(1:obj.numFIM.G) = h_G;
            
            % B matrix
%             H_B = zeros(obj.numBus, obj.numBus);
            h_BB =  - obj.dataE.Vm(bus, snap) * obj.dataE.Vm(:, snap)' / obj.k.B;
            h_BB = h_BB + obj.data.Vm(bus, snap)^2 / obj.k.B;
            h(obj.numFIM.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
%             H_B(bus, :) = h_BB;
%             h_B = obj.matToColDE(H_B);
%             h(obj.numFIM.G+1:obj.numFIM.G+obj.numFIM.B) = h_B;
            
            % Vm
            % the first order term of other Vm
%             H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.dataE.Vm(bus, snap) * (-obj.dataE.B(:, bus)) / obj.k.vm; % (-obj.dataE.B(:, bus))
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.dataE.Vm(bus, snap) * (-obj.dataE.B(bus, bus)) / obj.k.vm; % (-obj.dataE.B(bus, bus))
            % the first order term of Vm(bus)
            fOrderVm = obj.dataE.Vm(:, snap) .* (-obj.dataE.B(:, bus)) / obj.k.vm; % (-obj.dataE.B(:, bus))
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
            h_Va = - obj.dataE.Vm(bus, snap) * obj.dataE.Vm(:, snap) .* obj.dataE.G(:, bus) / obj.k.va; % obj.dataE.G(:, bus)
            h_Va(bus) = (- obj.dataE.Vm(bus, snap)^2 * obj.dataE.G(bus, bus) ...
                        + obj.data.P_noised(bus, snap)) / obj.k.va;
            h(obj.numFIM.G+obj.numFIM.B+obj.idVa) = h_Va(2:end);
%             H_Va(:, snap) = h_Va;
%             % remove the source bus whose magnitude is not the state variable
%             H_Va(1, :) = []; 
%             h_VaLarge = reshape(H_Va, [], 1);
%             h(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1:end) = h_VaLarge;
            
            % build FIMQ
            h = h / obj.sigma.Q(bus);
%             obj.M(:, pt) = h;
            [row,col,val] = find(h);
            l = length(val);
            obj.mRow(obj.spt:obj.spt+l-1) = row;
            obj.mCol(obj.spt:obj.spt+l-1) = col*pt;
            obj.mVal(obj.spt:obj.spt+l-1) = val;
            obj.spt = obj.spt + l;
%             FIMQThis = h * h';
%             obj.A_FIMQ = obj.A_FIMQ + FIMQThis;
        end
        
        function obj = calABound(obj, varargin)
            % this method calculate the bound from the A_FIM matrix;
            
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
                idCell = 2*(obj.numBus-1) * ones(1, obj.numSnap);
                Cell = mat2cell(obj.A_FIM(obj.numFIM.index, obj.numFIM.index), ...
                    [obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del obj.numFIM.Vm+obj.numFIM.Va], ...
                    [obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del obj.numFIM.Vm+obj.numFIM.Va]);
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
                
                ABC = pinv(Cell{1,1} - BCB); % inv(A-B/CB')
                diagABC = diag(ABC);
                % Calculate the diag of C
                diagC = obj.cellGetDiag(invC22);
                % Calculate the var
                var = [diagABC; diagC];
            else
                cov = full(obj.A_FIM(obj.numFIM.index, obj.numFIM.index))\eye(sum(obj.numFIM.index));
                var = diag(cov);
%                 % we construct a Hermitian matrix H and use Cholesky
%                 % decomposition to compute the inverse matrix
%                 FIM = obj.A_FIM(obj.numFIM.index, obj.numFIM.index);
%                 H = FIM * FIM';
%                 U = chol(H);
%                 Uinv = U \ eye(size(U));
%                 Cov = H' * (Uinv * Uinv');
            end
            if min(var) < 0
                var = abs(var);
%                 cov = cov - diag(diag(cov)) + diag(var);
                fprintf('We use the absolute value of the variance.\n');
            end
            
            obj.boundA.total = sqrt(var);
            obj.boundA.total(obj.boundA.total>obj.prior.Gmax) = obj.prior.Gmax;
%             obj.boundA.cov = cov;
            
            boundG = zeros(obj.numFIM.G, 1);
            boundG(obj.numFIM.index(1:obj.numFIM.G)) = obj.boundA.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.boundA.total(1:obj.numFIM.G-obj.numFIM.del) = obj.boundA.total(1:obj.numFIM.G-obj.numFIM.del) / obj.k.G;
            obj.boundA.G = obj.colToMatDE(boundG, obj.numBus);
            
            boundB = zeros(obj.numFIM.B, 1);
            boundB(obj.numFIM.index(1:obj.numFIM.G)) = ...
                obj.boundA.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.boundA.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) = ...
                obj.boundA.total(obj.numFIM.G+1-obj.numFIM.del:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del) / obj.k.B;
            obj.boundA.B = obj.colToMatDE(boundB, obj.numBus);
            
            obj.boundA.G_relative = abs(obj.boundA.G ./ repmat(diag(obj.data.G), 1, obj.numBus));
            obj.boundA.B_relative = abs(obj.boundA.B ./ repmat(diag(obj.data.B), 1, obj.numBus));
            obj.boundA.G_relative_col = reshape(obj.boundA.G_relative, [], 1);
            obj.boundA.B_relative_col = reshape(obj.boundA.B_relative, [], 1);
            
            obj.boundA.VmVa = reshape(obj.boundA.total(obj.numFIM.G+obj.numFIM.B+1-2*obj.numFIM.del:end), 2*(obj.numBus-1), obj.numSnap);
            obj.boundA.Vm = reshape(obj.boundA.VmVa(1:obj.numBus-1, :), [], 1) / obj.k.vm;
            obj.boundA.VmBus = mean(obj.boundA.VmVa(1:obj.numBus-1, :), 2);
            obj.boundA.Va = reshape(obj.boundA.VmVa(obj.numBus:end, :), [], 1) / obj.k.vm;
            obj.boundA.VaBus = mean(obj.boundA.VmVa(obj.numBus:end, :), 2);
            
%             obj.boundA.Vm = ...
%                 obj.boundA.total(obj.numFIM.G+obj.numFIM.B+1-2*obj.numFIM.del...
%                 :obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm-2*obj.numFIM.del) / obj.k.vm;
%             obj.boundA.VmBus = mean(reshape(obj.boundA.Vm, obj.numBus-1, obj.numSnap), 2);
%             obj.boundA.total(obj.numFIM.G+obj.numFIM.B+1-2*obj.numFIM.del...
%                 :obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm-2*obj.numFIM.del)...
%                 = obj.boundA.Vm;
%             obj.boundA.Va = ...
%                 obj.boundA.total(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1-2*obj.numFIM.del...
%                 :obj.numFIM.Sum-2*obj.numFIM.del) / obj.k.va;
%             obj.boundA.VaBus = mean(reshape(obj.boundA.Va, obj.numBus-1, obj.numSnap), 2);
%             obj.boundA.total(obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm+1-2*obj.numFIM.del...
%                 :obj.numFIM.Sum-2*obj.numFIM.del)...
%                 = obj.boundA.Va;
        end
        
        function obj = identifyTopo(obj)
            % This method identifies the topology by the voltage magnitudes
            % measurements. The initial topology may not be accurate.
            T = obj.data.G~=0;
            Vm = movmean(obj.data.Vm_noised, floor(obj.numSnap/20)+1, 2);
            C = corrcoef(Vm');
            C(isnan(C)) = 0;
            C(1,1) = 1;
            CT = corrcoef(obj.data.Vm');
            CT(isnan(CT)) = 0;
            CT(1,1) = 1;
        end
        
        function obj = approximateY(obj)
            % This method approximates the Y matrix by the measurements. We
            % use the simple Ohom's law to provide an initial value of Y.
            % We also assume the G/B ratio is a constant.
%             rng(103);
%             randG = 0.75 + 0.5 * randn(size(obj.data.G));
%             rng(104);
%             randB = 0.75 + 0.5 * randn(size(obj.data.B));
%             obj.dataE.G = obj.data.G .* randG;
%             obj.dataE.B = obj.data.B .* randB;
%             % The approximation of the diagonal elements
%             diagG = diag(obj.dataE.G);
%             diagB = diag(obj.dataE.B);
            
            % approximate the topology using Vm data only
            % ranking the Vm
%             Vm = obj.data.Vm_noised;
            if 1>2
                IP = obj.data.IP_noised;
                IQ = obj.data.IQ_noised;
                G = IP * obj.data.Vm_noised' / (obj.data.Vm_noised * obj.data.Vm_noised');
                B = - IQ * obj.data.Vm_noised' / (obj.data.Vm_noised * obj.data.Vm_noised');
            else
                IP = obj.data.IP_noised;
                IQ = obj.data.IQ_noised;
                Vm = obj.data.Vm;
                Topo = logical(eye(obj.numBus));
                VmMean = mean(Vm, 2);
                [~, VmOrder] = sort(VmMean,'descend');

                assert (VmOrder(1) == 1); % the first bus is the source bus

                Vm = movmean(Vm, floor(obj.numSnap/20)+1, 2);
                corr = corrcoef(Vm');
                corr(isnan(corr)) = 0; % one can also simulate some disturbance in the source bus voltage
                corr(obj.topoPrior) = -2;
                for i = 2:obj.numBus
                    % iterate each bus
                    [~, loc] = max(corr(VmOrder(i), VmOrder(1:i-1))); % the location of the connected bus
                    Topo(VmOrder(i), VmOrder(loc)) = true;
                    Topo(VmOrder(loc), VmOrder(i)) = true;
                end
%                 if obj.caseName == 'case123_R'
%                     Topo = ~obj.topoPrior;
%                 end

                T = obj.data.G~=0;

                % approximate the parameter
                
                G_ols = zeros(obj.numBus, obj.numBus);
                B_ols = zeros(obj.numBus, obj.numBus);
                for i = 1:obj.numBus
                    j = VmOrder(i);
                    filter = Topo(:, j);
                    filter(j) = false;
                    previous = VmOrder(1:i);
                    previous = intersect(previous, find(filter));

                    VmDelta = Vm(filter, :) - repmat(Vm(j, :), sum(filter), 1);
                    yG = IP(i, :);
                    yB = IQ(i, :);
                    try
                        yG = yG - G_ols(previous, j)' * VmDelta(filter(previous), :);
                        yB = yB + B_ols(previous, j)' * VmDelta(filter(previous), :);
                    catch
                        assert (i == 1);
                    end

                    rng(i);
                    filter(previous) = false;
                    VmDelta = Vm(filter, :) - repmat(Vm(j, :), sum(filter), 1);
    %                 G_ols(j, filter) = obj.tls(VmDelta', yG');
                    G_ols(j, filter) = yG * VmDelta' / (VmDelta * VmDelta');
                    outlier = G_ols(j,:) > -obj.prior.Gmin;
                    G_ols(j, filter & outlier') = - obj.prior.Gmin * (1+0.1*rand());
                    outlier = G_ols(j,:) < -obj.prior.Gmax;
                    G_ols(j, filter & outlier') = - obj.prior.Gmax * (1+0.1*rand());
                    outlier = isnan(G_ols(j,:));
                    G_ols(j, filter & outlier') = - obj.prior.Gmin * (1+0.1*rand());
                    G_ols(filter, j) = G_ols(j, filter);
                    G_ols(j, j) = -sum(G_ols(j, :));

                    B_ols(j, filter) = - yB * VmDelta' / (VmDelta * VmDelta');
                    outlier = B_ols(j,:) < obj.prior.Bmin;
                    B_ols(j, filter & outlier') = obj.prior.Bmin * (1+0.1*rand());
                    outlier = B_ols(j,:) > obj.prior.Bmax;
                    B_ols(j, filter & outlier') = obj.prior.Bmax * (1+0.1*rand());
                    B_ols(filter, j) = B_ols(j, filter);
                    outlier = isnan(B_ols(j,:));
                    B_ols(j, filter & outlier') = obj.prior.Bmin * (1+0.1*rand());
                    B_ols(j, j) = -sum(B_ols(j, :));
                end

                obj.dataE.G = G_ols;
                obj.dataE.B = B_ols;
            end
            
            
%             obj.dataE.G = (G+G')/2;
%             obj.dataE.B = (B+B')/2;
            
%             obj.dataE.G = obj.data.G;
%             obj.dataE.B = obj.data.B;
        end
        
        function obj = iterateY(obj)
            % This method iterate Y matrix considering the measurement
            % error from both inputs and outputs.
            
            % We first assume a flat diagonal element setting
            W = ones(obj.numBus*2, 1);
            obj = optimizeY(obj, W);
        end
        
        function [obj, Gopt, Bopt] = optimizeY(obj, W)
            % This method use some convex optimization method and provide
            % the G and B matrix
            
            % control variables
            G = sdpvar(obj.numBus, obj.numBus);
            B = sdpvar(obj.numBus, obj.numBus);
            % anxillary variables
            Pres = sdpvar(obj.numBus, obj.numSnap);
            Qres = sdpvar(obj.numBus, obj.numSnap);
            
            % constraints
            constP = Pres == G * obj.data.Vm_noised - obj.data.IP_noised;
            constQ = Qres == - B * obj.data.Vm_noised - obj.data.IQ_noised;
            constG = sum(G) == zeros(1, obj.numBus);
            constB = sum(B) == zeros(1, obj.numBus);
            constraints = [constP; constQ; constG; constB];
            for i = 1:obj.numBus
                for j = i+1:obj.numBus
                    constraints = [constraints; G(i,j)<=0];
                    constraints = [constraints; B(i,j)>=0];
                end
            end
            
            % objective function
            objective = sum(W(1:obj.numBus)' * (Pres .* Pres)...
                + W(1+obj.numBus:end)' * (Qres .* Qres));
            options = sdpsettings('solver','gurobi');
            sol = optimize(constraints,objective,options);
            
            Gopt = value(G);
            Bopt = value(B);
        end
        
        function obj = initValue(obj)
            % This method provides the initial value (voltage angles?)
            
        end
        
        function obj = identifyOptNLP(obj)
            % This method simply use the nonlinar programming techique to
            % solve the maximum identification problem
            
            % This version we simply assume we have all the measurements
            % We should bound all the control variables and all the
            % anxillary variables
            
            % control variables
            G = sdpvar(obj.numBus, obj.numBus);
            B = sdpvar(obj.numBus, obj.numBus);
            Pest = sdpvar(obj.numBus, obj.numSnap);
            Qest = sdpvar(obj.numBus, obj.numSnap);
            Vm = sdpvar(obj.numBus, obj.numSnap);
            Va = sdpvar(obj.numBus, obj.numSnap);
            % anxillary variables
            e_P = sdpvar(obj.numBus, obj.numSnap);
            e_Q = sdpvar(obj.numBus, obj.numSnap);
            e_Vm = sdpvar(obj.numBus, obj.numSnap);
            e_Va = sdpvar(obj.numBus, obj.numSnap);
            Theta_ij = sdpvar(obj.numBus, obj.numBus, obj.numSnap);
            GBThetaP = sdpvar(obj.numBus, obj.numBus, obj.numSnap);
            GBThetaQ = sdpvar(obj.numBus, obj.numBus, obj.numSnap);
            % some constaints
            maxGB = 1000;
            maxNoise = 10;
            
            % constraints
            Constraints = [];
            % the power flow equation, P and Q injections
            for snap = 1:obj.numSnap
                Theta_ij(:,:,snap) = repmat(Va(:, snap), 1, obj.numBus) - repmat(Va(:, snap)', obj.numBus, 1);
                % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
                GBThetaP(:,:,snap) = G .* cos(Theta_ij(:,:,snap)) + B .* sin(Theta_ij(:,:,snap));
                % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
                GBThetaQ(:,:,snap) = G .* sin(Theta_ij(:,:,snap)) - B .* cos(Theta_ij(:,:,snap));
                Constraints = [Constraints; Pest(:, snap) == (GBThetaP(:,:,snap) * Vm(:, snap)) .* Vm(:, snap)];
                Constraints = [Constraints; Qest(:, snap) == (GBThetaQ(:,:,snap) * Vm(:, snap)) .* Vm(:, snap)];
            end
            % the anxillary variable constraints
            Constraints = [Constraints; Pest + e_P == obj.data.P_noised];
            Constraints = [Constraints; Qest + e_Q == obj.data.Q_noised];
            Constraints = [Constraints; Vm + e_Vm == obj.data.Vm_noised];
            Constraints = [Constraints; Va + e_Va == obj.data.Va_noised];
            % zero noise for reference bus
            Constraints = [Constraints; e_Va(1,:) == zeros(1, obj.numSnap)];
            Constraints = [Constraints; e_Vm(1,:) == zeros(1, obj.numSnap)];
            % the sum of G and B
            Constraints = [Constraints; sum(G) == zeros(1, obj.numBus)];
            Constraints = [Constraints; sum(B) == zeros(1, obj.numBus)];
            % bound all the variables
%             for i = 1:obj.numBus
%                 for j = i+1:obj.numBus
%                     Constraints = [Constraints; -maxGB <= G(i,j) <= 0];
%                     Constraints = [Constraints; 0 <= B(i,j) <= maxGB];
%                 end
%             end
            Constraints = [Constraints; -obj.sigma.P*ones(1, obj.numSnap)*maxNoise <= e_P <= obj.sigma.P*ones(1, obj.numSnap)*maxNoise];
            Constraints = [Constraints; -obj.sigma.Q*ones(1, obj.numSnap)*maxNoise <= e_Q <= obj.sigma.Q*ones(1, obj.numSnap)*maxNoise];
            Constraints = [Constraints; -obj.sigma.Vm*ones(1, obj.numSnap)*maxNoise <= e_Vm <= obj.sigma.Vm*ones(1, obj.numSnap)*maxNoise];
            Constraints = [Constraints; -obj.sigma.Va*ones(1, obj.numSnap)*maxNoise <= e_Va <= obj.sigma.Va*ones(1, obj.numSnap)*maxNoise];
            
            % assign the initial value
            assign(G, obj.dataE.G);
            assign(B, obj.dataE.B);
            assign(Vm, obj.data.Vm_noised);
            assign(Va, obj.data.Va_noised);
            
            % objective function
            objective = sum((obj.sigma.P.^-2)' * (e_P.*e_P) ...
                + (obj.sigma.Q.^-2)' * (e_Q.*e_Q)...
                + (obj.sigma.Vm(2:end).^-2)' * (e_Vm(2:end,:).*e_Vm(2:end,:))...
                + (obj.sigma.Va(2:end).^-2)' * (e_Va(2:end,:).*e_Va(2:end,:)));
            options = sdpsettings('solver','ipopt','ipopt.max_iter',3000);
            sol = optimize(Constraints,objective,options);
            
            Gopt = value(G);
            Bopt = value(B);
            Pestopt = value(Pest);
            Qestopt = value(Qest);
            Vmopt = value(Vm);
            Vaopt = value(Va);
            e_Popt = value(e_P);
            e_Qopt = value(e_Q);
            e_Vmopt = value(e_Vm);
            e_Vaopt = value(e_Va);
        end
        
        function obj = identifyOptGradient(obj)
            % This method uses gradient-based method to solve the nonconvex
            % optimization problem.
            % Hopefully we could implement some power system domain
            % knowledge into the process because we know the ground truth
            % value.
            obj.maxIter = 4000;
            obj.step = 1e-4;
            obj.stepMax = 1e-3;
            obj.stepMin = 1e-3;
            obj.momentRatio = 0.9;
            obj.updateStepFreq = 20;
            obj.vmvaWeight = 1;
            obj.momentRatioMax = 0.95;
            obj.momentRatioMin = 0.9;
            obj.kZero = 0.0005;
            obj.tuneGrad = false;
            
            % we first initialize data
            obj.dataO.G = obj.dataE.G;
            obj.dataO.B = obj.dataE.B;
            % note that we should replace the Vm ro Va data to some
            % initialized data if we do not have the measurement devices
            obj.dataO.Vm = obj.data.Vm;
%             obj.dataO.Va = obj.data.Va;
            obj.dataO.Vm(2:end, :) = bsxfun(@times, obj.data.Vm_noised(2:end, :), obj.isMeasure.Vm(2:end));
            obj.dataO.Vm(obj.dataO.Vm == 0) = 1;
            obj.dataO.Va = bsxfun(@times, obj.data.Va_noised, obj.isMeasure.Va);
            
            % begin the iteration loop
            % initialize the gradient numbers
            obj.numGrad.G = (obj.numBus - 1) * obj.numBus / 2; % exclude the diagonal elements
            obj.numGrad.B = (obj.numBus - 1) * obj.numBus / 2;
            obj.numGrad.Vm = obj.numSnap * (obj.numBus - 1); % exclude the source bus
            obj.numGrad.Va = obj.numSnap * (obj.numBus - 1);
            obj.numGrad.Sum = obj.numGrad.G + obj.numGrad.B + obj.numGrad.Vm + obj.numGrad.Va;
            obj.iter = 1;
            obj.gradChain = zeros(obj.numGrad.Sum, obj.maxIter);
            obj.lossChain = zeros(5, obj.maxIter);
            obj.parChain = zeros(obj.numGrad.Sum, obj.maxIter);
            obj.stepChain = zeros(1, obj.maxIter);
            
            obj.isConverge = false;
            while (obj.iter <= obj.maxIter && ~obj.isConverge)
                disp(obj.iter);
%                 profile on;
                % collect the paramter vector
                obj = collectPar(obj);
                % build the gradient
                obj = buildGradient(obj);
                % implement the re-weight techique.
                obj = tuneGradient(obj);
                % update the chains
                try
                    obj.gradChain(:, obj.iter) = obj.grad * (1-obj.momentRatio) + obj.gradChain(:, obj.iter-1) * obj.momentRatio;
                catch
                    obj.gradChain(:, obj.iter) = obj.grad;
                end
                obj.lossChain(:, obj.iter) = [obj.loss.total; obj.loss.P; obj.loss.Q; obj.loss.Vm; obj.loss.Va];
                % update the parameters
                obj = updatePar(obj);
                % if converge
                if mod(obj.iter, obj.updateStepFreq) == 0 %obj.iter > 10
                    if (mean(obj.lossChain(1, obj.iter-9:obj.iter-5)) < mean(obj.lossChain(1, obj.iter-4:obj.iter)))
                        obj.step = max(obj.step / 2, obj.stepMin);
                        obj.momentRatio = min(obj.momentRatio + 0.1, obj.momentRatioMax);
                    elseif (((obj.lossChain(1, obj.iter) - obj.lossChain(1, obj.iter-1)) < 0) ...
                        && ((obj.lossChain(1, obj.iter-1) - obj.lossChain(1, obj.iter-2)) < 0)...
                        && ((obj.lossChain(1, obj.iter-2) - obj.lossChain(1, obj.iter-3)) < 0))
%                         && ((obj.lossChain(1, obj.iter-3) - obj.lossChain(1, obj.iter-4)) < 0))
                        obj.step = min(obj.step * 1.2, obj.stepMax);
                        obj.momentRatio = max(obj.momentRatio - 0.1, obj.momentRatioMin);
                    elseif (((obj.lossChain(1, obj.iter) - obj.lossChain(1, obj.iter-1)) *...
                        (obj.lossChain(1, obj.iter-1) - obj.lossChain(1, obj.iter-2)) < 0)...
                        && ((obj.lossChain(1, obj.iter-7) - obj.lossChain(1, obj.iter-8)) *...
                        (obj.lossChain(1, obj.iter-8) - obj.lossChain(1, obj.iter-9)) < 0))
                        obj.step = max(obj.step / 2, obj.stepMin);
                        obj.momentRatio = min(obj.momentRatio + 0.1, obj.momentRatioMax);
%                         disp('tune the weight');
%                         obj.tuneGrad = true;
%                         obj = buildMeasure(obj);
%                         obj.boundTuned = sqrt(abs(diag(full(obj.H)\eye(obj.numGrad.Sum))));
                    end
%                     if (mean(obj.lossChain(1, obj.iter-9:obj.iter-5)) < mean(obj.lossChain(1, obj.iter-4:obj.iter)))
%                         isConverge = true;
%                     end
                end
                obj.stepChain(obj.iter) = obj.step;
                obj.iter = obj.iter + 1;
%                 profile off;
%                 profile viewer;
            end
        end
        
        function obj = buildGradient(obj)
            % This method build the gradient of the squared loss function
            
            % Initialize the gradient matrix
            
            obj.grad = zeros(obj.numGrad.Sum, 1);
            obj.gradP = zeros(obj.numGrad.Sum, 1);
            obj.gradQ = zeros(obj.numGrad.Sum, 1);
            obj.gradVm = zeros(obj.numGrad.Sum, 1);
            obj.gradVa = zeros(obj.numGrad.Sum, 1);
            
            obj.loss.total = 0;
            obj.loss.P = 0;
            obj.loss.Q = 0;
            obj.loss.Vm = 0;
            obj.loss.Va = 0;
            
            % Initialize the idGB
            obj.idGB = zeros(obj.numBus, obj.numBus);
            id = 1;
            for i = 1:obj.numBus
                obj.idGB(i, i+1:end) = id:id+obj.numBus-i-1;
                obj.idGB(i+1:end, i) = id:id+obj.numBus-i-1;
                id = id+obj.numBus-i;
            end
            
            for i = 1:obj.numSnap
                % calculate some basic parameters at present state
                Theta_ij = repmat(obj.dataO.Va(:, i), 1, obj.numBus) - repmat(obj.dataO.Va(:, i)', obj.numBus, 1);
                % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
                GBThetaP = obj.dataO.G .* cos(Theta_ij) + obj.dataO.B .* sin(Theta_ij);
                % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
                GBThetaQ = obj.dataO.G .* sin(Theta_ij) - obj.dataO.B .* cos(Theta_ij);
                % P estimate
                Pest = (GBThetaP * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                % Q estimate
                Qest = (GBThetaQ * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                % the id of Vm and Va
                obj.idVmVa = obj.numSnap * (0:obj.numBus-2) + i;
                
                % calculate the sub-vector of P of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.P(j)
                        obj = buildGradientP(obj, i, j, GBThetaP, GBThetaQ, Pest);
                    end
                end
                
                % calculate the sub-vector of Q of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Q(j)
                        obj = buildGradientQ(obj, i, j, GBThetaP, GBThetaQ, Qest);
                    end
                end
                
                % calculate the sub-vector of Vm of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Vm(j)
                        obj = buildGradientVm(obj, i, j);
                    end
                end
                
                % calculate the sub-vector of Va of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Va(j)
                        obj = buildGradientVa(obj, i, j);
                    end
                end
            end
            
            % collect the gradients and the losses
            obj.grad = obj.gradP + obj.gradQ + obj.gradVm + obj.gradVa;
            obj.loss.total = obj.loss.P + obj.loss.Q + obj.loss.Vm + obj.loss.Va;
        end
        
        function obj = buildGradientP(obj , snap, bus, GBThetaP, GBThetaQ, Pest)
            % This method builds the gradient from the measurement of P
            
            theta_ij = obj.dataO.Va(bus, snap) - obj.dataO.Va(:, snap);
            g = zeros(obj.numGrad.Sum, 1);
            
            % G matrix
            h_GG = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
            h_GG = h_GG -  obj.dataO.Vm(bus, snap)^2;
            g(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
            
            % B matrix
            h_BB = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
            g(obj.numGrad.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
            
            % Vm
            % the first order term of other Vm
            h_Vm = obj.dataO.Vm(bus, snap) * GBThetaP(:, bus);
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.dataO.Vm(bus, snap) * GBThetaP(bus, bus);
            % the first order term of Vm(bus)
            fOrderVm = obj.dataO.Vm(:, snap) .* GBThetaP(:, bus);
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            g(obj.numGrad.G+obj.numGrad.B+obj.idVmVa) = h_Vm(2:end);
            
            % Va
            h_Va = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaQ(:, bus);
            h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.B(bus, bus)...
                       - obj.data.Q_noised(bus, snap); 
%             h_Va(bus) = h_Va(bus)-sum(GBThetaQ(bus, :) * obj.dataO.Vm(:, snap) * obj.dataO.Vm(bus, snap));
            g(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+obj.idVmVa) = h_Va(2:end);
            
            % build GradientP and loss.P
            lossThis = (Pest(bus) - obj.data.P_noised(bus, snap));
            obj.loss.P = obj.loss.P + lossThis^2 * obj.sigma.P(bus).^(-2);
            gradPThis = obj.sigma.P(bus).^(-2) * lossThis * g;
            obj.gradP = obj.gradP + gradPThis;
        end
        
        function obj = buildGradientQ(obj , snap, bus, GBThetaP, GBThetaQ, Qest)
            % This method builds the gradient from the measurement of Q
            
            theta_ij = obj.dataO.Va(bus, snap) - obj.dataO.Va(:, snap);
            g = zeros(obj.numGrad.Sum, 1);
            
            % G matrix
            h_GG = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
            g(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
            
            % B matrix
            h_BB = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
            h_BB = h_BB + obj.dataO.Vm(bus, snap)^2; % the equivilance of diagonal elements
            g(obj.numGrad.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
            
            % Vm
            % the first order term of other Vm
            h_Vm = obj.dataO.Vm(bus, snap) * GBThetaQ(:, bus);
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.dataO.Vm(bus, snap) * GBThetaQ(bus, bus);
            % the first order term of Vm(bus)
            fOrderVm = obj.dataO.Vm(:, snap) .* GBThetaQ(:, bus);
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            g(obj.numGrad.G+obj.numGrad.B+obj.idVmVa) = h_Vm(2:end);
            
            % Va
            h_Va = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaP(:, bus);
            h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.G(bus, bus) ...
                        + obj.data.P_noised(bus, snap);
            g(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+obj.idVmVa) = h_Va(2:end);
            
            % build GradientQ and lossQ
            lossThis = (Qest(bus) - obj.data.Q_noised(bus, snap));
            obj.loss.Q = obj.loss.Q + lossThis^2 * obj.sigma.Q(bus).^(-2);
            gradQThis = obj.sigma.Q(bus).^(-2) * lossThis * g;
            obj.gradQ = obj.gradQ + gradQThis;
        end
        
        function obj = buildGradientVm(obj, snap, bus)
            % This method builds the gradient from the measurement of Vm
            
            % build GradientVm and lossVm
            lossThis = (obj.dataO.Vm(bus, snap) - obj.data.Vm_noised(bus, snap));
            obj.loss.Vm = obj.loss.Vm + lossThis^2 * obj.sigma.Vm(bus).^(-2);
            obj.gradVm(obj.numGrad.G+obj.numGrad.B+obj.idVmVa(bus-1)) = ...
                obj.gradVm(obj.numGrad.G+obj.numGrad.B+obj.idVmVa(bus-1)) + obj.sigma.Vm(bus).^(-2) * lossThis;
        end
        
        function obj = buildGradientVa(obj, snap, bus)
            % This method builds the gradient from the measurement of Va
            
            % build GradientVa and lossVa
            lossThis = (obj.dataO.Va(bus, snap) - obj.data.Va_noised(bus, snap));
            obj.loss.Va = obj.loss.Va + lossThis^2 * obj.sigma.Va(bus).^(-2);
            obj.gradVa(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+obj.idVmVa(bus-1)) = ...
            obj.gradVa(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+obj.idVmVa(bus-1)) + obj.sigma.Va(bus).^(-2) * lossThis;
        end
        
        function obj = tuneGradient(obj)
            % This method tunes the gradient according to the weights. In
            % this version we treat P and Q together.
            
            obj.gradOrigin = obj.grad;
            
            % The weight of the initial gradient
            wg.P.G = mean(abs(obj.gradP(1:obj.numGrad.G)));
            wg.P.B = mean(abs(obj.gradP(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B)));
            gradPVmVa = reshape(obj.gradP(1+obj.numGrad.G+obj.numGrad.B:end), (obj.numBus-1)*2, obj.numSnap);
            wg.P.Vm = mean(mean(abs(gradPVmVa(1:obj.numBus-1, :))));
            wg.P.Va = mean(mean(abs(gradPVmVa(obj.numBus:end, :))));
            
            wg.Q.G = mean(abs(obj.gradQ(1:obj.numGrad.G)));
            wg.Q.B = mean(abs(obj.gradQ(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B)));
            gradQVmVa = reshape(obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:end), (obj.numBus-1)*2, obj.numSnap);
            wg.Q.Vm = mean(mean(abs(gradQVmVa(1:obj.numBus-1, :))));
            wg.Q.Va = mean(mean(abs(gradQVmVa(obj.numBus:end, :))));
            
            wg.PQ_GB = mean([wg.P.G wg.P.B wg.Q.G  wg.Q.B]);
            wg.PQ_Vm = mean([wg.P.Vm wg.Q.Vm]);
            wg.PQ_Va = mean([wg.P.Va wg.Q.Va]);
            gradVmVm = reshape(obj.gradVm(1+obj.numGrad.G+obj.numGrad.B:end), (obj.numBus-1)*2, obj.numSnap);
            gradVaVa = reshape(obj.gradVa(1+obj.numGrad.G+obj.numGrad.B:end), (obj.numBus-1)*2, obj.numSnap);
            wg.Vm_Vm = mean(mean(abs(gradVmVm(1:obj.numBus-1, :))));
            wg.Va_Va = mean(mean(abs(gradVaVa(obj.numBus:end, :))));
            
            % The weight of the CRLB
            if ~obj.tuneGrad
                wb.GB = mean(abs(obj.boundA.total(1:obj.numFIM.G+obj.numFIM.B-2*obj.numFIM.del)));
                wb.Vm = mean(abs(obj.boundA.Vm));
                wb.Va = mean(abs(obj.boundA.Va));
            else
                wb.GB = mean(abs(obj.boundTuned(1:obj.numGrad.G+obj.numGrad.B)));
                wb.Vm = mean(abs(obj.boundTuned(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm)));
                wb.Va = mean(abs(obj.boundTuned(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end)));
            end
            % The weight of the loss function
            wl.total = sqrt(obj.loss.P + obj.loss.Q) + sqrt(obj.loss.Vm) + sqrt(obj.loss.Va);
            wl.PQ = sqrt(obj.loss.P + obj.loss.Q) / wl.total;
            wl.Vm = sqrt(obj.loss.Vm) * obj.vmvaWeight / wl.total; % one P measurements related to multiple Vm and Va, we should correct this.  * 2 * obj.numBus  
            wl.Va = sqrt(obj.loss.Va) * obj.vmvaWeight * 3 / wl.total; % * 2 * obj.numBus; the number five is the average degree of a distribution network times two  * 5
            % The conditional weights
            wl.Vm_PQ = wl.PQ / (wl.PQ + wl.Vm + 1e-9);
            wl.Vm_Vm = wl.Vm / (wl.PQ + wl.Vm + 1e-9);
            wl.Va_PQ = wl.PQ / (wl.PQ + wl.Va + 1e-9);
            wl.Va_Va = wl.Va / (wl.PQ + wl.Va + 1e-9);
            
            % tune the gradient vector. 
            % normalize the gradient weight by P Q Vm Va
            gradPVmVa(1:obj.numBus-1,:) = gradPVmVa(1:obj.numBus-1,:) / (wg.PQ_Vm + 1e-9);
            gradPVmVa(obj.numBus:end,:) = gradPVmVa(obj.numBus:end,:) / (wg.PQ_Va + 1e-9);
%             obj.gradP(1+obj.numGrad.G+obj.numGrad.B:end) = reshape(gradPVmVa, [], 1);
            obj.gradP(1:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradP(1:obj.numGrad.G+obj.numGrad.B) / (wg.PQ_GB + 1e-9);
%             obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
%                 obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) / (wg.PQ_Vm + 1e-9);
%             obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
%                 obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) / (wg.PQ_Va + 1e-9);
            
            gradQVmVa(1:obj.numBus-1,:) = gradQVmVa(1:obj.numBus-1,:) / (wg.PQ_Vm + 1e-9);
            gradQVmVa(obj.numBus:end,:) = gradQVmVa(obj.numBus:end,:) / (wg.PQ_Va + 1e-9);
%             obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:end) = reshape(gradQVmVa, [], 1);
            obj.gradQ(1:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradQ(1:obj.numGrad.G+obj.numGrad.B) / (wg.PQ_GB + 1e-9);
%             obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
%                 obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) / (wg.PQ_Vm + 1e-9);
%             obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
%                 obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) / (wg.PQ_Va + 1e-9);
            
            obj.gradVm = ...
                obj.gradVm / (wg.Vm_Vm + 1e-9);
            obj.gradVa = ...
                obj.gradVa / (wg.Va_Va + 1e-9);
            
            % we use the weight of the approximated CRLB and the weight
            % from the loss function
            gradPVmVa(1:obj.numBus-1,:) = gradPVmVa(1:obj.numBus-1,:) * wb.Vm * wl.Vm_PQ;
            gradPVmVa(obj.numBus:end,:) = gradPVmVa(obj.numBus:end,:) * wb.Va * wl.Va_PQ;
            obj.gradP(1+obj.numGrad.G+obj.numGrad.B:end) = reshape(gradPVmVa, [], 1);
            obj.gradP(1:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradP(1:obj.numGrad.G+obj.numGrad.B) * wb.GB;
%             obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
%                 obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) * wb.Vm * wl.Vm_PQ;
%             obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
%                 obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) * wb.Va * wl.Va_PQ;
            
            gradQVmVa(1:obj.numBus-1,:) = gradQVmVa(1:obj.numBus-1,:) * wb.Vm * wl.Vm_PQ;
            gradQVmVa(obj.numBus:end,:) = gradQVmVa(obj.numBus:end,:) * wb.Va * wl.Va_PQ;
            obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:end) = reshape(gradQVmVa, [], 1);
            obj.gradQ(1:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradQ(1:obj.numGrad.G+obj.numGrad.B) * wb.GB;
%             obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
%                 obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) * wb.Vm * wl.Vm_PQ;
%             obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
%                 obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) * wb.Va * wl.Va_PQ;
            
            obj.gradVm = ...
                obj.gradVm * wb.Vm * wl.Vm_Vm;
            obj.gradVa = ...
                obj.gradVa * wb.Va * wl.Va_Va;
            
            % collect the tuned gardient
            obj.grad = obj.gradP + obj.gradQ + obj.gradVm + obj.gradVa;
        end
        
        function obj = tuneGradientPQ(obj)
            % This method tunes the gradient according to the weights. In
            % this version we treat P and Q independently.
            
            % The weight of the initial gradient
            wg.P.G = mean(abs(obj.gradP(1:obj.numGrad.G)));
            wg.P.B = mean(abs(obj.gradP(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B)));
            wg.P.Vm = mean(abs(obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm)));
            wg.P.Va = mean(abs(obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end)));
            wg.Q.G = mean(abs(obj.gradQ(1:obj.numGrad.G)));
            wg.Q.B = mean(abs(obj.gradQ(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B)));
            wg.Q.Vm = mean(abs(obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm)));
            wg.Q.Va = mean(abs(obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end)));
            wg.Vm = mean(abs(obj.gradVm(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm)));
            wg.Va = mean(abs(obj.gradVa(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end)));
            % The weight of the CRLB
            wb.G = mean(obj.boundA.total(1:obj.numFIM.G));
            wb.B = mean(obj.boundA.total(1+obj.numFIM.G:obj.numFIM.G+obj.numFIM.B));
            wb.Vm = mean(abs(obj.boundA.total(1+obj.numFIM.G+obj.numFIM.B:obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm)));
            wb.Va = mean(abs(obj.boundA.total(1+obj.numFIM.G+obj.numFIM.B+obj.numFIM.Vm:end)));
            % The weight of the loss function
            wl.total = sqrt(obj.loss.P) + sqrt(obj.loss.Q) + sqrt(obj.loss.Vm) + sqrt(obj.loss.Va);
            wl.P = sqrt(obj.loss.P) / wl.total;
            wl.Q = sqrt(obj.loss.Q) / wl.total;
            wl.Vm = sqrt(obj.loss.Vm) * obj.vmvaWeight / wl.total; % one P measurements related to multiple Vm and Va, we should correct this.  * 2 * obj.numBus  
            wl.Va = sqrt(obj.loss.Va) * obj.vmvaWeight / wl.total; % * 2 * obj.numBus; the number five is the average degree of a distribution network times two  * 5
            % The conditional weights
            wl.GP = wl.P / (wl.P + wl.Q + 1e-9);
            wl.GQ = wl.Q / (wl.P + wl.Q + 1e-9);
            wl.BP = wl.P / (wl.P + wl.Q + 1e-9);
            wl.BQ = wl.Q / (wl.P + wl.Q + 1e-9);
            wl.VmP = wl.P / (wl.P + wl.Q + wl.Vm + 1e-9);
            wl.VmQ = wl.Q / (wl.P + wl.Q + wl.Vm + 1e-9);
            wl.VmVm = wl.Vm / (wl.P + wl.Q + wl.Vm + 1e-9);
            wl.VaP = wl.P / (wl.P + wl.Q + wl.Va + 1e-9);
            wl.VaQ = wl.Q / (wl.P + wl.Q + wl.Va + 1e-9);
            wl.VaVa = wl.Va / (wl.P + wl.Q + wl.Va + 1e-9);
            
            % tune the gradient vector. 
            % normalize the gradient weight by P Q Vm Va
            obj.gradP(1:obj.numGrad.G) = ...
                obj.gradP(1:obj.numGrad.G) / (wg.P.G + 1e-9);
            obj.gradP(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradP(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) / (wg.P.B + 1e-9);
            obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
                obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) / (wg.P.Vm + 1e-9);
            obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
                obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) / (wg.P.Va + 1e-9);
            
            obj.gradQ(1:obj.numGrad.G) = ...
                obj.gradQ(1:obj.numGrad.G) / (wg.Q.G + 1e-9);
            obj.gradQ(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradQ(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) / (wg.Q.B + 1e-9);
            obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
                obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) / (wg.Q.Vm + 1e-9);
            obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
                obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) / (wg.Q.Va + 1e-9);
            
            obj.gradVm(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
                obj.gradVm(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) / (wg.Vm + 1e-9);
            obj.gradVa(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
                obj.gradVa(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) / (wg.Va + 1e-9);
            
            % we use the weight of the approximated CRLB and the weight
            % from the loss function
            
            obj.gradP(1:obj.numGrad.G) = ...
                obj.gradP(1:obj.numGrad.G) * wb.G * wl.GP;
            obj.gradP(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradP(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) * wb.B * wl.BP;
            obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
                obj.gradP(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) * wb.Vm * wl.VmP;
            obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
                obj.gradP(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) * wb.Va * wl.VaP;
            
            obj.gradQ(1:obj.numGrad.G) = ...
                obj.gradQ(1:obj.numGrad.G) * wb.G * wl.GQ;
            obj.gradQ(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) = ...
                obj.gradQ(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) * wb.B * wl.BQ;
            obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
                obj.gradQ(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) * wb.Vm * wl.VmQ;
            obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
                obj.gradQ(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) * wb.Va * wl.VaQ;
            
            obj.gradVm(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = ...
                obj.gradVm(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) * wb.Vm * wl.VmVm;
            obj.gradVa(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) = ...
                obj.gradVa(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end) * wb.Va * wl.VaVa;
            
            % collect the tuned gardient
            obj.grad = obj.gradP + obj.gradQ + obj.gradVm + obj.gradVa;
        end
        
        function obj = collectPar(obj)
            % This method formulates the parameter vector
            par = zeros(obj.numGrad.Sum, 1);
            par(1:obj.numGrad.G) = obj.matOfColDE(obj.dataO.G);
            par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B) = obj.matOfColDE(obj.dataO.B);
            par(1+obj.numGrad.G+obj.numGrad.B:end) = reshape([obj.dataO.Vm(2:end,:);obj.dataO.Va(2:end,:)], [], 1);
            obj.parChain(:, obj.iter) = par;
        end
        
        function obj = updatePar(obj)
            % This method updates the parameters in the iteration process
            delta = obj.step * obj.gradChain(:, obj.iter);
            par = obj.parChain(:, obj.iter) - delta;
            % gather the par values
            G = par(1:obj.numGrad.G);
            B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
%             G(G>0) = 0;
%             B(B<0) = 0;
%             G(B==0) = 0; % we do not use it because it will cause sudden change
%             B(G==0) = 0;
            % we first do not assume any topologies, then we would add some
            % topology iteration techiques.
            obj.dataO.G = obj.colToMatDE(G, obj.numBus);
            obj.dataO.B = obj.colToMatDE(B, obj.numBus);
%             if mod(obj.iter, obj.updateVmVaFreq) == 0 
            Vm = par(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm);
            Va = par(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end);
            obj.dataO.Vm(2:end, :) = reshape(Vm, [], obj.numBus-1)'; % exclude the source bus
            obj.dataO.Va(2:end, :) = reshape(Va, [], obj.numBus-1)'; % exclude the source bus
%             end
        end
        
        function obj = identifyOptNewton(obj)
            % This method uses Newton method to update the parameters
            obj.maxIter = 500;
            obj.thsTopo = 0.05;
            obj.Topo = true(obj.numBus, obj.numBus);
            obj.Tvec = logical(obj.matOfColDE(obj.Topo));
            
            % we first initialize data
            obj.dataO.G = obj.dataE.G;
            obj.dataO.B = obj.dataE.B;
            % note that we should replace the Vm ro Va data to some
            % initialized data if we do not have the measurement devices
            obj.dataO.Vm = obj.data.Vm;
%             obj.dataO.Va = obj.data.Va;
            obj.dataO.Vm(2:end, :) = bsxfun(@times, obj.data.Vm_noised(2:end, :), obj.isMeasure.Vm(2:end));
            obj.dataO.Vm(obj.dataO.Vm == 0) = 1;
            obj.dataO.Va = bsxfun(@times, obj.data.Va_noised, obj.isMeasure.Va);
            
%             obj.dataO.P = obj.data.P_noised;
%             obj.dataO.Q = obj.data.Q_noised;
            obj.dataO.P = obj.data.P_noised;
            obj.dataO.Q = obj.data.Q_noised;
            
            % begin the iteration loop
            % initialize the gradient numbers
            obj.numGrad.G = (obj.numBus - 1) * obj.numBus / 2; % exclude the diagonal elements
            obj.numGrad.B = (obj.numBus - 1) * obj.numBus / 2;
            obj.numGrad.Vm = obj.numSnap * (obj.numBus - 1); % exclude the source bus
            obj.numGrad.Va = obj.numSnap * (obj.numBus - 1);
            obj.numGrad.Sum = obj.numGrad.G + obj.numGrad.B + obj.numGrad.Vm + obj.numGrad.Va;
            obj.iter = 1;
            obj.lossChain = zeros(5, obj.maxIter);
            obj.parChain = zeros(obj.numGrad.Sum, obj.maxIter);
            obj.isGB = false;
            
            obj.isConverge = 0;
            while (obj.iter <= obj.maxIter && obj.isConverge <= 2)
                % update Va by power flow calculation
%                 obj = updateParPF(obj);
                % collect the paramter vector
                obj = collectPar(obj);
                % build the Jacobian
                obj = buildJacobian(obj);
                % build the Hessian
                obj = buildHessian(obj);
                obj.lossChain(:, obj.iter) = ...
                    [obj.loss.total; obj.loss.P; obj.loss.Q; ...
                    obj.loss.Vm; obj.loss.Va];
                % update the parameters
                obj = updateParNewtonGV(obj);
%                 if (mod(obj.iter-1, 2) ~= 0)
%                     obj = updateParNewtonGV(obj, true); % update GB
%                 else
% %                     obj = updateParNewtonGV(obj, true); % update GB
%                     obj = updateParNewtonGV(obj, false);
%                 end
                obj.iter = obj.iter + 1;
            end
        end
        
        function obj = identifyOptLMPower(obj)
            % This function identify the topology and the parameters using
            % the LM-based strategy and the knowledge of power flow
            % equations
%             obj.second = 2e1; % the absolute proportion of second order
%             obj.secondMax = 1e4;
%             obj.secondMin = 1e-2;
            
            obj.lambda = 1e1; % the proportion of first order gradient
            obj.lambdaMin = 0;
            obj.lambdaMax = 1e2;%1e3 1e2;
            obj.ratioMax = 1e3; % the ratio of second order / first order (final value)1e4
            obj.ratioMaxConst = 1e4; % 1e4
%             obj.ratioMaxMax = 1e4;
%             obj.ratioMaxMin = 1e4;
            obj.lambdaCompen = 1e4; % the additional compensate when second order is too large 1e2
            
            obj.isLHinv = true;
            obj.isLBFGS = false;
            obj.numEstH = 4;
            
            obj.vaPseudoWeightInit = 100;
            obj.vaPseudoWeight = obj.vaPseudoWeightInit;
            obj.vaPseudoMax = 1e3;
            obj.vaPseudoMin = 1;
            obj.maxD2Upper = 5000;
            obj.maxD2Lower = 50;
            
            obj.stepInit = 1e-3; % 1e-5
            obj.stepMin = 1e-5;
            obj.stepMax = 1;
            obj.deRatio = 1.1;
            obj.inRatio = 2;
            obj.regretRatio = 2;
            obj.startPF = 4;
            
            obj.updateStart = 20;           % the start iteration number to update the topology
            obj.updateStep = 6;             % the number of steps we calculate the judge whether stop iteration
            obj.updateRatio = 1e-2;         % the long term ratio and the short term ratio to stop iteration
            obj.updateRatioLast = 1e-3;     % the last topology update ratio
            obj.updateLast = 0;
            obj.updateLastLoss = 1e2;       % times the lossMin
            
            obj.maxIter = 2000;
            obj.thsTopo = 0.05;
            obj.Topo = ~obj.topoPrior;
            obj.Tvec = logical(obj.matOfColDE(obj.Topo));
            obj.numGrad.del = obj.numFIM.del; % the number of branches that should be disconnected
            obj.vmvaWeight = 1;
            
            if strcmp(obj.caseName, 'case123_R')
                obj.lambda = 1e3; % the proportion of first order gradient
                obj.lambdaMin = 1e-1;
                obj.lambdaMax = 1e3;
                obj.regretRatio = 1.2;
                obj.maxIter = 5000;
                obj.deRatio = 1.1;
                obj.inRatio = 2;
                obj.ratioMaxConst = 1e4;
            end
            
            obj.momentRatio = 0.9;
            obj.momentRatioMax = 0.9;
            obj.tuneGrad = false;
            
            % we first initialize the data
            obj.dataO.G = obj.dataE.G;
            obj.dataO.B = obj.dataE.B;
            
            obj.dataO.Vm = obj.data.Vm;
%             obj.dataO.Va = obj.data.Va;
            obj.dataO.Vm(2:end, :) = bsxfun(@times, obj.data.Vm_noised(2:end, :), obj.isMeasure.Vm(2:end));
            obj.dataO.Vm(obj.dataO.Vm == 0) = 1;
%             obj.dataO.Va = bsxfun(@times, obj.data.Va_noised, obj.isMeasure.Va);
            obj.dataO.P = obj.data.P_noised;
            obj.dataO.Q = obj.data.Q_noised;
            obj.dataO.Va = zeros(obj.numBus, obj.numSnap);
            obj = updateParPF(obj);
            obj.dataO.Va(obj.isMeasure.Va, :) = obj.data.Va_noised(obj.isMeasure.Va, :);
            
%             obj.dataO.P = obj.data.P;
%             obj.dataO.Q = obj.data.Q;
%             obj.dataO.Vm = obj.data.Vm;
%             obj.dataO.Va = obj.data.Va;
%             obj.dataO.G = obj.data.G;
%             obj.dataO.B = obj.data.B;
            
            % initialize the gradient numbers
            obj.numGrad.G = (obj.numBus - 1) * obj.numBus / 2; % exclude the diagonal elements
            obj.numGrad.B = (obj.numBus - 1) * obj.numBus / 2;
            obj.numGrad.Vm = obj.numSnap * (obj.numBus - 1); % exclude the source bus
            obj.numGrad.Va = obj.numSnap * (obj.numBus - 1);
            obj.numGrad.Sum = obj.numGrad.G + obj.numGrad.B + obj.numGrad.Vm + obj.numGrad.Va;
            
            % evaluate the minimum loss
            obj = evaluateLossMin(obj);
            obj.updateLastLoss = obj.updateLastLoss * obj.lossMin;
            
            % begin the iteration loop
            obj.iter = 1;
            obj.lossChain = zeros(5, obj.maxIter);
            obj.parChain = zeros(obj.numGrad.Sum, obj.maxIter);
            obj.stepChain = zeros(1, obj.maxIter);
            obj.lambdaChain = zeros(1, obj.maxIter);
            obj.isBoundChain = false(1, obj.maxIter);
            obj.ratioMaxChain = zeros(1, obj.maxIter);
            obj.ratioChain = zeros(1, obj.maxIter);
            obj.maxD2Chain = zeros(1, obj.maxIter);
            obj.D2D1Chain = zeros(1, obj.maxIter);
            obj.sChain = zeros(obj.numGrad.Sum, obj.maxIter);
            obj.yChain = zeros(obj.numGrad.Sum, obj.maxIter);
            obj.rhoChain = zeros(1, obj.maxIter);
%             obj.secondChain = zeros(1, obj.maxIter);
            obj.isGB = false;
            obj.isConverge = 0;
            obj.isSecond = false;
            obj.isFirst = false;
            obj.step = obj.stepInit;
            
            while (obj.iter <= obj.maxIter && obj.isConverge <= 2)
                disp(obj.iter);
                % whether to stop iteration and update the topology
                if ((obj.iter > obj.updateStart + obj.updateLast ...
                        && mean(obj.lossChain(1, obj.iter-3*obj.updateStep:obj.iter-2*obj.updateStep)) ...
                        / mean(obj.lossChain(1, obj.iter-2*obj.updateStep:obj.iter-obj.updateStep)) ...
                        < (1 + obj.updateRatio)...
                        && obj.lossChain(1, obj.iter-2) / obj.lossChain(1, obj.iter-1) ...
                        < (1 + obj.updateRatio)...
                        && obj.lossChain(1, obj.iter-1) < obj.updateLastLoss))...
                        || (obj.iter > 1 + obj.updateLast && obj.loss.total < 0.9*obj.lossMin)...
                        || ((obj.iter > 31 + obj.updateLast) ...
                        && all(diff(obj.lossChain(1, obj.iter-30:obj.iter-1))>0))
                    obj = updateTopoIter(obj);
                    continue;
                end
%                 profile on;
%                 % do the pseudo PF
%                 if ~all(obj.isMeasure.Va(2:end)) ...
%                         && ~obj.isFirst && obj.iter > 1 ...
%                         && log10(obj.loss.total / obj.lossMin) < obj.startPF% We do not calculate the PF for the regret mode
% %                     obj = updateParPF(obj);
%                 end
                % collect the parameter vector
                obj = collectPar(obj);
%                 lossTest = getLoss(obj);
                % build the Hessian
                obj = buildMeasure(obj);
                obj.lossChain(:, obj.iter) = ...
                    [obj.loss.total; obj.loss.P; obj.loss.Q; ...
                    obj.loss.Vm; obj.loss.Va];
                % implement the re-weight techique.
                obj = tuneGradient(obj);
                % update the parameters
                obj.isFirst = false;
                obj = updateParLMPower(obj);
                obj.iter = obj.iter + 1;
%                 profile off;
%                 profile viewer;
            end
            obj.lossChain(:, obj.iter+1:end) = [];
            obj.parChain(:, obj.iter+1:end) = [];
            obj.stepChain(:, obj.iter+1:end) = [];
            obj.lambdaChain(:, obj.iter+1:end) = [];
            obj.ratioMaxChain(:, obj.iter+1:end) = [];
            obj.maxD2Chain(:, obj.iter+1:end) = [];
            obj.D2D1Chain(:, obj.iter+1:end) = [];
            
        end
        
        function obj = identifyLineSearch(obj)
            % This method implement the line search
            % We may use simply the second order, or the combination of
            % first order and second order
            obj.ls_c = 1e-2;
            obj.ls_alpha = 5;
            obj.ls_maxTry = 20;
%             obj.boundA = obj.bound;
            
            obj.isLHinv = true;
            obj.isPHinv = true;
            obj.isIll = false;
            obj.isLBFGS = false;
            obj.maxIter = 2000;%2000
            obj.thsTopo = 0.05;
            obj.Topo = ~obj.topoPrior;
            obj.Tvec = logical(obj.matOfColDE(obj.Topo));
            obj.numGrad.del = obj.numFIM.del; % the number of branches that should be disconnected
            obj.vmvaWeight = 1;
            obj.updateLastLoss = 1e2;       % times the lossMin
            
            % we first initialize the data
            obj.dataO.G = obj.dataE.G;
            obj.dataO.B = obj.dataE.B;
            
            obj.dataO.Vm = obj.data.Vm;
%             obj.dataO.Va = obj.data.Va;
            obj.dataO.Vm(2:end, :) = bsxfun(@times, obj.data.Vm_noised(2:end, :), obj.isMeasure.Vm(2:end));
            obj.dataO.Vm(obj.dataO.Vm == 0) = 1;
%             obj.dataO.Va = bsxfun(@times, obj.data.Va_noised, obj.isMeasure.Va);
            obj.dataO.P = obj.data.P_noised;
            obj.dataO.Q = obj.data.Q_noised;
            obj.dataO.Va = zeros(obj.numBus, obj.numSnap);
            obj = updateParPF(obj);
            obj.dataO.Va(obj.isMeasure.Va, :) = obj.data.Va_noised(obj.isMeasure.Va, :);
            
            
            % initialize the gradient numbers
            obj.numGrad.G = (obj.numBus - 1) * obj.numBus / 2; % exclude the diagonal elements
            obj.numGrad.B = (obj.numBus - 1) * obj.numBus / 2;
            obj.numGrad.Vm = obj.numSnap * (obj.numBus - 1); % exclude the source bus
            obj.numGrad.Va = obj.numSnap * (obj.numBus - 1);
            obj.numGrad.Sum = obj.numGrad.G + obj.numGrad.B + obj.numGrad.Vm + obj.numGrad.Va;
            
            % evaluate the minimum loss
            obj.updateLastLoss = 1e3;       % times the lossMin
            obj = evaluateLossMin(obj);
            obj.updateLastLoss = obj.updateLastLoss * obj.lossMin;
            
            obj.updateStart = 10;           % the start iteration number to update the topology
            obj.updateStep = 3;             % the number of steps we calculate the judge whether stop iteration
            obj.updateRatio = 1e-2;         % the long term ratio and the short term ratio to stop iteration
            obj.updateRatioLast = 1e-3;     % the last topology update ratio
            obj.updateLast = 0;
            switch obj.caseName
                case 'case33bw'
                    obj.maxD2Upper = 100;
                otherwise
                    obj.maxD2Upper = 1000;
            end
            
            obj.momentRatio = 0.9;
            obj.momentRatioMax = 0.9;
            obj.tuneGrad = false;
            
            % begin the iteration loop
            obj.iter = 1;
            obj.lossChain = zeros(5, obj.maxIter);
            obj.parChain = zeros(obj.numGrad.Sum, obj.maxIter);
            obj.isConverge = 0;
            
            while (obj.iter <= obj.maxIter && obj.isConverge <= 2)% 
                disp(obj.iter);
                % whether to stop iteration and update the topology
                if ((obj.iter > obj.updateStart + obj.updateLast ...
                        && mean(obj.lossChain(1, obj.iter-3*obj.updateStep:obj.iter-2*obj.updateStep)) ...
                        / mean(obj.lossChain(1, obj.iter-2*obj.updateStep:obj.iter-obj.updateStep)) ...
                        < (1 + obj.updateRatio)...
                        && obj.lossChain(1, obj.iter-2) / obj.lossChain(1, obj.iter-1) ...
                        < (1 + obj.updateRatio)...
                        && obj.lossChain(1, obj.iter-1) < obj.updateLastLoss))...
                        || (obj.iter > 1 + obj.updateLast && obj.loss.total < obj.lossMin*0.8)...
                        || ((obj.iter > 31 + obj.updateLast) ...
                        && all(diff(obj.lossChain(1, obj.iter-30:obj.iter-1))>0))
                    obj = updateABound(obj);
                    obj = updateTopoIter(obj);
%                     continue;
                end
                % collect the parameter vector
                obj = collectPar(obj);
                % build the Hessian
                obj = buildMeasure(obj);
                obj.lossChain(:, obj.iter) = ...
                    [obj.loss.total; obj.loss.P; obj.loss.Q; ...
                    obj.loss.Vm; obj.loss.Va];
                disp(obj.loss.total/1e10);
                % update the bound
%                 if mod(obj.iter, obj.updateStart*2) == 0
%                     disp('we update the approximated bound');
%                     obj = updateABound(obj);
%                 end
                % implement the re-weight techique.
                obj = tuneGradient(obj);
                % update the parameters
                obj = updateParLineSearch(obj);
                obj.iter = obj.iter + 1;
            end
            obj.lossChain(:, obj.iter+1:end) = [];
            obj.parChain(:, obj.iter+1:end) = [];
        end
        
        function obj = updateParLineSearch(obj)
            % This method updates the parameters using the line search
            % strategies
            
            id_GB = [obj.Tvec; obj.Tvec];
            id = [id_GB; true(obj.numGrad.Vm+obj.numGrad.Va, 1)];
            
            % get the first and second order delta
            if obj.iter > 1 + obj.updateLast
                moment = obj.gradPast * obj.momentRatio + obj.grad * (1-obj.momentRatio);
            else
                moment = obj.grad;
            end
            obj.gradPast = moment;
            delta1 = moment(id);
            if ~obj.isLHinv
                if ~obj.isPHinv
                    delta2 = obj.H(id, id) \ obj.gradOrigin(id);
                else
                    delta2 = lsqminnorm(obj.H(id, id), obj.gradOrigin(id));
                end
            else
                [obj, delta2] = calLHInv(obj, id);
            end
            % correct the large value of delta2
%             delta2(delta2 > obj.prior.Gmax) = obj.prior.Gmax;
%             delta2(delta2 < -obj.prior.Gmax) = -obj.prior.Gmax;
%             maxD2 = max(abs(delta2));

            % do the line search of first order
            for i = -5:1:obj.ls_maxTry
                alpha = 1/(obj.ls_alpha^i);
                delta = alpha * delta1;
                % try the current delta and update the parameters
                par = zeros(obj.numGrad.Sum, 1);
                par(id) = obj.parChain(id, obj.iter) - delta;
                G = par(1:obj.numGrad.G);
                B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
                
%                 outlier = G > 0;
%                 G(outlier & obj.Tvec) = 0;
%                 outlier = B < 0;
%                 B(outlier & obj.Tvec) = 0;
                
                obj.dataO.G = obj.colToMatDE(G, obj.numBus);
                obj.dataO.B = obj.colToMatDE(B, obj.numBus);
                VmVa = reshape(par(1+obj.numGrad.G+obj.numGrad.B:end), 2*(obj.numBus-1), obj.numSnap);
                obj.dataO.Vm(2:end, :) = VmVa(1:obj.numBus-1, :);
                obj.dataO.Va(2:end, :) = VmVa(obj.numBus:end, :);
                lossTry = getLoss(obj);
                thresDelta = obj.ls_c * obj.gradOrigin(id)' * delta;
                if obj.loss.total - lossTry > thresDelta
                    fprintf('The first order delta try number is %d.\n', i);
                    break
                end
            end
%             GB = [G(obj.Tvec); B(obj.Tvec)];
%             delta(id_GB) = obj.parChain(id_GB, obj.iter) - GB;
            delta1 = delta;
%             delta1 = delta1 * 0;


            if obj.isIll
                delta2(delta2>obj.prior.Gmax) = obj.prior.Gmax;
                delta2(delta2<-obj.prior.Gmax) = -obj.prior.Gmax;
                begin = 4; % 8 for case33
            else
                begin = -5;
            end
            for i = begin:1:obj.ls_maxTry
                lambdaLS = obj.ls_alpha^i;
                d2 = delta2 * 1/(1+lambdaLS);
                idSmall = abs(d2) < 1;
                d2(idSmall) = d2(idSmall) / sqrt(1/(1+lambdaLS));
                delta = delta1 * lambdaLS/(1+lambdaLS) + d2;
%                 delta = alpha * delta2;
                % try the current delta and update the parameters
                par = zeros(obj.numGrad.Sum, 1);
                par(id) = obj.parChain(id, obj.iter) - delta;
                G = par(1:obj.numGrad.G);
                B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
                
%                 outlier = G > 0;
%                 G(outlier & obj.Tvec) = 0;
%                 outlier = B < 0;
%                 B(outlier & obj.Tvec) = 0;

                obj.dataO.G = obj.colToMatDE(G, obj.numBus);
                obj.dataO.B = obj.colToMatDE(B, obj.numBus);
                VmVa = reshape(par(1+obj.numGrad.G+obj.numGrad.B:end), 2*(obj.numBus-1), obj.numSnap);
                obj.dataO.Vm(2:end, :) = VmVa(1:obj.numBus-1, :);
                obj.dataO.Va(2:end, :) = VmVa(obj.numBus:end, :);
                lossTry = getLoss(obj);
                thresDelta = obj.ls_c * obj.gradOrigin(id)' * delta;
                if obj.loss.total - lossTry > thresDelta
                    fprintf('The second order delta try number is %d.\n', i);
                    break
                end
            end

%             delta = delta1;
%             par = zeros(obj.numGrad.Sum, 1);
%             par(id) = obj.parChain(id, obj.iter) - delta;
%             G = par(1:obj.numGrad.G);
%             B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
% %                 outlier = G > 0;
% %                 G(outlier & obj.Tvec) = 0;
% %                 outlier = B < 0;
% %                 B(outlier & obj.Tvec) = 0;
%             obj.dataO.G = obj.colToMatDE(G, obj.numBus);
%             obj.dataO.B = obj.colToMatDE(B, obj.numBus);
%             VmVa = reshape(par(1+obj.numGrad.G+obj.numGrad.B:end), 2*(obj.numBus-1), obj.numSnap);
%             obj.dataO.Vm(2:end, :) = VmVa(1:obj.numBus-1, :);
%             obj.dataO.Va(2:end, :) = VmVa(obj.numBus:end, :);

        end
        
        function obj = updateABound(obj)
            % This method update the approximate bound from the dataO
            % struct.
            id_GB = [obj.Tvec; obj.Tvec];
            id = [id_GB; true(obj.numGrad.Vm+obj.numGrad.Va, 1)];
            % split the matrices
            numMea = size(obj.M, 2);
            numGB = obj.numGrad.G+obj.numGrad.B-2*obj.numGrad.del;
            idSplit = [numGB ones(1, obj.numSnap)*2*(obj.numBus-1)];
            M = obj.M;
%             M = mat2cell(obj.M(id, :), idSplit, numMea);
            A = full(M{1}*M{1}');
            
            % calculate the value inv(A-B/CB')
            invC = cellfun(@(m) inv(full(m*m')), M(2:end), 'UniformOutput', false);
            BCB = zeros(numGB); % B/CB'
            BCell = cell(obj.numSnap, 1);
            for i = 1:obj.numSnap
                B = full(M{1} * M{i+1}');
                BCell{i} = B;
                BCB = BCB + B*invC{i}*B';
            end
            ABCB = inv(A - BCB);
            varA = diag(ABCB);
            
            % calculate the value invC+invC*B'*ABCB*B*invC
            VCell = cell(obj.numSnap, 1);
            for i = 1:obj.numSnap
                add = invC{i}*BCell{i}'*ABCB*BCell{i}*invC{i};
                VCell{i} = diag(invC{i}) + diag(add);
            end
            varV = cell2mat(VCell);
            var = [varA; varV];
            obj.boundA.total = sqrt(abs(var));
            obj.boundA.total(obj.boundA.total>obj.prior.Gmax) = obj.prior.Gmax;
            
            boundG = zeros(obj.numGrad.G, 1);
            boundG(obj.Tvec) = obj.boundA.total(1:obj.numGrad.G-obj.numGrad.del);
            obj.boundA.G = obj.colToMatDE(boundG, obj.numBus);
            boundB = zeros(obj.numGrad.B, 1);
            boundB(obj.Tvec) = obj.boundA.total(1+obj.numGrad.G-obj.numGrad.del:obj.numGrad.G+obj.numGrad.B-2*obj.numGrad.del);
            obj.boundA.B = obj.colToMatDE(boundB, obj.numBus);
            
%             obj.boundA.G(obj.Tvec) = obj.boundA.total(1:obj.numGrad.G-obj.numGrad.del);
%             obj.boundA.B(obj.Tvec);
            
            obj.boundA.VmVa = reshape(obj.boundA.total(obj.numGrad.G+obj.numGrad.B+1-2*obj.numGrad.del:end), 2*(obj.numBus-1), obj.numSnap);
            obj.boundA.Vm = reshape(obj.boundA.VmVa(1:obj.numBus-1, :), [], 1) / obj.k.vm;
            obj.boundA.VmBus = mean(obj.boundA.VmVa(1:obj.numBus-1, :), 2);
            obj.boundA.Va = reshape(obj.boundA.VmVa(obj.numBus:end, :), [], 1) / obj.k.vm;
            obj.boundA.VaBus = mean(obj.boundA.VmVa(obj.numBus:end, :), 2);
        end
        
        function loss = getLoss(obj)
            % This method return the loss of the function
            loss = 0;
            for i = 1:obj.numSnap
                % calculate some basic parameters at present state
                Theta_ij = repmat(obj.dataO.Va(:, i), 1, obj.numBus) - repmat(obj.dataO.Va(:, i)', obj.numBus, 1);
                % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
                GBThetaP = obj.dataO.G .* cos(Theta_ij) + obj.dataO.B .* sin(Theta_ij);
                % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
                GBThetaQ = obj.dataO.G .* sin(Theta_ij) - obj.dataO.B .* cos(Theta_ij);
                % P estimate
                Pest = (GBThetaP * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                lossP = sum(((Pest(obj.isMeasure.P) - obj.data.P_noised(obj.isMeasure.P, i)) ./ obj.sigma.P).^2);
                loss = loss + lossP;
                % Q estimate
                Qest = (GBThetaQ * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                lossQ = sum(((Qest(obj.isMeasure.Q) - obj.data.Q_noised(obj.isMeasure.Q, i)) ./ obj.sigma.Q).^2);
                loss = loss + lossQ;
            end
            lossVm = sum(sum(bsxfun(@rdivide, obj.dataO.Vm(obj.isMeasure.Vm, :) - obj.data.Vm_noised(obj.isMeasure.Vm, :), obj.sigma.Vm(obj.isMeasure.Vm)).^2));
            loss = loss + lossVm;
            lossVa = sum(sum(bsxfun(@rdivide, obj.dataO.Va(obj.isMeasure.Va, :) - obj.data.Va_noised(obj.isMeasure.Va, :), obj.sigma.Va(obj.isMeasure.Va)).^2));
            loss = loss + lossVa;
        end
        
        function obj = updateTopoIter(obj)
            % This method update the topology in the iteration process
            
            % We collect the parameter of the last step, because we have
            % the regret strategy
%             obj.iter = obj.iter - 1;
%             par = obj.parChain(:, obj.iter);
%             G = par(1:obj.numGrad.G);
%             B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
%             obj.dataO.G = obj.colToMatDE(G, obj.numBus);
%             obj.dataO.B = obj.colToMatDE(B, obj.numBus);
%             VmVa = reshape(par(1+obj.numGrad.G+obj.numGrad.B:end), 2*(obj.numBus-1), obj.numSnap);
%             obj.dataO.Vm(2:end, :) = VmVa(1:obj.numBus-1, :);
%             obj.dataO.Va(2:end, :) = VmVa(obj.numBus:end, :);
            
            % We update the topo
            diagEle = sum(abs(obj.dataO.G)) / 2;
%             diagEle = diag(obj.dataO.G);
            % due with the minus value
            for i = 1:obj.numBus
                if diagEle(i) < 0
                    diagEle(i) = max(abs(obj.dataO.G(i, :)));
                end
            end
            diagEle(diagEle<0) = 0.1;
            ratio1 = abs(bsxfun(@rdivide, obj.dataO.G, diagEle));
            ratio2 = abs(bsxfun(@rdivide, obj.dataO.G, diagEle'));
            ratio = max(ratio1, ratio2);
            ratio = ratio + eye(obj.numBus);
            denseRatio = size(find(obj.dataO.G),1)/(obj.numBus*obj.numBus);
            
%             if denseRatio > 0.5
%                 TopoNext = ratio > (obj.thsTopo/3);
%             elseif denseRatio > 0.3
%                 TopoNext = ratio > (obj.thsTopo/3);
%             else
%                 TopoNext = ratio > obj.thsTopo;
%             end
            
            % we use the bound to help us
            ratioB1 = abs(bsxfun(@rdivide, obj.boundA.G, diagEle));
            ratioB2 = abs(bsxfun(@rdivide, obj.boundA.G, diagEle'));
            ratioB = max(ratioB1, ratioB2);
            ratioB = ratioB + eye(obj.numBus);
                
            if denseRatio > 0.5
%                 TopoNext = (ratio > (obj.thsTopo/3)) | (ratioB >obj.thsTopo);
%             elseif denseRatio > 0.3
                TopoNext = ratio > (obj.thsTopo/2) | (ratioB >obj.thsTopo/1.2);%原来没有/1.1
            else
                TopoNext = ratio > obj.thsTopo | (ratioB >obj.thsTopo);%原来乘以1.5
            end
            
%             TopoNext = obj.disconnection(obj.Topo-TopoNext, TopoNext);
            
            if sum(obj.matOfColDE(TopoNext)) >= obj.numBus-1
                numDisconnect = sum(sum(triu(obj.Topo) - triu(TopoNext)));
                TopoMissConnect = sum(sum(~TopoNext & obj.data.G))/2;
                % examine the disconnection 
                fprintf('We disconnect %d branches, with %d branches wrong\n', numDisconnect, TopoMissConnect);
                obj.Topo = TopoNext;
                obj.Tvec = logical(obj.matOfColDE(obj.Topo));
                if numDisconnect > 0
%                     obj.dataO.G = obj.dataE.G;
%                     obj.dataO.B = obj.dataE.B;
%                     obj.dataO.G(~obj.Topo) = 0;
%                     obj.dataO.B(~obj.Topo) = 0;
                    
%                     obj.dataO.Vm = obj.data.Vm;
%         %             obj.dataO.Va = obj.data.Va;
%                     obj.dataO.Vm(2:end, :) = bsxfun(@times, obj.data.Vm_noised(2:end, :), obj.isMeasure.Vm(2:end));
%                     obj.dataO.Vm(obj.dataO.Vm == 0) = 1;
%         %             obj.dataO.Va = bsxfun(@times, obj.data.Va_noised, obj.isMeasure.Va);
%                     obj.dataO.P = obj.data.P_noised;
%                     obj.dataO.Q = obj.data.Q_noised;
%                     obj.dataO.Va = zeros(obj.numBus, obj.numSnap);
%                     obj = updateParPF(obj);
%                     obj.dataO.Va(obj.isMeasure.Va, :) = obj.data.Va_noised(obj.isMeasure.Va, :);
                end
            else
                numDisconnect = 0;
            end
%             ratioN = obj.dataO.G>0;
%             ratioN(logical(eye(size(ratioN)))) = false;
%             obj.dataO.G(ratioN) = 0;
%             obj.dataO.B(ratioN) = 0;
            % we update some hyper-parameters
            obj.numGrad.del = sum(~obj.Tvec);
            if numDisconnect == 0
                if obj.updateRatio == obj.updateRatioLast
                    obj.isConverge = 3;
                else
                    ratioN = obj.dataO.G>0;
                    ratioN(logical(eye(size(ratioN)))) = false;
                    if sum(sum(ratioN)) > 0
                        if denseRatio > 0.5
                            eta = obj.thsTopo/4;
                        else
                            eta = obj.thsTopo*2;
                        end
                        group1 = ratioN & ratio>eta;
                        group2 = ratioN & ratio<eta;
                        if sum(sum(group2)) > 0
                            TopoNext = TopoNext & ~group2;
%                             TopoNext = obj.disconnection(obj.Topo-TopoNext, TopoNext);
                            if sum(obj.matOfColDE(TopoNext)) >= obj.numBus-1
                                numDisconnect = sum(sum(triu(obj.Topo) - triu(TopoNext)));
                                TopoMissConnect = sum(sum(~TopoNext & obj.data.G));
                                fprintf('We disconnect %d branches, with %d branches wrong\n', numDisconnect, TopoMissConnect);
                                obj.Topo = TopoNext;
                                obj.Tvec = logical(obj.matOfColDE(obj.Topo));
                                obj.numGrad.del = sum(~obj.Tvec);
                            end
                        else
                            obj.dataO.G(group1) = obj.dataO.G(group1)*0.99;
                            obj.dataO.B(group1) = obj.dataO.B(group1)*0.99;
                        end
%                         obj.dataO.G(group2) = obj.dataO.G(group2)*0.8;
%                         obj.dataO.B(group2) = obj.dataO.B(group2)*0.8;
                    else
                        obj.updateRatio = obj.updateRatioLast;
                    end
                end
            end
            obj.updateLast = obj.iter;
            obj.step = obj.stepInit;
            obj.vaPseudoWeight = obj.vaPseudoWeightInit;
%             obj = updateParPF(obj);
%             obj.updateLastLoss = obj.lossChain(1, obj.iter);
        end
        
        function obj = evaluateLossMin(obj)
            % This method evalutes the minimum loss
            obj.lossMin = obj.numSnap *...
                sum([obj.isMeasure.P;obj.isMeasure.Q;obj.isMeasure.Vm;obj.isMeasure.Va]);
        end
        
        function obj = updateParLMPower(obj)
            % This method updates the parameters using LM strategies and
            % iteratively updates the GB and VmVa
            % calculate the modified Hessian
            
            % we update all the parameters together
%             id = 1:obj.numGrad.Sum;
%             id_GB = 1:obj.numGrad.G+obj.numGrad.B;
            
            id_GB = [obj.Tvec; obj.Tvec];
            id = [id_GB; true(obj.numGrad.Vm+obj.numGrad.Va, 1)];
            
            % whether jump back to the last step
            if obj.iter-obj.updateLast > 1 && obj.lossChain(1, obj.iter) > obj.lossChain(1, obj.iter-1) * obj.regretRatio % obj.isSecond && 
                obj.isSecond = false;
                obj.isFirst = true;
                obj.iter = obj.iter - 1;
                
%                 delta1 = obj.lastState.delta1 / obj.lastState.step * obj.stepMin;
                delta1 = obj.lastState.delta1 / obj.inRatio;
                delta2 = obj.lastState.delta2;
                maxD1 = obj.lastState.maxD1;
                maxD2 = obj.lastState.maxD2;
                obj.gradPast = obj.lastState.gradPast;
                obj.grad = obj.lastState.grad;
                
%                 obj.step = obj.stepMin;
                obj.step = obj.step / obj.inRatio;
                obj.lambda = obj.lambda * obj.inRatio;
            end
            % update the delta value
            if ~obj.isFirst % the non regret mode
                if obj.iter > 1 + obj.updateLast
%                 try
                    moment = obj.gradPast * obj.momentRatio + obj.grad * (1-obj.momentRatio);
                else
%                 catch
                    moment = obj.grad;
                end
    %             obj.gradPast = moment;
    %             delta1 = obj.step * moment(id);
    % %             delta1 = moment(id);
    %             delta2 = obj.H(id, id) \ obj.gradOrigin(id);
    %             delta = delta1 * obj.lambda/(1+obj.lambda) + delta2 * 1/(1+obj.lambda);

                obj.gradPast = moment;
                delta1 = obj.step * moment(id);
                if ~obj.isLBFGS && ~obj.isLHinv
                    delta2 = obj.H(id, id) \ obj.gradOrigin(id);
                elseif obj.isLHinv
%                     delta2 = (obj.M(id, :) * obj.M(id, :)') \ obj.gradOrigin(id);
                    [obj, delta2] = calLHInv(obj, id);
                else
                    [obj, delta2] = doLBFGS(obj);
                end
                maxD1 = max(abs(delta1));
                maxD2 = max(abs(delta2));
                D2D1Ratio = maxD2/(maxD1/obj.step);
                obj.D2D1Chain(obj.iter) = D2D1Ratio;
    %             maxD1 = mean(abs(delta1(id_GB)));
    %             maxD2 = mean(abs(delta2(id_GB)));
    %             delta = delta1 + delta2 / maxD2 * maxD1 * obj.second;
    %             obj.secondMax = maxD2 / maxD1;
    %             disp(obj.second);
                disp(obj.loss.total / 1e10);
                ratio = maxD2 / maxD1;
                obj.ratioChain(obj.iter) = ratio / (obj.lambda * obj.ratioMax);
                
                obj.lastState.delta1 = delta1;
                obj.lastState.delta2 = delta2;
                obj.lastState.maxD1 = maxD1;
                obj.lastState.maxD2 = maxD2;
                obj.lastState.gradPast = obj.gradPast;
                obj.lastState.moment = moment;
                obj.lastState.grad = obj.grad;
                obj.lastState.step = obj.step;
                    
                if ratio > obj.lambda * obj.ratioMax % first order mode
%                     obj.lambda = obj.lambdaCompen * ratio / obj.ratioMax;
                    disp('first order mode')
                    obj.isBoundChain(obj.iter) = true;
                    obj.isSecond = false;
                    obj.lambda = min(obj.lambda * obj.inRatio, obj.lambdaMax);
                    
                    delta = delta1;
                else % second order mode
                    disp('second order mode')
                    obj.isSecond = true;
%                     delta = delta2;
                    delta = delta1 * obj.lambda/(1+obj.lambda) + delta2 * 1/(1+obj.lambda);
                end
            else % the regret mode
%                 ratio = maxD2 / maxD1;
%                 obj.lambda = obj.lambdaCompen * ratio / obj.ratioMax;
                disp('regret mode')
                obj.isBoundChain(obj.iter) = true;
                
                delta = obj.step * obj.grad(id);
%                 delta = delta1;
            end
            
            disp(obj.lambda);
            
%             delta = delta2;
            obj.lambdaChain(obj.iter) = obj.lambda;
            par = zeros(obj.numGrad.Sum, 1);
            
            par(id) = obj.parChain(id, obj.iter) - delta;
            G = par(1:obj.numGrad.G);
            B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
%             G(G>0) = 0;
%             B(B<0) = 0;
            obj.dataO.G = obj.colToMatDE(G, obj.numBus);
            obj.dataO.B = obj.colToMatDE(B, obj.numBus);
            VmVa = reshape(par(1+obj.numGrad.G+obj.numGrad.B:end), 2*(obj.numBus-1), obj.numSnap);
            obj.dataO.Vm(2:end, :) = VmVa(1:obj.numBus-1, :);
            obj.dataO.Va(2:end, :) = VmVa(obj.numBus:end, :);
            
%             if obj.isGB
% %                 delta = zeros(obj.numGrad.G+obj.numGrad.B, 1);
% %                 id = [obj.Tvec; obj.Tvec];
%                 id = 1:obj.numGrad.G+obj.numGrad.B;
%                 delta = H1(id, id) \ obj.gradOrigin(id);
%                 % converge or not
%                 if (max(abs(delta)) < 1e-5)
%                     obj.isConverge = obj.isConverge + 1;
%                 else
%                     obj.isConverge = 0;
%                 end
%                 obj.isGB = false;
%                 % update the parameters
%                 par = zeros(obj.numGrad.Sum, 1);
%                 par(id) = obj.parChain(id, obj.iter) - delta(id);
%                 G = par(1:obj.numGrad.G);
%                 B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
%                 G(G>0) = 0;
%                 B(B<0) = 0;
%                 obj.dataO.G = obj.colToMatDE(G, obj.numBus);
%                 obj.dataO.B = obj.colToMatDE(B, obj.numBus);
%             else
%                 id = 1+obj.numGrad.B+obj.numGrad.G:obj.numGrad.Sum;
%                 delta = H1(id, id) \ obj.gradOrigin(id);
%                 % converge or not
%                 if (max(abs(delta)) < 1e-9)
%                     obj.isConverge = obj.isConverge + 1;
%                 else
%                     obj.isConverge = 0;
%                 end
%                 obj.isGB = true;
%                 % update the paramters
%                 par = zeros(obj.numGrad.Sum, 1);
%                 par(id) = obj.parChain(id, obj.iter) - delta;
%                 Vm = par(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm);
%                 Va = par(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end);
%                 obj.dataO.Vm(2:end, :) = reshape(Vm, [], obj.numBus-1)'; % exclude the source bus
%                 obj.dataO.Va(2:end, :) = reshape(Va, [], obj.numBus-1)'; % exclude the source bus
%             end
            % update the lambda and the step length
            if ~obj.isFirst
                if obj.iter > 1 + obj.updateLast
                    if obj.lossChain(1, obj.iter) < obj.lossChain(1, obj.iter-1)
    %                     ratio = (obj.lossChain(1, obj.iter-1) / obj.lossChain(1, obj.iter));
                        obj.step = min(obj.step * obj.deRatio, obj.stepMax);
                        obj.lambda = max(obj.lambda / obj.deRatio, obj.lambdaMin);
                        obj.lambda = min(obj.lambda, obj.lambdaMax);
                        obj.momentRatio = min(obj.momentRatio * obj.inRatio, obj.momentRatioMax);
    %                     obj.ratioMax = min(obj.ratioMax * obj.inRatio, obj.ratioMaxMax);
    %                     obj.second = min(obj.second * obj.inRatio, obj.secondMax);
                    else
    %                     ratio = (obj.lossChain(1, obj.iter) / obj.lossChain(1, obj.iter-1))^2;

                        obj.step = max(obj.step / obj.inRatio, obj.stepMin);
                        obj.lambda = min(obj.lambda * obj.inRatio, obj.lambdaMax);
    %                     obj.ratioMax = max(obj.ratioMax / obj.inRatio, obj.ratioMaxMin);
    %                     obj.second = max(obj.second / obj.inRatio, obj.secondMin);
    %                     ratio = log10(max(obj.loss.total, obj.lossMin * 10) / obj.lossMin);
    %                     dRatio = 10/ratio;
    %                     obj.lambda = min(obj.lambda * (1.1+dRatio), obj.lambdaMax);
    %                     obj.step = max(obj.step / (1.1+dRatio), obj.stepMin);
                    end
                end
            end
%             if obj.iter > 1 % I think we should use PD control here, currently it is only D control
%                 if obj.loss.total < obj.momentLoss
%                     obj.step = min(obj.step * obj.deRatio, obj.stepMax);
%                     obj.lambda = max(obj.lambda / obj.deRatio, obj.lambdaMin);
%                     obj.lambda = min(obj.lambda, obj.lambdaMax);
%                     obj.momentRatio = min(obj.momentRatio * obj.inRatio, obj.momentRatioMax);
%                 else
%                     obj.step = max(obj.step / obj.deRatio, obj.stepMin);
%                     obj.lambda = min(obj.lambda * obj.deRatio, obj.lambdaMax);
%                 end
%                 obj.momentLoss = obj.momentLoss * 0.1 + obj.loss.total * (1-0.1);
%             else
%                 obj.momentLoss = obj.loss.total;
%             end
%             obj.isFirst = false;
            obj.stepChain(obj.iter) = obj.step;
            obj.ratioMax = log10(obj.loss.total/obj.lossMin) * obj.ratioMaxConst;
            obj.ratioMax = max(obj.ratioMaxConst, obj.ratioMax);
            obj.ratioMaxChain(obj.iter) = obj.ratioMax;
            obj.maxD2Chain(obj.iter) = maxD2;
            
            % adjust vaPseudoWeight
            if obj.iter > 1 + obj.updateLast && maxD2 > obj.maxD2Upper
                obj.vaPseudoWeight = 1;
            end
%             if maxD2 > obj.maxD2Upper
%                 obj.vaPseudoWeight = max(obj.vaPseudoMin, obj.vaPseudoWeight / obj.inRatio);
%             elseif maxD2 < obj.maxD2Lower
%                 obj.vaPseudoWeight = min(obj.vaPseudoMax, obj.vaPseudoWeight * obj.inRatio);
%             end
%             obj.vaPseudoWeight = 10 / log10(obj.loss.total / obj.lossMin);

%             obj.secondChain(obj.iter) = obj.second;   
%             obj.lambdaMax = log10(max(obj.loss.total, obj.lossMin * 10) / obj.lossMin) * 1000;
            % converge or not
%             if obj.loss.total < obj.lossMin
%                 obj.isConverge = 3;
%             end
        end
        
        function [obj, delta] = calLHInv(obj, id)
            % This method calculate the d = H\g in a memory saving manner
            % We firstly divide the matrix
%             profile on
%             deltaTrue = (obj.M * obj.M') \ obj.gradOrigin;
            
            % split the matrices
            numMea = size(obj.M, 2);
            numGB = obj.numGrad.G+obj.numGrad.B-2*obj.numGrad.del;
            idSplit = [numGB ones(1, obj.numSnap)*2*(obj.numBus-1)];
            obj.M = mat2cell(obj.M(id, :), idSplit, numMea);
            gradSplit = mat2cell(obj.gradOrigin(id), idSplit, 1);
            A = full(obj.M{1}*obj.M{1}');
            
            % calculate the value of x_1 or deltaGB
            % x_1 = (A-B/CB')\(g_1-B/Cg_2)
            invC = cellfun(@(m) inv(full(m*m')), obj.M(2:end), 'UniformOutput', false);
%             deltaVaVmSplit = cell(obj.numSnap, 1);
%             deltaSplit = cellfun(@(m, g) (m*m')\g, obj.M, gradSplit, 'UniformOutput', false);
            BCB = zeros(numGB); % B/CB'
            BCg = zeros(numGB, 1); % B/Cg_2
            BCBCell = cell(obj.numSnap, 1);
            for i = 1:obj.numSnap
                B = full(obj.M{1} * obj.M{i+1}');
                BC = B*invC{i};
                BCBCell{i} = BC*B';
                BCB = BCB + BC*B';
                BCg = BCg + BC*gradSplit{i+1};
            end
            if ~obj.isPHinv
                deltaGB = (A - BCB) \ (gradSplit{1} - BCg);
                deltaGBn = deltaGB;
            else
                ABCB = A - BCB;
                obj.isIll = false;
                invABCB = pinv(ABCB);
                deltaGBn = invABCB * (gradSplit{1} - BCg);
                deltaGB = deltaGBn;
                if max(abs(deltaGB)) > obj.prior.Gmax/2
                    disp('the ABCB matrix is ill-conditioned');
                    obj.isIll = true;
                end
            end
            
            % calculate the value of x_2 or deltaVmVa
            deltaVmVa = cell(obj.numSnap, 1);
            for i = 1:obj.numSnap
                B = full(obj.M{1} * obj.M{i+1}');
                deltaVmVa{i} = invC{i}*(gradSplit{i+1}-B'*deltaGB); % we do not use the accurate form, can be improved
            end
%             deltaVmVa = cellfun(@(invc, gVmVa, m) invc*(gVmVa-full(m*obj.M{1}')*deltaGB), invC, gradSplit(2:end), obj.M(2:end), 'UniformOutput', false);
            deltaVmVa = cell2mat(deltaVmVa);
            delta = [deltaGBn; deltaVmVa];
            
%             profile off;
%             profile viewer;
        end
        
        function [obj, delta] = doLBFGS(obj)
            % This method conduct the L-BFGS algorithm to update the delta
            % value using far less memory
            if obj.iter == 1
                delta = obj.gradOrigin;
                return;
            end
            
            % begin the iteration loop
            k = obj.iter;
            m = obj.numEstH;
            id_GB = [obj.Tvec; obj.Tvec];
            id = [id_GB; true(obj.numGrad.Vm+obj.numGrad.Va, 1)];
            q = obj.gradOrigin(id);
            alpha = zeros(length(k-1:-1:max(k-m, 1)), 1);
            for i = k-1:-1:max(k-m, 1)
                pt = i-max(k-m, 1)+1;
                alpha(pt) = obj.rhoChain(i) * obj.sChain(id, i)' * q;
                q = q - alpha(pt) * obj.yChain(id, i);
            end
            r = (obj.sChain(id, k-1)' * obj.yChain(id, k-1)) / (obj.yChain(id, k-1)' * obj.yChain(id, k-1));
            H0 = r * speye(sum(id));
            z = H0 * q;
            for i = max(k-m, 1):k-1
                pt = i-max(k-m, 1)+1;
                beta = obj.rhoChain(i) * obj.yChain(id, i)' * z;
                z = z + obj.sChain(id, i) * (alpha(pt) - beta);
            end
            delta = z;
        end
        
        function obj = buildJacobian(obj)
            % This method build the Jacobian matrix
            obj.J = zeros(2 * obj.numBus * obj.numSnap, obj.numGrad.G + obj.numGrad.B + obj.numGrad.Va);
            numP = obj.numBus * obj.numSnap;
            for snap = 1:obj.numSnap
                % calculate some basic parameters at present state
                Theta_ij = repmat(obj.dataO.Va(:, snap), 1, obj.numBus) - repmat(obj.dataO.Va(:, snap)', obj.numBus, 1);
                % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
                GBThetaP = obj.dataO.G .* cos(Theta_ij) + obj.dataO.B .* sin(Theta_ij);
                % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
                GBThetaQ = obj.dataO.G .* sin(Theta_ij) - obj.dataO.B .* cos(Theta_ij);
                for bus = 1:obj.numBus
                    theta_ij = obj.dataO.Va(bus, snap) - obj.dataO.Va(:, snap);
                    % P
                    hP = zeros(obj.numGrad.G + obj.numGrad.B + obj.numGrad.Va, 1);
                    % G matrix
                    H_G = zeros(obj.numBus, obj.numBus);
                    H_G(bus, :) = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
                    H_G(bus, :) = H_G(bus, :) - obj.dataO.Vm(bus, snap)^2; % the equivilance of diagonal elements
                    h_G = obj.matToColDE(H_G);
                    hP(1:obj.numGrad.G) = h_G;

                    % B matrix
                    H_B = zeros(obj.numBus, obj.numBus);
                    H_B(bus, :) = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
                    h_B = obj.matToColDE(H_B);
                    hP(obj.numGrad.G+1:obj.numGrad.G+obj.numGrad.B) = h_B;
                    
                    % Va
                    H_Va = zeros(obj.numBus, obj.numSnap);
                    h_Va = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaQ(:, bus);
                    h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.B(bus, bus)...
                       - obj.data.Q_noised(bus, snap); 
%                     h_Va(bus) = h_Va(bus)-sum(GBThetaQ(bus, :) * obj.dataO.Vm(:, snap) * obj.dataO.Vm(bus, snap));
                    H_Va(:, snap) = h_Va;
                    % remove the source bus whose magnitude is not the state variable
                    H_Va(1, :) = []; 
                    h_VaLarge = reshape(H_Va', [], 1);
                    hP(obj.numGrad.G+obj.numGrad.B+1:end) = h_VaLarge;
                    
                    % Q
                    hQ = zeros(obj.numGrad.G + obj.numGrad.B + obj.numGrad.Va, 1);
                    % G matrix
                    H_G = zeros(obj.numBus, obj.numBus);
                    H_G(bus, :) = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
                    h_G = obj.matToColDE(H_G);
                    hQ(1:obj.numGrad.G) = h_G;

                    % B matrix
                    H_B = zeros(obj.numBus, obj.numBus);
                    H_B(bus, :) = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
                    H_B(bus, :) = H_B(bus, :) + obj.dataO.Vm(bus, snap)^2; % the equivilance of diagonal elements
                    h_B = obj.matToColDE(H_B);
                    hQ(obj.numGrad.G+1:obj.numGrad.G+obj.numGrad.B) = h_B;
                    
                    % Va
                    H_Va = zeros(obj.numBus, obj.numSnap);
                    h_Va = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaP(:, bus);
                    h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.G(bus, bus) ...
                        + obj.data.P_noised(bus, snap);
%                     h_Va(bus) = h_Va(bus)+sum(GBThetaP(bus, :) * obj.dataO.Vm(:, snap) * obj.dataO.Vm(bus, snap));
                    H_Va(:, snap) = h_Va;
                    % remove the source bus whose magnitude is not the state variable
                    H_Va(1, :) = []; 
                    h_VaLarge = reshape(H_Va', [], 1);
                    hQ(obj.numGrad.G+obj.numGrad.B+1:end) = h_VaLarge;
                    
                    obj.J((snap-1)*obj.numBus+bus, :) = hP';
                    obj.J((snap-1)*obj.numBus+bus+numP, :) = hQ';
                end
            end
        end
        
        function obj = updateParPF(obj)
            % This method updates the voltage angles by power flow
            % calculation.
            % We first build the branch matrix
            GB = triu(obj.dataO.G - obj.dataO.B, 1);
            [fBus, tBus] = find(GB);
            branchLoc = find(GB);
            numBranch = length(fBus);
            branch = repmat(obj.mpc.branch(1,:), numBranch, 1);
            branch(:, 1:2) = [fBus, tBus];
            
            y = - obj.dataO.G(branchLoc) - 1j * obj.dataO.B(branchLoc);
            z = 1 ./ y;
            branch(:, 3) = real(z);
            branch(:, 4) = imag(z);
            
            % We then update the bus matrix can do the PF calculations
            mpcO = obj.mpc; 
            mpcO.branch = branch;
%             Y = makeYbus(mpcO);
%             Gtest = real(full(Y));
%             Btest = imag(full(Y));
%             mpcO.bus(mpcO.bus(:, 2) == 2, 2) = 1; % change all PV buses to PQ buses
            mpcO.bus(mpcO.bus(:, 2) == 1, 2) = 2; % change all PQ buses to PV buses
            mpopt = mpoption('verbose',0,'out.all',0);
            
            for snap = 1:obj.numSnap
                mpcO.bus(2:end, 3) = - obj.dataO.P(2:end, snap) * mpcO.baseMVA;
                mpcO.bus(2:end, 4) = - obj.dataO.Q(2:end, snap) * mpcO.baseMVA;
                mpcO.bus(:, 8) = obj.dataO.Vm(:, snap);
                mpcThis = runpf(mpcO, mpopt);
                obj.dataO.Va(:, snap) = mpcThis.bus(:,9)/180*pi;
%                 obj.dataO.Vm(:, snap) = mpcThis.bus(:,8);
            end
        end
        
        function obj = updateParNewton(obj)
            % This method updates the parameters using Newton kings of
            % strategies
%             delta = obj.H \ obj.grad;
%             par = obj.parChain(:, obj.iter) - delta;
            
            delta = obj.H(1:obj.numGrad.B+obj.numGrad.G, 1:obj.numGrad.B+obj.numGrad.G) \ obj.grad(1:obj.numGrad.B+obj.numGrad.G);
            par = zeros(obj.numGrad.Sum, 1);
            par(1:obj.numGrad.B+obj.numGrad.G) = obj.parChain(1:obj.numGrad.B+obj.numGrad.G, obj.iter) - delta;
            
%             delta = obj.H(1+obj.numGrad.B+obj.numGrad.G:end,1+obj.numGrad.B+obj.numGrad.G:end) \ obj.grad(1+obj.numGrad.B+obj.numGrad.G:end);
%             par = zeros(obj.numGrad.Sum, 1);
%             par(1+obj.numGrad.B+obj.numGrad.G:end) = obj.parChain(1+obj.numGrad.B+obj.numGrad.G:end, obj.iter) - delta;
            % gather the par values
            G = par(1:obj.numGrad.G);
            B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
%             G(G>0) = 0;
%             B(B<0) = 0;
            
            obj.dataO.G = obj.colToMatDE(G, obj.numBus);
            obj.dataO.B = obj.colToMatDE(B, obj.numBus);
            Vm = par(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm);
            Va = par(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end);
%             obj.dataO.Vm(2:end, :) = reshape(Vm, [], obj.numBus-1)'; % exclude the source bus
%             obj.dataO.Va(2:end, :) = reshape(Va, [], obj.numBus-1)'; % exclude the source bus
        end
        
        function obj = updateParNewtonGV(obj)
            % This method updates the parameters using Newton strategy by
            % iteratively updating GB and VmVa
            
            if obj.isGB % update GB value, and Va. We also update the topology
                
                % correct the topology
                
                diagEle = sum(abs(obj.dataO.G)) / 2;
                ratio1 = abs(bsxfun(@rdivide, obj.dataO.G, diagEle));
                ratio2 = abs(bsxfun(@rdivide, obj.dataO.G, diagEle'));
                ratio = max(ratio1, ratio2);
                obj.Topo = ratio > obj.thsTopo;
                obj.Tvec = logical(obj.matOfColDE(obj.Topo));
                obj.dataO.G(~obj.Topo) = 0;
                obj.dataO.B(~obj.Topo) = 0;
                
%                 % update GB only
%                 id = [obj.Tvec; obj.Tvec];
%                 delta = zeros(obj.numGrad.G+obj.numGrad.B, 1);
%                 delta(id) = obj.H(id, id) \ obj.grad(id);
                
%                 % update GBVa using state estimation
%                 id = [1:obj.numGrad.B+obj.numGrad.G obj.numGrad.B+obj.numGrad.G+obj.numGrad.Vm+1:obj.numGrad.Sum];
%                 delta = obj.H(id, id) \ obj.grad(id);

                % update GBVa using Pseudo power flow
                deltaP = obj.dataO.P - obj.data.P_noised;
                deltaQ = obj.dataO.Q - obj.data.Q_noised;
                deltaPQ = [reshape(deltaP, [], 1);reshape(deltaQ, [], 1)];
                id = true(obj.numGrad.B+obj.numGrad.G+obj.numGrad.Va, 1);
                id(1:obj.numGrad.G+obj.numGrad.B) = [obj.Tvec; obj.Tvec];
                delta = zeros(obj.numGrad.B+obj.numGrad.G+obj.numGrad.Va, 1);
                delta(id) = pinv(obj.J(:,id)) * deltaPQ;
                
%                 delta = pinv(obj.J) * deltaPQ;
                if (max(abs(delta)) < 1e-2)
                    obj.isGB = false;
                    obj.isConverge = obj.isConverge + 1;
                else
                    obj.isConverge = 0;
                end
%                 obj.isGB = false;
                
                par = zeros(obj.numGrad.Sum, 1);
                id = [obj.Tvec; obj.Tvec];
                par(id) = ...
                    obj.parChain(id, obj.iter) ...
                    - delta(id);
                G = par(1:obj.numGrad.G);
                B = par(1+obj.numGrad.G:obj.numGrad.G+obj.numGrad.B);
                G(G>0) = -max(G)*rand()*0.2;
                B(B<0) = max(B)*rand()*0.2;
                G(G<-300) = -300;
                B(B>300) = 300;
                obj.dataO.G = obj.colToMatDE(G, obj.numBus);
                obj.dataO.B = obj.colToMatDE(B, obj.numBus);


                par(obj.numGrad.B+obj.numGrad.G+obj.numGrad.Vm+1:end) = ...
                    obj.parChain(obj.numGrad.B+obj.numGrad.G+obj.numGrad.Vm+1:end, obj.iter)...
                    - delta(obj.numGrad.B+obj.numGrad.G+1:end);
                Va = par(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end);
                obj.dataO.Va(2:end, :) = reshape(Va, [], obj.numBus-1)'; % exclude the source bus
            else % update VmVa value
                delta = obj.H(1+obj.numGrad.B+obj.numGrad.G:end,1+obj.numGrad.B+obj.numGrad.G:end) \ obj.grad(1+obj.numGrad.B+obj.numGrad.G:end);
                if (max(abs(delta)) < 1e-5)
                    obj.isGB = true;
                    obj.isConverge = obj.isConverge + 1;
                else
                    obj.isConverge = 0;
                end
%                 obj.isGB = true;
                
                par = zeros(obj.numGrad.Sum, 1);
                par(1+obj.numGrad.B+obj.numGrad.G:end) = obj.parChain(1+obj.numGrad.B+obj.numGrad.G:end, obj.iter) - delta;
                Vm = par(1+obj.numGrad.G+obj.numGrad.B:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm);
                Va = par(1+obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm:end);
                obj.dataO.Vm(2:end, :) = reshape(Vm, [], obj.numBus-1)'; % exclude the source bus
                obj.dataO.Va(2:end, :) = reshape(Va, [], obj.numBus-1)'; % exclude the source bus
            end
            
            % update PQ
            for i = 1:obj.numSnap
                % calculate some basic parameters at present state
                Theta_ij = repmat(obj.dataO.Va(:, i), 1, obj.numBus) - repmat(obj.dataO.Va(:, i)', obj.numBus, 1);
                % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
                GBThetaP = obj.dataO.G .* cos(Theta_ij) + obj.dataO.B .* sin(Theta_ij);
                % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
                GBThetaQ = obj.dataO.G .* sin(Theta_ij) - obj.dataO.B .* cos(Theta_ij);
                % P estimate
                Pest = (GBThetaP * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                obj.dataO.P(:, i) = Pest;
                % Q estimate
                Qest = (GBThetaQ * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                obj.dataO.Q(:, i) = Qest;
            end
        end
        
        function obj = buildMeasure(obj)
            % build the measurement matrix
            % clear some matrices to get enough memory
            obj.A_FIM = [];
            obj.FIM = [];
            obj.numMeasure = obj.numSnap *...
                sum([obj.isMeasure.P;obj.isMeasure.Q;obj.isMeasure.Vm;obj.isMeasure.Va]);
%             obj.M = zeros(obj.numGrad.Sum, obj.numMeasure);
            % Initialize the gradient matrix
            obj.grad = zeros(obj.numGrad.Sum, 1);
            obj.gradP = zeros(obj.numGrad.Sum, 1);
            obj.gradQ = zeros(obj.numGrad.Sum, 1);
            obj.gradVm = zeros(obj.numGrad.Sum, 1);
            obj.gradVa = zeros(obj.numGrad.Sum, 1);
            % Initialize the loss
            obj.loss.total = 0;
            obj.loss.P = 0;
            obj.loss.Q = 0;
            obj.loss.Vm = 0;
            obj.loss.Va = 0;
            
            %initialize the sparsify measurement matrix
            if ~obj.isLBFGS
                numVector = obj.numSnap * obj.numBus * ((obj.numBus-1)*4*2 + 2);
                obj.mRow = zeros(1, numVector);
                obj.mCol = zeros(1, numVector);
                obj.mVal = zeros(1, numVector);
                obj.spt = 1;
            end
%             numVector = obj.numSnap * obj.numBus * ((obj.numBus-1)*4*2 + 2);
%             obj.mRow = zeros(1, numVector);
%             obj.mCol = zeros(1, numVector);
%             obj.mVal = zeros(1, numVector);
%             obj.spt = 1;
            
            % Initialize the idGB
            obj.idGB = zeros(obj.numBus, obj.numBus);
            id = 1;
            for i = 1:obj.numBus
                obj.idGB(i, i+1:end) = id:id+obj.numBus-i-1;
                obj.idGB(i+1:end, i) = id:id+obj.numBus-i-1;
                id = id+obj.numBus-i;
            end
            pt = 1;
            
            % start the loop
            for i = 1:obj.numSnap
                % calculate some basic parameters at present state
                Theta_ij = repmat(obj.dataO.Va(:, i), 1, obj.numBus) - repmat(obj.dataO.Va(:, i)', obj.numBus, 1);
                % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
                GBThetaP = obj.dataO.G .* cos(Theta_ij) + obj.dataO.B .* sin(Theta_ij);
                % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
                GBThetaQ = obj.dataO.G .* sin(Theta_ij) - obj.dataO.B .* cos(Theta_ij);
                % P estimate
                Pest = (GBThetaP * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                obj.dataO.P(:, i) = Pest;
                % Q estimate
                Qest = (GBThetaQ * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                obj.dataO.Q(:, i) = Pest;
                % the id of Vm and Va
                obj.idVm = 2*(obj.numBus-1)*(i-1)+1 : 2*(obj.numBus-1)*(i-1)+obj.numBus-1;
                obj.idVa = 2*(obj.numBus-1)*(i-1)+obj.numBus : 2*(obj.numBus-1)*(i-1)+2*obj.numBus-2;
                % calculate the sub-vector of P of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.P(j)
                        obj = buildMeasureP(obj, i, j, GBThetaP, GBThetaQ, Pest, pt);
%                         R(pt) = obj.sigma.P(j).^(-1);
                        pt = pt + 1;
                    end
                end
                
                % calculate the sub-vector of Q of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Q(j)
                        obj = buildMeasureQ(obj, i, j, GBThetaP, GBThetaQ, Qest, pt);
%                         R(pt) = obj.sigma.Q(j).^(-1);
                        pt = pt + 1;
                    end
                end
                
                % calculate the sub-vector of Vm of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Vm(j)
                        obj = buildMeasureVm(obj, i, j, pt);
%                         R(pt) = obj.sigma.Vm(j).^(-1);
                        pt = pt + 1;
                    end
                end
                
                % calculate the sub-vector of Va of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Va(j)
                        obj = buildMeasureVa(obj, i, j, pt);
%                         R(pt) = obj.sigma.Va(j).^(-1);
                        pt = pt + 1;
                    elseif j > 1 % we can add a judgement here
                        if obj.vaPseudoWeight < 50
                            if ~obj.isLBFGS
                                l = 1;
                                obj.mRow(obj.spt:obj.spt+l-1) = obj.numGrad.G+obj.numGrad.B+obj.idVa(j-1);
                                obj.mCol(obj.spt:obj.spt+l-1) = pt;
                                obj.mVal(obj.spt:obj.spt+l-1) = (obj.sigma.Va(j)*obj.vaPseudoWeight).^(-1);
                                obj.spt = obj.spt + l;
                            else
                                obj.M(obj.numGrad.G+obj.numGrad.B+obj.idVa(j-1), pt) ...
                                    = (obj.sigma.Va(j)*obj.vaPseudoWeight).^(-1);
                            end
                            pt = pt + 1;
                        end
                    end
                end
            end
            
%             assert (pt -1 == obj.numMeasure);
            
            % collect the gradients, the losses, and compute the Hessian
            obj.grad = obj.gradP + obj.gradQ + obj.gradVm + obj.gradVa;
            obj.loss.total = obj.loss.P + obj.loss.Q + obj.loss.Vm + obj.loss.Va;
            if ~obj.isLBFGS
                obj.mRow(obj.spt:end) = [];
                obj.mCol(obj.spt:end) = [];
                obj.mVal(obj.spt:end) = [];
                Ms = sparse(obj.mRow, obj.mCol, obj.mVal);%, obj.numFIM.Sum, obj.numMeasure);
                if ~obj.isLHinv
                    obj.H = Ms * Ms';
                else
                    obj.M = Ms;
                end
            elseif obj.iter > 1 % update the sChain and the yChain
                id_GB = [obj.Tvec; obj.Tvec];
                id = [id_GB; true(obj.numGrad.Vm+obj.numGrad.Va, 1)];
                obj.sChain(id, obj.iter-1) = obj.parChain(id, obj.iter) - obj.parChain(id, obj.iter-1);
                test = obj.grad(id) - obj.gradOrigin(id);
                if sum(abs(test)) > 1e-5
                    obj.yChain(id, obj.iter-1) = test;
                end
                obj.rhoChain(obj.iter-1) = 1/(obj.yChain(id, obj.iter-1)' * obj.sChain(id, obj.iter-1));
            end
%             obj.mRow(obj.spt:end) = [];
%             obj.mCol(obj.spt:end) = [];
%             obj.mVal(obj.spt:end) = [];
%             Ms = sparse(obj.mRow, obj.mCol, obj.mVal, obj.numFIM.Sum, obj.numMeasure);
%             obj.H = Ms * Ms';
        end
        
        function obj = buildMeasureP(obj, snap, bus, GBThetaP, GBThetaQ, Pest, pt)
            % This method builds the <ea from the measurement of P
            
            theta_ij = obj.dataO.Va(bus, snap) - obj.dataO.Va(:, snap);
            g = zeros(obj.numGrad.Sum, 1);
            
            % G matrix           
            h_GG = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
            h_GG = h_GG -  obj.dataO.Vm(bus, snap)^2;
            g(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
            
            % B matrix
            h_BB = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
            g(obj.numGrad.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
            
            
            % Vm
            % the first order term of other Vm
            h_Vm = obj.dataO.Vm(bus, snap) * GBThetaP(:, bus);
%             % the second order term of Vm(bus)
%             h_Vm(bus) = 2*obj.dataO.Vm(bus, snap) * GBThetaP(bus, bus);
%             % the first order term of Vm(bus)
%             fOrderVm = obj.dataO.Vm(:, snap) .* GBThetaP(:, bus);
%             fOrderVm(bus) = 0;
%             h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            h_Vm(bus) = obj.dataO.G(bus, bus) * obj.dataO.Vm(bus, snap) ...
                + obj.data.P_noised(bus, snap) / obj.dataO.Vm(bus, snap);
            g(obj.numGrad.G+obj.numGrad.B+obj.idVm) = h_Vm(2:end);
            
            % Va
            h_Va = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaQ(:, bus);
            h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.B(bus, bus)...
                       - obj.data.Q_noised(bus, snap); 
%             h_Va(bus) = h_Va(bus)-sum(GBThetaQ(bus, :) * obj.dataO.Vm(:, snap) * obj.dataO.Vm(bus, snap));
            g(obj.numGrad.G+obj.numGrad.B+obj.idVa) = h_Va(2:end);
            
            % build HP, gradP and loss.P
            lossThis = (Pest(bus) - obj.data.P_noised(bus, snap));
            obj.loss.P = obj.loss.P + lossThis^2 * obj.sigma.P(bus).^(-2);
            gradPThis = obj.sigma.P(bus).^(-2) * lossThis * g;
%             gradPThis = obj.sigma.P(bus).^(-2) * lossThis * obj.M(:, pt);
            obj.gradP = obj.gradP + gradPThis;
%             obj.M(:, pt) = obj.sigma.P(bus).^(-1)* obj.M(:, pt);
%             g = obj.sigma.P(bus).^(-1) * g;
%             assert(sum(abs(g-obj.M(:, pt))) < 1e-9);
%             obj.M(:, pt) = obj.sigma.P(bus).^(-1) * g;
            if ~obj.isLBFGS
                [row,col,val] = find(g);
                l = length(val);
                obj.mRow(obj.spt:obj.spt+l-1) = row;
                obj.mCol(obj.spt:obj.spt+l-1) = col*pt;
                obj.mVal(obj.spt:obj.spt+l-1) = val*obj.sigma.P(bus).^(-1);
                obj.spt = obj.spt + l;
            end
        end
        
        function obj = buildMeasureQ(obj, snap, bus, GBThetaP, GBThetaQ, Qest, pt)
            % This method builds the Hessian from the measurement of Q
            
            theta_ij = obj.dataO.Va(bus, snap) - obj.dataO.Va(:, snap);
            g = zeros(obj.numGrad.Sum, 1);
            
            % G matrix
            h_GG = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
            g(obj.idGB(bus, [1:bus-1 bus+1:end])) = h_GG([1:bus-1 bus+1:end]);
            
            % B matrix
            h_BB = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
            h_BB = h_BB + obj.dataO.Vm(bus, snap)^2; % the equivilance of diagonal elements
            g(obj.numGrad.G+obj.idGB(bus, [1:bus-1 bus+1:end])) = h_BB([1:bus-1 bus+1:end]);
            
            % Vm
            % the first order term of other Vm
            h_Vm = obj.dataO.Vm(bus, snap) * GBThetaQ(:, bus);
%             % the second order term of Vm(bus)
%             h_Vm(bus) = 2*obj.dataO.Vm(bus, snap) * GBThetaQ(bus, bus);
%             % the first order term of Vm(bus)
%             fOrderVm = obj.dataO.Vm(:, snap) .* GBThetaQ(:, bus);
%             fOrderVm(bus) = 0;
%             h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            h_Vm(bus) = - obj.dataO.B(bus, bus) * obj.dataO.Vm(bus, snap) ...
                + obj.data.Q_noised(bus, snap) / obj.dataO.Vm(bus, snap);
            g(obj.numGrad.G+obj.numGrad.B+obj.idVm) = h_Vm(2:end);
            
            % Va
            h_Va = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaP(:, bus);
            h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.G(bus, bus) ...
                        + obj.data.P_noised(bus, snap);
            g(obj.numGrad.G+obj.numGrad.B+obj.idVa) = h_Va(2:end);
            
            % build HQ, GradientQ and lossQ
            lossThis = (Qest(bus) - obj.data.Q_noised(bus, snap));
            obj.loss.Q = obj.loss.Q + lossThis^2 * obj.sigma.Q(bus).^(-2);
            gradQThis = obj.sigma.Q(bus).^(-2) * lossThis * g;
            obj.gradQ = obj.gradQ + gradQThis;
%             obj.M(:, pt) = obj.sigma.Q(bus).^(-1) * g;
            if ~obj.isLBFGS
                [row,col,val] = find(g);
                l = length(val);
                obj.mRow(obj.spt:obj.spt+l-1) = row;
                obj.mCol(obj.spt:obj.spt+l-1) = col*pt;
                obj.mVal(obj.spt:obj.spt+l-1) = val*obj.sigma.Q(bus).^(-1);
                obj.spt = obj.spt + l;
            end
%             HQThis = obj.sigma.Q(bus).^(-2) * (g * g');
%             obj.HQ = obj.HQ + HQThis;
        end
        
        function obj = buildMeasureVm(obj, snap, bus, pt)
            % This method builds the measurement matrix from the measurement of Vm
            
            % build GradientVm and lossVm
            lossThis = (obj.dataO.Vm(bus, snap) - obj.data.Vm_noised(bus, snap));
            obj.loss.Vm = obj.loss.Vm + lossThis^2 * obj.sigma.Vm(bus).^(-2);
            obj.gradVm(obj.numGrad.G+obj.numGrad.B+obj.idVm(bus-1)) = ...
                obj.gradVm(obj.numGrad.G+obj.numGrad.B+obj.idVm(bus-1)) + obj.sigma.Vm(bus).^(-2) * lossThis;
%             obj.M(obj.numGrad.G+obj.numGrad.B+obj.idVmVa(bus-1), pt) = obj.sigma.Vm(bus).^(-1);
            if ~obj.isLBFGS
                l = 1;
                obj.mRow(obj.spt:obj.spt+l-1) = obj.numGrad.G+obj.numGrad.B+obj.idVm(bus-1);
                obj.mCol(obj.spt:obj.spt+l-1) = pt;
                obj.mVal(obj.spt:obj.spt+l-1) = obj.sigma.Vm(bus).^(-1);
                obj.spt = obj.spt + l;
            end
        end
        
        function obj = buildMeasureVa(obj, snap, bus, pt)
            % This method builds the measurement matrix from the measurement of Va
            
            % build HVa, GradientVa and lossVa
            lossThis = (obj.dataO.Va(bus, snap) - obj.data.Va_noised(bus, snap));
            obj.loss.Va = obj.loss.Va + lossThis^2 * obj.sigma.Va(bus).^(-2);
            obj.gradVa(obj.numGrad.G+obj.numGrad.B+obj.idVa(bus-1)) = ...
                obj.gradVa(obj.numGrad.G+obj.numGrad.B+obj.idVa(bus-1)) + obj.sigma.Va(bus).^(-2) * lossThis;
%             obj.M(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+obj.idVmVa(bus-1), pt) = obj.sigma.Va(bus).^(-1);
            if ~obj.isLBFGS
                l = 1;
                obj.mRow(obj.spt:obj.spt+l-1) = obj.numGrad.G+obj.numGrad.B+obj.idVa(bus-1);
                obj.mCol(obj.spt:obj.spt+l-1) = pt;
                obj.mVal(obj.spt:obj.spt+l-1) = obj.sigma.Va(bus).^(-1);
                obj.spt = obj.spt + l;
            end
        end
        
        function obj = buildHessian(obj)
            % This method builds the Hessian matrix
            obj.H = zeros(obj.numGrad.Sum, obj.numGrad.Sum);
            obj.HP = sparse(obj.numGrad.Sum, obj.numGrad.Sum);
            obj.HQ = sparse(obj.numGrad.Sum, obj.numGrad.Sum);
            obj.HVm = sparse(obj.numGrad.Sum, obj.numGrad.Sum);
            obj.HVa = sparse(obj.numGrad.Sum, obj.numGrad.Sum);
            
            obj.grad = zeros(obj.numGrad.Sum, 1);
            obj.gradP = sparse(obj.numGrad.Sum, 1);
            obj.gradQ = sparse(obj.numGrad.Sum, 1);
            obj.gradVm = sparse(obj.numGrad.Sum, 1);
            obj.gradVa = sparse(obj.numGrad.Sum, 1);
            
            obj.loss.total = 0;
            obj.loss.P = 0;
            obj.loss.Q = 0;
            obj.loss.Vm = 0;
            obj.loss.Va = 0;
            
            for i = 1:obj.numSnap
                % calculate some basic parameters at present state
                Theta_ij = repmat(obj.dataO.Va(:, i), 1, obj.numBus) - repmat(obj.dataO.Va(:, i)', obj.numBus, 1);
                % G_ij\cos(\Theta_ij)+B_ij\sin(\Theta_ij)
                GBThetaP = obj.dataO.G .* cos(Theta_ij) + obj.dataO.B .* sin(Theta_ij);
                % G_ij\sin(\Theta_ij)-B_ij\cos(\Theta_ij)
                GBThetaQ = obj.dataO.G .* sin(Theta_ij) - obj.dataO.B .* cos(Theta_ij);
                % P estimate
                Pest = (GBThetaP * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                obj.dataO.P(:, i) = Pest;
                % Q estimate
                Qest = (GBThetaQ * obj.dataO.Vm(:, i)) .* obj.dataO.Vm(:, i);
                obj.dataO.Q(:, i) = Qest;
                
                % calculate the sub-matrix of P of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.P(j)
                        obj = buildHessianP(obj, i, j, GBThetaP, GBThetaQ, Pest);
                    end
                end
                
                % calculate the sub-matrix of Q of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Q(j)
                        obj = buildHessianQ(obj, i, j, GBThetaP, GBThetaQ, Qest);
                    end
                end
                
                % calculate the sub-matrix of Vm of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Vm(j)
                        obj = buildHessianVm(obj, i, j);
                    end
                end
                
                % calculate the sub-matrix of Va of all buses
                for j = 1:obj.numBus
                    if obj.isMeasure.Va(j)
                        obj = buildHessianVa(obj, i, j);
                    end
                end
            end
            
            % collect the Hessians, gradients and the losses
            obj.H = full(obj.HP + obj.HQ + obj.HVm + obj.HVa);
            obj.gradP = full(obj.gradP);
            obj.gradQ = full(obj.gradQ);
            obj.gradVm = full(obj.gradVm);
            obj.gradVa = full(obj.gradVa);
            obj.grad = obj.gradP + obj.gradQ + obj.gradVm + obj.gradVa;
            obj.loss.total = obj.loss.P + obj.loss.Q + obj.loss.Vm + obj.loss.Va;
        end
        
        function obj = buildHessianP(obj, snap, bus, GBThetaP, GBThetaQ, Pest)
            % This method builds the Hessian from the measurement of P
            
            theta_ij = obj.dataO.Va(bus, snap) - obj.dataO.Va(:, snap);
            g = sparse(obj.numGrad.Sum, 1);
            
            % G matrix
            H_G = zeros(obj.numBus, obj.numBus);
            H_G(bus, :) = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
            H_G(bus, :) = H_G(bus, :) - obj.dataO.Vm(bus, snap)^2; % the equivilance of diagonal elements
            h_G = obj.matToColDE(H_G);
            g(1:obj.numGrad.G) = h_G;
            
            % B matrix
            H_B = zeros(obj.numBus, obj.numBus);
            H_B(bus, :) = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
            h_B = obj.matToColDE(H_B);
            g(obj.numGrad.G+1:obj.numGrad.G+obj.numGrad.B) = h_B;
            
            % Vm
            % the first order term of other Vm
            H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.dataO.Vm(bus, snap) * GBThetaP(:, bus);
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.dataO.Vm(bus, snap) * GBThetaP(bus, bus);
            % the first order term of Vm(bus)
            fOrderVm = obj.dataO.Vm(:, snap) .* GBThetaP(:, bus);
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            H_Vm(:, snap) = h_Vm;
            % remove the source bus whose magnitude is not the state variable
            H_Vm(1, :) = []; 
            h_VmLarge = reshape(H_Vm', [], 1);
            g(obj.numGrad.G+obj.numGrad.B+1:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = h_VmLarge;
            
            % Va
            H_Va = zeros(obj.numBus, obj.numSnap);
            h_Va = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaQ(:, bus);
            h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.B(bus, bus)...
                       - obj.data.Q_noised(bus, snap); 
%             h_Va(bus) = h_Va(bus)-sum(GBThetaQ(bus, :) * obj.dataO.Vm(:, snap) * obj.dataO.Vm(bus, snap));
            H_Va(:, snap) = h_Va;
            % remove the source bus whose magnitude is not the state variable
            H_Va(1, :) = []; 
            h_VaLarge = reshape(H_Va', [], 1);
            g(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+1:end) = h_VaLarge;
            
            % build HP, gradP and loss.P
            lossThis = (Pest(bus) - obj.data.P_noised(bus, snap));
            obj.loss.P = obj.loss.P + lossThis^2 * obj.sigma.P(bus).^(-2);
            gradPThis = obj.sigma.P(bus).^(-2) * lossThis * g;
            obj.gradP = obj.gradP + gradPThis;
            HPThis = obj.sigma.P(bus).^(-2) * (g * g');
            obj.HP = obj.HP + HPThis;
        end
        
        function obj = buildHessianQ(obj , snap, bus, GBThetaP, GBThetaQ, Qest)
            % This method builds the Hessian from the measurement of Q
            
            theta_ij = obj.dataO.Va(bus, snap) - obj.dataO.Va(:, snap);
            g = sparse(obj.numGrad.Sum, 1);
            
            % G matrix
            H_G = zeros(obj.numBus, obj.numBus);
            H_G(bus, :) = obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* sin(theta_ij');
            h_G = obj.matToColDE(H_G);
            g(1:obj.numGrad.G) = h_G;
            
            % B matrix
            H_B = zeros(obj.numBus, obj.numBus);
            H_B(bus, :) = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap)' .* cos(theta_ij');
            H_B(bus, :) = H_B(bus, :) + obj.dataO.Vm(bus, snap)^2; % the equivilance of diagonal elements
            h_B = obj.matToColDE(H_B);
            g(obj.numGrad.G+1:obj.numGrad.G+obj.numGrad.B) = h_B;
            
            % Vm
            % the first order term of other Vm
            H_Vm = zeros(obj.numBus, obj.numSnap);
            h_Vm = obj.dataO.Vm(bus, snap) * GBThetaQ(:, bus);
            % the second order term of Vm(bus)
            h_Vm(bus) = 2*obj.dataO.Vm(bus, snap) * GBThetaQ(bus, bus);
            % the first order term of Vm(bus)
            fOrderVm = obj.dataO.Vm(:, snap) .* GBThetaQ(:, bus);
            fOrderVm(bus) = 0;
            h_Vm(bus) = h_Vm(bus) + sum(fOrderVm);
            H_Vm(:, snap) = h_Vm;
            % remove the source bus whose magnitude is not the state variable
            H_Vm(1, :) = []; 
            h_VmLarge = reshape(H_Vm', [], 1);
            g(obj.numGrad.G+obj.numGrad.B+1:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = h_VmLarge;
            
            % Va
            H_Va = zeros(obj.numBus, obj.numSnap);
            h_Va = - obj.dataO.Vm(bus, snap) * obj.dataO.Vm(:, snap) .* GBThetaP(:, bus);
            h_Va(bus) = - obj.dataO.Vm(bus, snap)^2 * obj.dataO.G(bus, bus) ...
                        + obj.data.P_noised(bus, snap);
%             h_Va(bus) = h_Va(bus)+sum(GBThetaP(bus, :) * obj.dataO.Vm(:, snap) * obj.dataO.Vm(bus, snap));
            H_Va(:, snap) = h_Va;
            % remove the source bus whose magnitude is not the state variable
            H_Va(1, :) = []; 
            h_VaLarge = reshape(H_Va', [], 1);
            g(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+1:end) = h_VaLarge;
            
            % build HQ, GradientQ and lossQ
            lossThis = (Qest(bus) - obj.data.Q_noised(bus, snap));
            obj.loss.Q = obj.loss.Q + lossThis^2 * obj.sigma.Q(bus).^(-2);
            gradQThis = obj.sigma.Q(bus).^(-2) * lossThis * g;
            obj.gradQ = obj.gradQ + gradQThis;
            HQThis = obj.sigma.Q(bus).^(-2) * (g * g');
            obj.HQ = obj.HQ + HQThis;
        end
        
        function obj = buildHessianVm(obj, snap, bus)
            % This method builds the Hessian from the measurement of Vm
            g = sparse(obj.numGrad.Sum, 1);
            H_Vm = sparse(obj.numBus, obj.numSnap);
            H_Vm(bus, snap) = 1;
            % remove the source bus whose magnitude is not the state variable
            H_Vm(1, :) = []; 
            h_VmLarge = reshape(H_Vm', [], 1);
            g(obj.numGrad.G+obj.numGrad.B+1:obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm) = h_VmLarge;
            
            % build GradientVm and lossVm
            lossThis = (obj.dataO.Vm(bus, snap) - obj.data.Vm_noised(bus, snap));
            obj.loss.Vm = obj.loss.Vm + lossThis^2 * obj.sigma.Vm(bus).^(-2);
            gradVmThis = obj.sigma.Vm(bus).^(-2) * lossThis * g;
            obj.gradVm = obj.gradVm + gradVmThis;
            HVmThis = obj.sigma.Vm(bus).^(-2) * (g * g');
            obj.HVm = obj.HVm + HVmThis;
        end
        
        function obj = buildHessianVa(obj, snap, bus)
            % This method builds the Hessian from the measurement of Va
            g = sparse(obj.numGrad.Sum, 1);
            H_Va = sparse(obj.numBus, obj.numSnap);
            H_Va(bus, snap) = 1;
            % remove the source bus whose angle is not the state variable
            H_Va(1, :) = []; 
            h_VaLarge = reshape(H_Va', [], 1);
            g(obj.numGrad.G+obj.numGrad.B+obj.numGrad.Vm+1:end) = h_VaLarge;
            
            % build HVa, GradientVa and lossVa
            lossThis = (obj.dataO.Va(bus, snap) - obj.data.Va_noised(bus, snap));
            obj.loss.Va = obj.loss.Va + lossThis^2 * obj.sigma.Va(bus).^(-2);
            gradVaThis = obj.sigma.Va(bus).^(-2) * lossThis * g;
            obj.gradVa = obj.gradVa + gradVaThis;
            HVaThis = obj.sigma.Va(bus).^(-2) * (g * g');
            obj.HVa = obj.HVa + HVaThis;
        end
        
        function obj = evalErr(obj)
            % This function calculate the error of the evaluated values
            
            % error of topology
            obj.dataO.topo = obj.dataO.G ~= 0;
            topoTrue = obj.data.G ~= 0;
            topoDelta = obj.dataO.topo - topoTrue;
            numMiss = sum(sum(topoDelta == -1));
            numRedund = sum(sum(topoDelta == 1));
            obj.err.topoMiss = numMiss / obj.numBranch;
            obj.err.topoRedund = numRedund / obj.numBranch;
            
            % error of G and B
            topoBranch = triu(topoTrue, 1);
            obj.err.G = abs(obj.data.G - obj.dataO.G);
            obj.err.g = obj.err.G(topoBranch);
            obj.err.B = abs(obj.data.B - obj.dataO.B);
            obj.err.b = obj.err.B(topoBranch);
            
            % real value of G and B
            obj.err.gEval = obj.dataO.G(topoBranch);
            obj.err.gReal = obj.data.G(topoBranch);
            obj.err.bEval = obj.dataO.B(topoBranch);
            obj.err.bReal = obj.data.B(topoBranch);
            
            % error of Vm and Va
            obj.err.Vm = mean(abs(obj.data.Vm(2:end, :) - obj.dataO.Vm(2:end, :)), 2);
            obj.err.Va = mean(abs(obj.data.Va(2:end, :) - obj.dataO.Va(2:end, :)), 2);
        end
        
        function obj = identifyMCMCEIV(obj)
            % This method uses the Markov Chain Monte Carlo to sample the
            % distribution of the parameters and the topologies. We use the
            % error-in-variables(EIV) assumption.
            % We may have some errors regarding to the usage of reshape Vm
            % and Va
            
            % Build the measurement function.
            % Currently, we assume we know all the P, Q, Vm, Va
            % measurements. We have to modify it later.
            data.Pn = obj.data.P_noised;
            data.Qn = obj.data.Q_noised;
            data.Vmn = obj.data.Vm_noised;
            data.Van = obj.data.Va_noised;
            data.num = obj.numFIM;
            data.isMeasure = obj.isMeasure;
            data.sigma = obj.sigma;
            
            % build the parameters
            G = obj.matOfCol(obj.dataE.G);
            B = obj.matOfCol(obj.dataE.B);
            Vm = reshape(obj.data.Vm_noised(2:end,:)', [], 1); % we assume the value of the source bus is already known
            Va = reshape(obj.data.Va_noised(2:end,:)', [], 1);
            par = [G' B' Vm' Va'];
            assert (length(par) == obj.numFIM.Sum) % the number of total parameters
            
            % we also build the ground truth value of the parameters
            Gtr = obj.matOfCol(obj.data.G);
            Btr = obj.matOfCol(obj.data.B);
            Vmtr = reshape(obj.data.Vm(2:end,:), [], 1);
            Vatr = reshape(obj.data.Va(2:end,:), [], 1);
            obj.truePar = [Gtr' Btr' Vmtr' Vatr'];
            
            % build the params in the format of mcmc
            params = cell(1, data.num.Sum);
            for i = 1:data.num.G
                params{i} = ...
                    {sprintf('G_{%d}',i), G(i), -Inf, Inf, obj.boundA.total(i)};
            end
            for i = 1:data.num.B
                params{i+data.num.G} = ...
                    {sprintf('B_{%d}',i), B(i), -Inf, Inf, obj.boundA.total(i+data.num.G)};
            end
            for i = 1:data.num.Vm
                params{i+data.num.G+data.num.B} =...
                    {sprintf('Vm_{%d}',i), Vm(i), Vm(i)*0.99, Vm(i)*1.01, obj.boundA.total(i+data.num.G+data.num.B)};
            end
            for i = 1:data.num.Va
                params{i+data.num.G+data.num.B+data.num.Vm} =...
                    {sprintf('Vm_{%d}',i), Va(i), Va(i)-abs(Va(i))*0.01, Va(i)+abs(Va(i))*0.01, obj.boundA.total(i+data.num.G+data.num.B+data.num.Vm)};
            end
            
            % build the model
            model.ssfun = @sumOfSquaresEIV;
            % build the sigma2 (the sum of squares error of the measurements)
            sigma2P = obj.sigma.P(obj.isMeasure.P).^2';
            sigma2Q = obj.sigma.Q(obj.isMeasure.Q).^2';
            sigma2Vm = obj.sigma.Vm(obj.isMeasure.Vm).^2';
            sigma2Va = obj.sigma.Va(obj.isMeasure.Va).^2';
            model.sigma2 = [sigma2P sigma2Q sigma2Vm sigma2Va] * obj.numSnap.^2 *1000;
            model.S20 = model.sigma2;
            model.N = obj.numSnap;
            
            % build the options
            options.nsimu = 500000;
            options.qcov = obj.boundA.cov;
            numGB = obj.numFIM.G+obj.numFIM.B;
            options.qcov(1:numGB,1:numGB) = options.qcov(1:numGB,1:numGB) * 1;
%             options.updatesigma = 1;

            % run the mcmc simulation
            [res,chain,s2chain] = mcmcrun(model,data,params,options);
            
            % run the mcmc simulation and update the cov matrix iteratively
            options.nsimu = 2000;
            numIter = 10;
            Gs = cell(1, numIter);
            Bs = cell(1, numIter);
            chains = [];
            errorInit = sum(sumOfSquaresEIV(par, data) ./ model.sigma2);
            errorTrue = sum(sumOfSquaresEIV(obj.truePar, data) ./ model.sigma2);
            errorEval = sum(sumOfSquaresEIV(res.theta', data) ./ model.sigma2);
            for i = 1:10
                [res,chain,~] = mcmcrun(model,data,params,options);
                errorEval = sum(sumOfSquaresEIV(res.theta', data) ./ model.sigma2)
                Gs{i} = res.theta(1:data.num.G);
                Bs{i} = res.theta(1+data.num.G:data.num.G+data.num.B);
                chains = [chains;chain];
                % rebuild the FIM matrix and the cov matrix
                obj.dataE.G = obj.colToMat(Gs{i}, obj.numBus);
                obj.dataE.B = obj.colToMat(Bs{i}, obj.numBus);
                obj = approximateFIM(obj);
                obj = calABound(obj);
                options.qcov = obj.boundA.cov;
                numGB = obj.numFIM.G+obj.numFIM.B;
                options.qcov(1:numGB,1:numGB) = options.qcov(1:numGB,1:numGB)*100;
            end
            errorInit = sum(sumOfSquaresEIV(par, data) ./ model.sigma2);
            errorTrue = sum(sumOfSquaresEIV(obj.truePar, data) ./ model.sigma2);
            errorEval = sum(sumOfSquaresEIV(res.theta', data) ./ model.sigma2);
        end
        
        function obj = identifyMCMCEIO(obj)
            % This method uses the Markov Chain Monte Carlo to sample the
            % distribution of the parameters and the topologies. We use the
            % error-in-outputs(EIV) assumption.
            % Build the measurement function.
            
            % Currently, we assume we know all the P, Q, Vm, Va
            % measurements. We have to modify it later.
            data.Pn = obj.data.P_noised;
            data.Qn = obj.data.Q_noised;
            data.Vmn = obj.data.Vm_noised;
            data.Van = obj.data.Va_noised;
            data.num = obj.numFIM;
            data.isMeasure = obj.isMeasure;
            data.sigma = obj.sigma;
            
            % build the parameters
%             G = obj.matOfCol(obj.dataE.G);
%             B = obj.matOfCol(obj.dataE.B);
            G = obj.matOfCol(obj.data.G);
            B = obj.matOfCol(obj.data.B);
            par = [G' B'];
            
            % we also build the ground truth value of the parameters
            Gtr = obj.matOfCol(obj.data.G);
            Btr = obj.matOfCol(obj.data.B);
            obj.truePar = [Gtr' Btr'];
            
            % build the params in the format of mcmc
            params = cell(1, data.num.G+data.num.B);
            for i = 1:data.num.G
                params{i} = ...
                    {sprintf('G_{%d}',i), G(i), -Inf, Inf, obj.boundA.total(i)};
            end
            for i = 1:data.num.B
                params{i+data.num.G} = ...
                    {sprintf('B_{%d}',i), B(i), -Inf, Inf, obj.boundA.total(i+data.num.G)};
            end
            
            % build the model
            model.ssfun = @sumOfSquaresEIO;
            % build the sigma2 (the sum of squares error of the measurements)
            % we use the summation of G and B matrices to approximate the
            % first order of measurement noises
%             sumG = diag(obj.dataE.G);
%             sumB = diag(obj.dataE.B);
            sumG = diag(obj.data.G);
            sumB = diag(obj.data.B);
            sigma2P = sumG(obj.isMeasure.P).^2';
            sigma2Q = sumB(obj.isMeasure.Q).^2';
            model.sigma2 = [sigma2P sigma2Q] / 10000000;
            model.S20 = model.sigma2;
            model.N = obj.numSnap;
            
            % build the options
            options.nsimu = 50000;
            numGB = obj.numFIM.G+obj.numFIM.B;
            options.qcov = obj.boundA.cov(1:numGB, 1:numGB);
            
            % run the mcmc
            [res,chain,s2chain] = mcmcrun(model,data,params,options);
            errorInit = sum(sumOfSquaresEIO(par, data) ./ model.sigma2);
            errorTrue = sum(sumOfSquaresEIO(obj.truePar, data) ./ model.sigma2);
            errorEval = sum(sumOfSquaresEIO(res.theta', data) ./ model.sigma2);
        end
    end
    
    methods (Static)
        function B = tls(xdata,ydata)
            % This method con
            SUM = sum(xdata,1);
            zero = find(SUM==0);
            xdata(:,zero)=[];

%             m       = length(ydata);       %number of x,y data pairs
            X       = xdata;
            Y       = ydata;
            n       = size(X,2);          % n is the width of X (X is m by n)
            Z       = [X Y];              % Z is X augmented with Y.
            [~, ~, V] = svd(Z,0);         % find the SVD of Z.
            VXY     = V(1:n,1+n:end);     % Take the block of V consisting of the first n rows and the n+1 to last column
            VYY     = V(1+n:end,1+n:end); % Take the bottom-right block of V.
            B       = -VXY/VYY;

            for i = zero
                B = [B(1:i-1); 0; B(i:end)];
            end
        end
        
        function h = matOfCol(H)
            % This method get the half triangle of a matrix
            H_up = tril(H, 1)';
            n = size(H, 1);
            N = (n + 1) * n / 2;
            h = zeros(N, 1);
            pt = 1;
            for i = 1:n
                h(pt:pt+n-i) = H_up(i, i:end);
                pt = pt+n-i+1;
            end
        end
        
        function h = matOfColDE(H)
            % This method get the half triangle of a matrix The name DE
            % denotes diagonal exclude, which means we consider the
            % diagonal elements as the negative summation of the rest elements.
%             H_up = tril(H, 1)';
            n = size(H, 1);
            N = (n - 1) * n / 2;
            h = zeros(N, 1);
            pt = 1;
            for i = 1:n
                h(pt:pt+n-i-1) = H(i, i+1:end);
                pt = pt+n-i;
            end
        end
        
        function TopoNext = disconnection(TopoDelta, TopoNext)
            % This method judge if the system is disconnected if the given
            % line is disconnected
            [rList, cList] = find(TopoDelta);
            num = length(rList);
            for i = 1:num
                if sum(TopoNext(rList(i),:))<3 || sum(TopoNext(:, cList(i)))<3
                    TopoNext(rList(i), cList(i)) = true;
                    fprintf("we should not disconnect line %d-%d",rList(i),cList(i));
                end
            end
        end
    end
end

