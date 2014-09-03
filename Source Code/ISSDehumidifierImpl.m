classdef ISSDehumidifierImpl < handle
    %ISSDehumidifierImpl Summary of this class goes here
    %   By: Sydney Do (sydneydo@mit.edu)
    %   Date Created: 5/16/2014
    %   Last Updated: 5/16/2014
    
    
    %% Notes to convert to ISS CCAA
    % Peak power draw: 705W (BVAD Appendix A)
    % Average operational power draw: 469W (Corresponds to max fan (inlet
    % ORU) power consumption (REF: BVAD Appendix A)
    % From calculations of data given from pg 105 of Living Together in
    % Space:
    % Original quote:"For 12,716 L/min (430 cfm) airflow, the minimum by-pass flow is 850L/min (30 cfm) and the minimum HX flow is 1,444 L/min (51 cfm)."
    % Minimum flow through CCAA CHX is 1444L/min
    % Maximum flow through CCAA CHX is 12716-850 = 11866L/min
    
    % CCAA fan flow rate ranges from 8490L/min to 14150L/min
    
    % From pg 110 of Living Together in Space: "The humidity condensate
    % water is delivered to the wastewater bus at a rate up to 1.45 kg (3.2 lb) per hour at a pressure of up to 55 kPa (8 psig)."
    
    % Therefore, one operating point is:
    % Maximum capacity:
    % - Power draw: 705W
    % - Air flow through CHX (ie. dehumidifier): 11866L/min
    % - Water delivered = min(equivalent amount of water in air, 1.45kg/hr)
    
    % Minimum capacity:
    % - Power draw: 469W
    % - Air flow through CHX: 1444L/min (we assume that the fan flow is
    % fixed at 12716 L/min)
    % - Water delivered = min(equivalent amount of water in air, 1.45kg/hr)
    
    % As is the case with the actual ISS CCAA, we assume automatic control
    % to maintain a set temperature (in this case, to maintain the
    % optimal_moisture_concentration listed in the private properties
    % section)
    
    % The code thus determines what amount of water should be removed based
    % on atmospheric data, then determined the corresponding amount of air
    % needed and the power drawn.
    
    properties
        % Consumer/Producer Definitions
        Environment   % ResourceStore here is set to a SimEnvironment
        DirtyWaterOutput
        PowerSource     % Power to drive CCAA Inlet (Fan) ORU
        Error = 0
    end
    
    properties (Access = private)
%         optimal_moisture_concentration = 0.0218910; %in kPa assuming 101 kPa total pressure and air temperature of 23C and relative humidity of 80% - this can be made a function of temperature according to the temperature-humidity control box
        targetVaporPressure = 2.837*0.4  %kPa, Psat at 23C is 2.837 kPa (From Saturated Water Table - Table A-4 Cengal and Turner 2nd Ed.), targeting a relative humidity of 40%
        targetRelativeHumidity = 0.4;    % Fraction - from NASA HIDH Section 6.2.3.2
        idealGasConstant = 8.314;        % J/K/mol
        max_condensate_extracted = 1.45*1E3/(2*1.008+15.999)       % in moles per hour, converted from 1.45kg/hr
        max_power_draw = 705        % Watts
        min_power_draw = 469        % Watts         CCAA always runs to maintain intramodule ventilation
        max_airflow_in_L = 11866*60 % Liters/hour
        min_airflow_in_L = 1444*60  % Liters/hour
    end
    
    methods
        %% Constructor
        function obj = ISSDehumidifierImpl(environment,CondensateOutput,PowerSource)
            obj.Environment = environment;
            obj.DirtyWaterOutput = CondensateOutput;
            obj.PowerSource = PowerSource;
        end
        
        %% tick
        % this function followsthe DehumidifierImpl.dehumidifyEnvironment
        % method
        function vaporMolesRemoved = tick(obj)
            
            % Only run if there is no system error
            if obj.Error == 0
                               
                % Take vapor moles removed if current vapoer partial
                % pressure is greater than target vapor pressure
                VaporMolesNeededToRemove = ((obj.Environment.VaporPercentage*obj.Environment.totalMoles) > obj.targetVaporPressure)*...
                    (obj.Environment.VaporStore.currentLevel-obj.targetVaporPressure*obj.Environment.volume/(obj.idealGasConstant*(273.15+obj.Environment.temperature)));
                
                
                % Determine amount of air corresponding to
                % vaporMolesNeededToRemove
                if VaporMolesNeededToRemove >= obj.max_condensate_extracted
                    powerToConsume = obj.max_power_draw;
                else
                    % Linear scaling law between max and min power and
                    % condensate extraction (where minimum extraction is zero -
                    % which corresponds to TCCV door angle at 0 degrees and all
                    % flow being sent to bypass stream - ref Fig. 59 - Living
                    % Together in Space)
                    powerToConsume = (obj.max_power_draw-obj.min_power_draw)/obj.max_condensate_extracted*VaporMolesNeededToRemove+obj.min_power_draw;
                end
                
                currentPowerConsumed = obj.PowerSource.take(powerToConsume);     % Take power from power source
                
                if currentPowerConsumed < powerToConsume
                    % return power to power store
                    obj.PowerSource.add(currentPowerConsumed);
                    disp('CCAA shut down due to inadequate power input. There is currently know intramodule ventilation and cabin humidity control')
                    obj.Error = 1;
                    vaporMolesRemoved = 0;  % nothing produced by CHX
                    return
                end
                
                vaporMolesToTake = max([obj.max_condensate_extracted/(obj.max_power_draw-obj.min_power_draw)*(currentPowerConsumed-obj.min_power_draw),0]);     % Max command just in case power available is less than minimum power draw
                vaporMolesRemoved = obj.Environment.VaporStore.take(vaporMolesToTake); % Actually vapor moles removed
                
                % Push humidity condensate to dirty water store (note that we
                % convert from water moles to water liters here)
                obj.DirtyWaterOutput.add(vaporMolesRemoved*18.01524/1000);
                
            else
                % There is an error in the OGS - no O2 is produced and we
                % skip the tick function
                vaporMolesRemoved = 0;
                return
                
            end
            
        end
    end
    
end

