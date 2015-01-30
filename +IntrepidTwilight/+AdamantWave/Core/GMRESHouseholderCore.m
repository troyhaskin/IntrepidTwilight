function [x,Residuals] = GMRESHouseholderCore(A,b,x0,Nrestarts,Nmax,Tolerance,nu,...
        PreConditionerLeft,PreConditionerRight)
    
    % ================================================================================== %
    %                                GMRESHouseholderCore                                %
    % ================================================================================== %
    %{
        GMRESHouseholderCore is an implementation of Adaptive Simpler GMRES (ASGMRES)
        using Householder reflections for orthogonalization.  Standard GMRES relies on
        updating a Hessenberg matrix (the product of A and the update basis directions)
        and then solving a least-squares problem via the Hessenberg's QR factorization
        (with updates done via Givens rotations); Simpler GMRES starts with a slightly
        different basis vector such that only the QR factorization is needed.  Adaptive
        Simpler GMRES adds the weighting factor nu to iteratively change the choice of
        basis vector for the next Simpler GMRES iteration depending on the residual's
        behavior.  This adaptivity results in ASGMRES being more stable and well-
        conditioned for linear solves.


        Ref:    Rozložník Jiránek, Pavel, and Miroslav Rozložník. "Adaptive version of
                Simpler GMRES." Numerical Algorithms 53.1 (2010): 93-112.
    %}
    
    
    
    % ============================================================= %
    %                             Set-Up                            %
    % ============================================================= %
    
    % Length of columns and vectors
    N = length(b);
    
    % 
    Niterate = (Nrestarts <= Nmax)*Nrestarts + (Nrestarts > Nmax)*Nmax;
    
    % Matrix allocation
    Z = zeros(N,Niterate)  ;   % Update's basis vectors
    H = zeros(N,Niterate)  ;   % Householder vectors for projections
    Q = zeros(N,Niterate)  ;   % Unitary matrix columns of QR decomposition
    R = zeros(N,Niterate)  ;   % Upper-triangular matrix for least squares problem
    
    % Vector allocation
    e         = [1 ; zeros(N-1,1)]  ; % Unit vector used in creation of Householder vectors
    alpha     = b*0                 ; % Vector of projected residuals
    Residuals = zeros(Nmax,1)       ; % All residuals from ASGMRES
    
    % Initial residuals
    r0      = PreConditionerLeft(b - A*PreConditionerRight(x0));
    rk      = r0            ; % Iterate residual
    r0Norm  = norm(r0,2)	; % True initial residual
    rkNorm  = norm(r0,2)    ; % Iterated initial residual
    
    % Convergence iteration setup
    NotDone      = r0Norm > Tolerance   ;
    Tolerance    = r0Norm * Tolerance   ;
    Iterations   = 0                    ;
    Residuals(1) = r0Norm               ;
    n            = 2                    ;
    x            = x0                   ;
    
    
    % ================================================================================= %
    %                              Convergence Iterations                               %
    % ================================================================================= %
    
    while NotDone
        
        % ---------------------------------------------------- %
        %                    First Arnoldi Step                %
        % ---------------------------------------------------- %
        
        % First basis vector
        Z(:,1) = rk / rkNorm ;
        
        % Compute A*z1 and store in R
        w      = PreConditionerRight(Z(:,1))    ;
        R(:,1) = PreConditionerLeft (A*w)       ;
        
        % Compute Householder vector for R(:,1)
        h      = R(:,1);
        h      = -Signum(h(1)) * norm(h,2) * e(1:N) - h;
        H(:,1) = h / norm(h,2);
        
        % Bring R into upper triangular form via projection
        R(:,1) = R(:,1) - 2 * H(:,1) * (H(:,1)'*R(:,1));
        
        % Get the first column of the unitary matrix
        Q(:,1) = e - 2 * H(:,1) * (H(:,1)'*e);
        
        % Residual update
        alpha(1) = Q(:,1)'*rk           ; % Projected residual
        rk       = rk - alpha(1)*Q(:,1) ; % True b - A*(x+dx) residual
        
        % Starting and current residual norms used for choice of next basis vector
        rkm1Norm = rkNorm       ;
        rkNorm   = norm(rk,2)   ;
        
        % Store new residual
        Residuals(n) = rkNorm   ;
        n            = n + 1    ;
        
        
        % ---------------------------------------------------- %
        %                Requested Arnoldi Steps               %
        % ---------------------------------------------------- %
        for k = 2:Niterate
            
%             if rkNorm <= nu*rkm1Norm
                Z(:,k) = rk/rkNorm;
%             else
%                 Z(:,k) = Q(:,k-1);
%             end
            
            % Compute and store A*zk in R
            w      = PreConditionerRight(Z(:,k));
            R(:,k) = PreConditionerLeft (A*w)   ;
            
            % Apply all previous projections to new the column
            for m = 1:k-1
                R(m:N,k) = R(m:N,k) - 2*H(1:N-m+1,m)*(H(1:N-m+1,m)'*R(m:N,k));
            end
            
            % Get the next Householder vector
            h            = R(k:N,k)                                 ;
            h            = -Signum(h(1)) * norm(h,2) * e(1:N-k+1) - h ;
            h            = h / norm(h)                              ;
            H(1:N-k+1,k) = h                                        ;
            
            %   Apply projection to R to bring it into upper triangular form;
            %   The triu() call explicitly zeros all strictly lower triangular
            %   components to minimize FP error.
            R(k:N,1:k) = R(k:N,1:k) - 2 * h * (h'*R(k:N,1:k));
            
            % Get the k-th column of the current unitary matrix
            Q(:,k) = [zeros(k-1,1) ; e(1:N-k+1) - 2*h*(h'*e(1:N-k+1))];
            for m = k-1:-1:1
                Q(m:N,k) = Q(m:N,k) - 2*H(1:N-m+1,m)*(H(1:N-m+1,m)'*Q(m:N,k));
            end
            
            % Update residual
            alpha(k) = Q(:,k)'*rk               ;
            rk       = rk - alpha(k)*Q(:,k)     ;
            
            % Reassign previous residuals
            rkm1Norm = rkNorm;
            rkNorm   = norm(rk,2);
            
            % Store new residual
            Residuals(n) = rkNorm   ;
            n            = n + 1    ;
            
            % Solve least-squares problem
            if rkNorm < Tolerance
                break;
            end
            
        end
        
        % ---------------------------------------------------- %
        %                   Post-Arnoldi Steps                 %
        % ---------------------------------------------------- %
        
        % Update iteration count
        Iterations = Iterations + k;
        
        % while-loop condition update
        NotConverged = (rkNorm > Tolerance)         ;
        CanIterate   = (Iterations <  Nmax)         ;
        NotDone      = NotConverged && CanIterate   ;
        
        
        % Update iteration maximum 
        if NotDone && (Nmax < (Iterations + Niterate))
            Niterate = Nmax - Iterations;
        end
        
        
        % Update solution

        % Solve the least-squares problem
        omega = triu(R(1:k,1:k)) \ alpha(1:k);
    
        % Calculate actual shift of guess
        dx = Z(:,1:k)*omega;
        x  = x + dx;
        
        if (nargout > 1)
            Residuals = Residuals(1:n-1);
        end
        
    end
    
    % Apply right-preconditioner to transform back to A*x = b
    x = PreConditionerRight(x);

end

function s = Signum(s)
    if (s ~= 0)
        s = sign(s);
    else
        s = 1;
    end
end
