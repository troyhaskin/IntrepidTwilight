function jfnk = JFNK(config)
    
    %   Default parameters
    jfnk = IntrepidTwilight.TenaciousReduction.Solver();
    jfnk = jfnk.changeID(jfnk,'JFNK');
    
    %   Parameters
    jfnk.set('tolerance.residual'      ,  1.0E-6  )   ;
    jfnk.set('tolerance.stepSize'      ,  1.0E-6  )   ;
    jfnk.set('maximumIterations'       ,  100     )   ;
    jfnk.set('epsilon'                 ,  1.0E-7  )   ;
    jfnk.set('gmres.iteration.restarts',     1    )   ;
    jfnk.set('gmres.iteration.maximum' ,    -1    )   ;
    jfnk.set('gmres.tolerance'         ,  1.0E-10 )   ;
    jfnk.set('gmres.nu'                ,    0.90  )   ;
    jfnk.set('newton.relax.over'       ,    1.1   )   ;


    %   Hook initializations
    jfnk.set('hook.presolve' , @(x) [] );
    jfnk.set('hook.postsolve', @(x) [] );
    jfnk.set('hook.prestep'  , @(x) [] );
    jfnk.set('hook.poststep' , @(x) [] );



    %   Overwrite defaults at construction
    if (nargin >= 1)
        jfnk.set(config);
    end


    %   Dependencies and Binder
    jfnk.set('dependencies',{'residual','preconditioner'});
    residual       = []                         ;
    preconditioner = []                         ;
    jfnk.bind      = @(varargin) bind(varargin) ;
    %
    function [] = bind(objects)
        for k = 1:length(objects)
            bind_(objects{k});
        end
    end
    function [] = bind_(object)
        if isstruct(object) && isfield(object,'type')
            switch(object.type)
                case('residual')
                    residual = object;
                case('preconditioner')
                    preconditioner = object;
            end
        end
    end


    %   Extract parameters from store
    jfnk.prepare  = @(varargin) prepare(varargin{:});
    params        = struct()     ;
    isNotPrepared = true;
    function [] = prepare(varargin)
        if isNotPrepared
            
            %   Preparation cascade
            residual.prepare(varargin{:});
            preconditioner.prepare();
            
            %   Pull parameters
            params = jfnk.get();
            
            isNotPrepared = false;

        end
    end
    
    
    
    
    
    %   Public methods
    jfnk.solve = @(x) solve(x);
    
    
    
    %   Private variable declarations for GMRES
    Z     = 0   ;   % Update's basis vectors
    H     = 0   ;   % Householder vectors for projections
    R     = 0   ;   % Upper-triangular matrix for least squares problem
    Zeros = 0   ;   % Persistent Zero matrix
    alpha = 0   ;   % Vector of projected residuals
    
    
    % ================================================================= %
    %                               Allocater                           %
    % ================================================================= %
    arraysAreNotAllocated = true();
    function [] = allocateWorkArrays(x)
        
        %   Determine row count
        nRows = numel(x);
        
        %   Determine column count
        if (params.gmres.iteration.maximum == -1)
            nCols                          = nRows;
            params.gmres.iteration.maximum = nCols;
        else
            nCols = params.gmres.iteration.maximum;
        end
        
        %   Allocate
        Z(nRows,nCols)   = 0        ;
        H(nRows,nCols)   = 0        ;
        R(nRows,nCols)   = 0        ;
        Zeros(nRows-1,1) = 0        ;
        alpha            = [0;Zeros];
        
        %   Flip the switch
        arraysAreNotAllocated = false();
    end
    
    
    
    
    % ================================================================= %
    %                    Fully-Coupled Solver                           %
    % ================================================================= %
    function [xNL,stats,postSolveFlag] = solve(xNL)
        
        %   Allocate arrays if not done already
        if arraysAreNotAllocated
            allocateWorkArrays(xNL);
        end


        %   Hook
        preSolveFlag = params.hook.presolve(xNL);


        %   Allocate stats struct
        stats.iterations                       = 0;
        stats.norm(params.maximumIterations,1) = 0;


        %   Initialize  residual
        xNL           = residual.guard.value(xNL)   ;
        rNL           = residual.value(xNL)         ;
        rNLnorm       = norm(rNL,2)                 ;
        stats.norm(1) = rNLnorm                     ;


        %   Initialize preconditionar
        preconditioner.initialize(xNL);


        %   Check initial residual and preSolveFlag:
        %       This is a tad inefficient since the residual and preconditioner
        %       calls may occur when an 'exit' has been called for, but the
        %       likelihood of a preSolve calling for a full fallback is 
        %       considered small and not worth a refactor.
        normNotDone  = rNLnorm > params.tolerance.residual              ;
        stepNotDone  = true()                                           ;
        notConverged = normNotDone && stepNotDone                       ;
        belowIterMax = true()                                           ;
        flaggedExit  = strcmpi('exit',preSolveFlag)                     ;
        notDone      = notConverged && belowIterMax && not(flaggedExit) ;


        %   Iterate
        while notDone

            %   Hook
            preFlag = params.hook.prestep(xNL);
            if strcmpi('exit',preFlag)
                flaggedExit = true();
                break;
            end


            %   Evaluate initial residual
            rNL     = residual.value(xNL)   ;
            rNLnorm = norm(rNL,2)           ;


            %   Take a step
            [xNL,rNLnorm,~] = nonlinearStep(xNL,rNL,rNLnorm);


            % Hook
            postFlag = params.hook.poststep(xNL);
            if strcmpi('exit',postFlag)
                flaggedExit = true();
                break;
            end


            %   Update to new state
            stats.iterations             = stats.iterations + 1 ;
            stats.norm(stats.iterations) = rNLnorm              ;
            preconditioner.update(xNL)                          ;


            %   Iteration convergence stuff
            normNotDone  =     rNLnorm      >= params.tolerance.residual            ;
%             stepNotDone  =      dxNorm      >= params.tolerance.stepSize* norm(xNL) ;
            belowIterMax = stats.iterations <= params.maximumIterations             ;
            notConverged = normNotDone && stepNotDone                               ;


            %   Continue the iteration
            flaggedNotDone = any(strcmpi('notDone',{preFlag,postFlag}))     ;
            notDone        = belowIterMax && notConverged || flaggedNotDone ;

        end
        
        % Hook
        postSolveFlag = params.hook.postsolve(xNL);
        
        
        %   Contract vector to the number of actuall iterations
        stats.norm      = stats.norm(1:max([stats.iterations,1]))   ;
        stats.converged = not(notConverged)                         ;
        
        
        %   Give a reason why the function has returned control to the caller
        if not(flaggedExit)
            if not(normNotDone)
                stats.returnStatus = 'NormConverged';
            elseif not(stepNotDone)
                stats.returnStatus = 'TooSmallStepNorm';
            elseif not(belowIterMax)
                stats.returnStatus = 'IterationMaximumReached';
            end
        else
            stats.returnStatus = 'HookExitRequest';
        end


    end





    % ================================================================= %
    %                         Non-Linear Step                           %
    % ================================================================= %
    function [xNL,rNLnorm,dxNorm] = nonlinearStep(xNLm1,rNLm1,rNLnorm)
        
        %   Advance in a descent direction
        [xNL,~,rNLnorm,dxNorm] = quasiNewtonUpdate(xNLm1,rNLm1,rNLnorm);
        
        
%         %   Extrapolate solution
%         dxExtrap    = rNL .* (xNL - xNLm1)./(rNL - rNLm1 + eps(rNLm1));
%         xExtrap     = xNL - dxExtrap            ;
%         rExtrap     = residual.value(xExtrap)   ;
%         rExtrapNorm = norm(rExtrap,2)           ;
%         if rExtrapNorm < 0.9*rNLnorm
%             xNL     = xExtrap       ;
%             rNLnorm = rExtrapNorm   ;
%         end
        
    end





    % ================================================================= %
    %                         Quasi-Newton Update                       %
    % ================================================================= %
    function [xNew,rNew,rNewNorm,dxNorm] = quasiNewtonUpdate(xOld,rOld,rOldNorm)
        
        % Solve linear system to within linearTolerance
        dx = GMRES(xOld,rOld,rOldNorm);

        %   Allow adjustment of the step size through user-defined function
        dx       = residual.guard.step(xOld,dx) ;
        rNew     = residual.value(xOld - dx)    ;
        rNewNorm = norm(rNew,2)                 ;
        
         if (rNewNorm > rOldNorm)
            [dx,rNewNorm] = inexactLineSearch(xOld,dx,rOldNorm,rNewNorm);
        end
        
        % Calculate relaxed x value
        xNew   = xOld - dx      ;
        dxNorm = norm(dx,Inf)   ;
        
    end





    % ================================================================= %
    %                            GMRES (Outer)                          %
    % ================================================================= %
    %   Outer "Restart" Iterations
    function dx = GMRES(xk,rk,rkNorm)
        dx = 0;
        for k = 1:params.gmres.iteration.restarts
            xk             = xk + dx                ;
            [dx,rk,rkNorm] = GMRESInner(xk,rk,rkNorm);
            
            if rkNorm <= params.gmres.tolerance
                break;
            end
        end
    end


    % ================================================================= %
    %                            GMRES (Inner)                          %
    % ================================================================= %
    function [dx,rk,rkNorm] = GMRESInner(xk,rk0,rk0Norm)
        
        %   Create shortcuts for closure variables
        nu              = params.gmres.nu       ;
        linearTolerance = params.gmres.tolerance;
        epsilon         = params.epsilon        ;
        n               = numel(xk)             ;
        
        
        %   First basis vector for update
        Z(:,1) = rk0 / rk0Norm ;
        
        % First Step (k = 1)
        % Compute J*z1 and store in R
        w      = preconditioner.apply(Z(:,1));
        R(:,1) = (residual.value(xk + epsilon*w) - rk0) / epsilon   ;
        
        % Compute Householder vector to bring R(:,1) into upper triangular form
        e      = [1 ; Zeros(1:n-1)]                 ;
        h      = R(:,1)                             ;
        h      = -Signum(h(1)) * norm(h,2) * e - h  ;
        H(:,1) = h / norm(h,2)                      ;
        
        % Apply projection to R to bring it into upper triangular form
        R(:,1) = R(:,1) - 2 * H(:,1) * (H(:,1)'*R(:,1));
        
        % Get the first column of the unitary matrix
        q = e - 2 * H(:,1) * (H(:,1)'*e);
        e = e(1:n-1);
        
        % Residual update
        alpha(1) = q'*rk0           ;
        rk       = rk0 - alpha(1)*q ;
        
        % Assign residual norms to determine which basis to use
        rkm1Norm = rk0Norm      ;
        rkNorm   = norm(rk,2)   ;
        
        
        for k = 2:params.gmres.iteration.maximum
            
            % Choose the next basis vector
            if rkNorm <= nu*rkm1Norm
                Z(:,k) = rk/rkNorm  ;   %   GCR (RB-SGMRES) basis
            else
                Z(:,k) = q          ;   %   Simpler GMRES basis
            end
            
            % Compute and store A*zk in R
            w      = preconditioner.apply(Z(:,k))                       ;
            R(:,k) = (residual.value(xk + epsilon*w) - rk0) / epsilon   ;
            
            % Apply all previous projections to new the column
            for m = 1:k-1
                R(:,k) = R(:,k) - H(:,m)*(2*H(:,m)'*R(:,k));
            end

            
            % Get the next Householder vector
            h        = R(k:n,k)                     ;
            h        = -Signum(h(1))*norm(h,2)*e - h;
            h        = h ./ norm(h,2)               ;
            H(k:n,k) = h                            ;

            
            %   Apply new projection to R to bring it into upper triangular form;
            for m = 1:k
                R(:,m) = R(:,m) - 2 * H(:,k) * (H(:,k)'*R(:,m));
            end

            
            % Get the k-th column of the current unitary matrix
            q = [Zeros(1:k-1) ; e - 2*h*(h'*e)];
            for m = k-1:-1:1
                q = q - 2*H(:,m)*(H(:,m)'*q);
            end
            e = e(1:end-1);
            
            % Update residual
            alpha(k) = q'*rk            ;
            rk       = rk - alpha(k)*q  ;
            
            % Update residual norms
            rkm1Norm = rkNorm;
            rkNorm   = norm(rk,2);
            
            % Solve least-squares problem
            if rkNorm < linearTolerance
                break;
            end
            
        end
        
        % Update to x
        Rtilde = triu(R(1:k,1:k));
        
        if rcond(Rtilde) > 100*eps()
            yk = Rtilde \ alpha(1:k);   % Solve the least-squares problem
        else
            %   Attempt to re-scale
            S  = diag(1./diag(Rtilde))  ;
            yk = (Rtilde*S) \ alpha(1:k);
            yk = S*yk                   ;
        end
        
        dx = Z(:,1:k) * yk              ; % Calculate full Newton update
        dx = preconditioner.apply(dx)   ;
        
    end





    % ================================================================= %
    %                       Inexact Line Search                         %
    % ================================================================= %
    function [dx,ralpha] = inexactLineSearch(x0,dx,r0,rbeta)
        
%         %   
%         while (rbeta > 1E2)
%             dx = 0.5 * dx;
%             rbeta = norm(residual.value(x0 - dx));
%         end


        %   Quadratic optimum
        sbeta  = 1                                          ;
        salpha = (sbeta^2*r0)/(2*(sbeta * r0 + rbeta - r0)) ;
        ralpha = norm(residual.value(x0 - salpha*dx))       ;


%         %   Guard against extremely small quadratic optimums
%         if (salpha < 1E-3)
%             salpha = sbeta/2                                ;
%             ralpha = norm(residual.value(x0 - salpha*dx))   ;
%         end


        %   Cubic optimum
        iter = 0;
        while (ralpha > r0) && (abs(sbeta-salpha)>100*eps())

            % Reassign for recursion
            rgamma = rbeta  ;
            sgamma = sbeta  ;
            rbeta  = ralpha ;
            sbeta  = salpha ;
            
            %   Cubic coefficients
            detA = sbeta^2  * sgamma^2 * (sbeta-sgamma)     ;
            b1   = sbeta^2  * ( rgamma + r0*(sgamma - 1) )  ;
            b2   = sgamma^2 * ( rbeta  + r0*(sbeta  - 1) )  ;
            c    = -r0                                      ;
            b    =  2 * ( sbeta*b1 - sgamma*b2 )/detA       ;
            a    = -3 * (       b1 -        b2 )/detA       ;

            
            %   Cubic optimums
            opt    = (-b-sign(b)*sqrt(b^2-4*a*c))/(2*a)     ;
            opts   = [opt,c/(a*opt)]                        ;
            salpha = min(opts(opts<1 & opts>0))             ;
            ralpha = norm(residual.value(x0 - salpha*dx))   ;
            
            iter = iter + 1;

        end
        
        dx = salpha*dx;

    end

end

function s = Signum(s)
    if (s ~= 0)
        s = sign(s);
    else
        s = 1;
    end
end
