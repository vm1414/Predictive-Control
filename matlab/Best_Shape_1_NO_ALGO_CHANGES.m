%% Modify the following function for your setup function
% IDEA: take c in pieces and work on optimising a route piece by piece.
% Then, for all but the last set of constraints, apply a weak penalty on 
% the final position. This way, the controller will not spend too long
% trying to perfectly fit intermediary positions before moving on.

function [ param ] = mySetup(c, startingPoint, targetPoint, eps_r, eps_t)
    tol = 0;
    angleConstraint = 2*pi/180; % in radians
    inputAttenuation = 0.78; % best=0.78
    ul=inputAttenuation*[-1; -1];
    uh=inputAttenuation*[1; 1];
    Tf=2*inputAttenuation; % duration of prediction horizon in seconds
    % This is a sample way to send reference points
    param.xTar = targetPoint(1);
    param.yTar = targetPoint(2);
    
    param.rTol = eps_r;
    param.tTol = eps_t;
    
    param.start = startingPoint;
    
    load CraneParameters;
    Ts=1/20;    
    N=ceil(Tf/Ts);
    [A,B,C,~] = genCraneODE(m,M,MR,r,g,Tx,Ty,Vm,Ts);    
    %% Declare penalty matrices and tune them here:
    Q=zeros(8);
%     Q(1,1)=10; % weight on X
%     Q(3,3)=10; % weight on Y
    Q = diag([10,0,10,0,50,0,50,0]);
    R=eye(2)*0.01; % very small penalty on input to demonstrate hard constraints
    P=Q; % terminal weight

    %% Declare contraints
    % Constrain only states (X,Y,theta,psi)
    % Constrained vector is Dx, hence
    %% Construct constraint matrix D
    % General form
    D = zeros(size(c,1) + 2, 8);
    ch = zeros(size(c,1) + 2, 1);       
    
    for i = 1:size(c,1)
        i2 = mod(i+1,size(c,1));
        if i2 == 0
            i2 = size(c,1);
        end        
        if c(i,1) > c(i2,1)
            modifier = -1;
            c1y = c(i,2) + tol;
            c2y = c(i2,2) + tol;
        else
            modifier = 1;
            c1y = c(i,2) - tol;
            c2y = c(i2,2) - tol;            
        end
%         coeff = polyfit([c(i,1), c(i2,1)], [c(i,2), c(i2,2)], 1);
        coeff = polyfit([c(i,1), c(i2,1)], [c1y, c2y], 1);
        D(i,1) = coeff(1) * modifier*(-1);
        D(i,3) = modifier;     
        ch(i) = modifier * coeff(2);
    end    
    D(end-1,5) = 1;      ch(end-1) = angleConstraint;
    D(end,7) = 1;        ch(end) = angleConstraint;  

    %% End of construction        
    

    %% Compute stage constraint matrices and vector
%     [Dt,Et,bt]=genStageConstraints(A,B,D,[],constraints,ul,uh);
    DA = D*A;
    DB = D*B;
    I = eye(size(B,2));
    O = zeros(size(B,2),size(A,2));
    Dt = [DA; O; O];
    Et = [DB; I; -I];
    bt = [ch; uh; -ul];    
    %% Compute trajectory constraints matrices and vector
    [DD,EE,bb]=genTrajectoryConstraints(Dt,Et,bt,N);

    %% Compute QP constraint matrices
    [Gamma,Phi] = genPrediction(A,B,N); % get prediction matrices:
    [F,J,L]=genConstraintMatrices(DD,EE,Gamma,Phi,N);

    %% Compute QP cost matrices
    [H,G]=genCostMatrices(Gamma,Phi,Q,R,P,N);

%     %% Compute matrices and vectors for soft constraints
%     % Define weights for constraint violations
%     rho = 1e3; % weight for exact penalty term
%     S = 1e-3*eye(size(D,1)); % small positive definite quadratic cost to ensure uniqueness
%     [Hs,gs,Fs,bs,Js,Ls] = genSoftPadding(H,F,bb,J,L,S,rho,size(B,2));
% 
%     %% replace matrices and vectors to simplify code
%     H = Hs; F = Fs; bb = bs; J = Js; L = Ls;
%     param.gs = gs;
    %% Prepare cost and constraint matrices for mpcqpsolver
    H = chol(H,'lower');
    H=H\eye(size(H));    
    
    param.H = H;
    param.G = G;    
    param.F = F;
    param.J = J;
    param.L = L;
    param.bb = bb;
    
    param.A = A;
    param.C = C;
end % End of mySetup


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% Modify the following function for your target generation
function r = myTargetGenerator(x_hat, param)

    %% Do not delete this line
    % Create the output array of the appropriate size
    r = zeros(10,1);
    %%
    % Make the crane go to (xTar, yTar)
    r(1,1) = param.xTar;
    r(3,1) = param.yTar;
    condition = (abs(x_hat(1) - param.xTar) < param.tTol) &...
                (abs(x_hat(3) - param.yTar) < param.tTol) &...
                (abs(x_hat(2)) < param.rTol) &...
                (abs(x_hat(4)) < param.rTol)&...
                (abs(x_hat(6)) < param.rTol)&...
                (abs(x_hat(8)) < param.rTol);
    if condition
        r(1:8) = x_hat(1:8);
    end
end % End of myTargetGenerator


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% Modify the following function for your state estimator (if desired)
function x_hat = myStateEstimator(u, y, param)

    %% Do not delete this line
    % Create the output array of the appropriate size
    x_hat = zeros(16,1);
    %% Pendulum is assumed to be of length 0.47m
    x_hat(1:8) = param.C\y;
end % End of myStateEstimator


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% Modify the following function for your controller
function u = myMPController(r, x_hat, param)
    %% Do not delete this line
    % Create the output array of the appropriate size
    u = zeros(2,1);
    %% Check if crane is at target point
%     condition = (abs(x_hat(1) - param.xTar) < param.tTol) &...
%                 (abs(x_hat(3) - param.yTar) < param.tTol) &...
%                 (abs(x_hat(2)) < param.rTol) &...
%                 (abs(x_hat(4)) < param.rTol)&...
%                 (abs(x_hat(6)) < param.rTol)&...
%                 (abs(x_hat(8)) < param.rTol);
    condition = 0; % Leave the condition to be handled by target gen
    if ~condition    
        %% MPC Controller
        opt = mpcqpsolverOptions;
        opt.IntegrityChecks = false;%% for code generation
        opt.FeasibilityTol = 1e-3;
        opt.DataType = 'double';
        %% your code starts here
        % Cholksey and inverse already computed and stored in H
        w = x_hat(1:8) - r(1:8);
    %     f = [w'*param.G', param.gs']; % Soft
        f = w'*param.G'; % Hard

        b = -(param.bb + param.J*x_hat(1:8) + param.L*r(1:8));
        [v, ~, ~, ~] = mpcqpsolver(param.H, f', -param.F, b, [], zeros(0,1), false(size(param.bb)), opt);
        %% your remaining code here
        u = v(1:2);
    end
end % End of myMPController
