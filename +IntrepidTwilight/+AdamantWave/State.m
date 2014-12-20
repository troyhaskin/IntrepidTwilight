classdef State < handle

    properties
        Fluid

        % Thermodynamic properties
        Pressure
        Temperature
        InternalEnergy
        Density
        SpecificVolume
        Entropy
        Enthalpy

        % Transport properties
        ThermalConductivity
        DynamicViscosity


        
    end
    
    methods
        function S = State(n)
            if (nargin >= 1) && not(isempty(n))
                S(n) = State();
            end
        end
    end
    
end