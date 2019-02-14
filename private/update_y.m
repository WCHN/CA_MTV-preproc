function [Nii_y,ll1,ll2]= update_y(Nii_x,Nii_y,Nii_u,Nii_w,Nii_H,dat,tau,rho,lam,num_workers,p)
% Update Nii_y
%
%_______________________________________________________________________
%  Copyright (C) 2018 Wellcome Trust Centre for Neuroimaging

% Some parameters from options struct
modality      = p.Results.Modality;
method        = p.Results.Method;
nitgn         = p.Results.IterGaussNewtonImage; 
speak         = p.Results.Verbose; 
EstimateRigid = p.Results.EstimateRigid;

C  = numel(Nii_x);
vx = sqrt(sum(dat(1).mat(1:3,1:3).^2));
dm = dat(1).dm;

% Flag saying if we solve using projection matrices (A, At), or not
use_projmat = ~(strcmpi(method,'denoise') && ~EstimateRigid);

ll1 = zeros(1,C);
ll2 = 0;
% for c=1:C, fprintf('OBS! for c=1:C\n')
parfor (c=1:C,num_workers) % Loop over channels

    set_boundary_conditions;

    u = get_nii(Nii_u(c));   
    w = get_nii(Nii_w(c));   

    %------------------------------------------------------------------
    % Proximal operator for y        
    %------------------------------------------------------------------

    x = get_nii(Nii_x(c)); % Get observed image
    y = get_nii(Nii_y(c)); % Get solution

    if use_projmat
        % We use the projection matrices (A, At)
        
        for gnit=1:nitgn % Iterate Gauss-Newton

            % Gradient      
            rhs = w/rho - u; 
            rhs = lam(c)*imdiv(rhs,vx);
            Ayx = A(y,dat(c));
            for n=1:dat(c).N
                % Here we discard missing data, for MRI these are
                % assumed to be zeros and NaNs.
                mskn          = isfinite(x{n}) & x{n} ~= 0;
                Ayx{n}        = Ayx{n} - x{n};
                Ayx{n}(~mskn) = 0;
            end                  
            mskn = [];
            rhs  = rhs + At(Ayx,dat(c),tau{c})*(1/rho); 
            Ayx  = [];
            rhs  = rhs + spm_field('vel2mom',y,[vx 0 lam(c)^2 0]);

            % Hessian
            H   = get_nii(Nii_H(c));
            lhs = H*sum(tau{c})/rho;
            H   = [];

            % Compute GN step
            y   = y - spm_field(lhs,rhs,[vx 0 lam(c)^2 0 2 2]);
            lhs = [];
            rhs = [];
        end                                
    else
        % We do not use the projection matrices (A, At)
        
        % RHS
        rhs = u - w/rho; 
        rhs = lam(c)*imdiv(rhs,vx);
        rhs = rhs + x{1}*(tau{c}/rho);

        % LHS
        lhs = ones(dm,'single')*tau{c}/rho;

        % Compute new y
        y   = spm_field(lhs,rhs,[vx 0 lam(c)^2 0 2 2]);
        lhs = [];
        rhs = [];        
    end
    
    if strcmpi(modality,'MRI')
        % Ensure non-negativity (ad-hoc)
        y(y < 0) = 0;
    end 

    % Compute log of likelihood part    
    ll1(c) = get_ll1(use_projmat,y,x,tau{c},dat(c));
    x      = [];

    %------------------------------------------------------------------
    % Solve for w
    % Here we update the Lagrange variable
    %------------------------------------------------------------------

    G = lam(c)*imgrad(y,vx);

    Nii_y(c) = put_nii(Nii_y(c),y);
    y        = [];
    
    %------------------------------------------------------------------
    % Compute log of prior part (part 1)
    %------------------------------------------------------------------
    
    ll2 = ll2 + sum(sum(G.^2,4),5);
    G   = [];                

end % End loop over channels     

% Compute log of prior part (part 2)
ll2 = -sum(sum(sum(sqrt(double(ll2))))); 

if speak >= 2    
    show_model('solution',use_projmat,modality,Nii_x,Nii_y);    
    show_model('rgb',Nii_y);
end
%==========================================================================