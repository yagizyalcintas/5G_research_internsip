classdef nrSchedulerRoundRobin < nr5g.internal.nrScheduler
    %nrSchedulerRoundRobin Implements round-robin scheduler
    %
    %   Note: This is an internal undocumented class and its API and/or
    %   functionality may change in subsequent releases.

    %   Copyright 2022 The MathWorks, Inc.

    methods
        function obj = nrSchedulerRoundRobin(simParameters)
            %nrSchedulerRoundRobin Construct an instance of this class

            % Invoke the super class constructor to initialize the properties
            obj = obj@nr5g.internal.nrScheduler(simParameters);
        end

        function [selectedUEs, mcsIndices] = runSchedulingStrategy(obj, schedulerInput)
            %runSchedulingStrategy Implements the round-robin scheduling
            %
            %   [SELECTEDUE, MCSINDEX] = runSchedulingStrategy(~,SCHEDULERINPUT) runs
            %   the round robin algorithm and returns the selected UE for this RBG
            %   (among the eligible ones), along with the suitable MCS index based on
            %   the channel condition. This function gets called for selecting a UE for
            %   each RBG to be used for new transmission, i.e. once for each of the
            %   remaining RBGs after assignment for retransmissions is completed.
            %
            %   SCHEDULERINPUT structure contains the following fields which scheduler
            %   would use (not necessarily all the information) for selecting the UE to
            %   which RBG would be assigned.
            %
            %       eligibleUEs    -  RNTI of the eligible UEs contending for the RBG
            %       RBGIndex       -  RBG index in the slot which is getting scheduled
            %       slotNum        -  Slot number in the frame whose RBG is getting scheduled
            %       RBGSize        -  RBG Size in terms of number of RBs
            %       cqiRBG         -  Uplink Channel quality on RBG for UEs. This is a
            %                         N-by-P  matrix with uplink CQI values for UEs on
            %                         different RBs of RBG. 'N' is the number of eligible
            %                         UEs and 'P' is the RBG size in RBs
            %       mcsRBG         -  MCS for eligible UEs based on the CQI values of the RBs
            %                         of RBG. This is a N-by-2 matrix where 'N' is number of
            %                         eligible UEs. For each eligible UE it contains, MCS
            %                         index (first column) and efficiency (bits/symbol
            %                         considering both Modulation and Coding scheme)
            %       pastDataRate   -  Served data rate. Vector of N elements containing
            %                         historical served data rate to eligible UEs. 'N' is
            %                         the number of eligible UEs
            %       bufferStatus   -  Buffer-Status of UEs. Vector of N elements where 'N'
            %                         is the number of eligible UEs, containing pending
            %                         buffer status for UEs
            %       ttiDur         -  TTI duration in ms
            %       UEs            -  RNTI of all the UEs (even the non-eligible ones for
            %                         this RBG)
            %       
            %       lastSelectedUE - The RNTI of the UE which was assigned the last
            %                        scheduled RBG
            %
            %   SELECTEDUE The UE (among the eligible ones) which gets assigned
            %                   this particular resource block group
            %
            %   MCSINDEX   The suitable MCS index based on the channel conditions

            % Select next UE for scheduling. After the last selected UE, go
            % in sequence and find the first UE which is eligible and with non-zero
            % buffer status
            %%% CHECK HERE. MAYBE BEFORE SELECTIING A UE WE CAN DO
            % SLEEP() WHICH WOULD DELAY THE FIRST TRANSMISSION
            selectedUEs = -1;
            mcsIndices = -1;
            scheduledUE = schedulerInput.lastSelectedUE;
            eligibleUEs=schedulerInput.eligibleUEs;
            for i = 1:length(schedulerInput.UEs)
                scheduledUE = mod(scheduledUE, length(schedulerInput.UEs))+1; % Next UE selected in round-robin fashion
                % Selected UE through round-robin strategy. UE must be in eligibility-list
                % otherwise move to the next UE
                index = find(schedulerInput.eligibleUEs == scheduledUE, 1);
                if(~isempty(index))
                    % Select the UE and calculate the expected MCS index
                    % for uplink grant, based on the CQI values for the RBs
                    % of this RBG
                    selectedUEs = schedulerInput.eligibleUEs(index);
                    mcsIndices = schedulerInput.mcsRBG(index, 1);
                    % Check if MUMIMO is enabled for DL
                    if (schedulerInput.linkDir == 0) && ~isempty(obj.UserPairingMatrix)
                        % Extract number of MUMIMO capable UEs
                        mumimoUEs = extractMUMIMOUserlist(obj, schedulerInput);
                        % If selected UE is MUMIMO capable UE
                        if mumimoUEs(index)
                            mumimoUEsIndex=eligibleUEs(mumimoUEs==1);
                            mumimoUEsIndex=intersect(mumimoUEsIndex,eligibleUEs(eligibleUEs~=selectedUEs));
                            selectedUERank = schedulerInput.selectedRank(index);
                            selectedUEMcs = schedulerInput.mcsRBG(index, 1);
                            % Get paired UE list for the primary user
                            [selectedUEs, mcsIndices] = selectPairedUEs(obj, schedulerInput, selectedUEs, selectedUEMcs, selectedUERank, mumimoUEsIndex);
                            selectedUEs=selectedUEs(selectedUEs~=0);
                            mcsIndices=mcsIndices(mcsIndices~=0);
                        end
                    end
                    break;
                end
            end
        end

        function [allottedUEs, freqAllocation, mcsIndex, pairedStatus] = runSchedulingStrategyRAT1(obj, schedulerInput)
            %runSchedulingStrategyRAT1 Implements the round-robin strategy for RAT-1 scheduling scheme
            %
            %   [allottedUEs, freqAllocation, mcsIndex, pairedStatus] = runSchedulingStrategyRAT1(obj, schedulerInput)
            %   runs the round robin algorithm and returns the allotted UEs with their
            %   frequency allocation for this slot, along with the
            %   suitable mcsIndex based on the channel condition. This
            %   function gets called for selecting UEs for new
            %   transmission, i.e. once for each slot after assignment for
            %   retransmissions is completed.
            %
            %   schedulerInput structure contains the following fields which scheduler
            %   would use for selecting the UE to which RBs would be assigned.
            %
            %       eligibleUEs    -  RNTI of the eligible UEs contending for the available RBs
            %       rbRequirement  -  RB requirement of UEs as per their buffered amount and CQI-based MCS
            %       bufferStatus   -  Buffer-Status of UEs. Vector of N elements where 'N'
            %                         is the number of eligible UEs, containing pending
            %                         buffer status for UEs
            %       rbOccupancyBitmap - Holds RB occupancy status after RBs got
            %                         allotted for retransmission
            %       rbAllocationLimit - Maximum number of RBs allotted to a UE in a particular slot
            %       channelQuality -  Channel quality information of the eligible UEs.
            %                         Vector of N elements where 'N' is the number of eligible UEs
            %       lastSelectedUE - The RNTI of the UE which was assigned the last scheduled RB
            %       linkDir        - Link direction as DL (value 0) or UL (value 1)
            %       numUEsReTx     - Number of UEs that are assigned retransmission grants

            % Calculate the number of eligibleUEs for new transmission based on max
            % allowed users per TTI
            eligibleUEs = schedulerInput.eligibleUEs;
            numEligibleUEs = min(length(eligibleUEs), obj.MaxNumUsersPerTTI - schedulerInput.numUEsRetx);

            % To store allotted RB count to UE in the slot
            allottedRBCount = zeros(numEligibleUEs, 1);
            allottedUEs = zeros(numEligibleUEs, 1);
            mcsIndex = zeros(numEligibleUEs, 1);
            freqAllocation = zeros(numEligibleUEs, 2);
            pairedStatus = zeros(numEligibleUEs, 1);

            if numEligibleUEs > 0
                rbOccupancyBitmap = schedulerInput.rbOccupancyBitmap;
                % First unoccupied RB in the rbOccupancyBitmap
                startRBIndex = find(rbOccupancyBitmap==0, 1)-1;
                % Number of available RBs in the rbOccupancyBitmap
                availableRBs = sum(~rbOccupancyBitmap);
                % Select index of the first UE for scheduling. After the last selected UE, go in
                % sequence and find index of the first eligible UE
                scheduledUEIndex = find(eligibleUEs>schedulerInput.lastSelectedUE, 1);
                if isempty(scheduledUEIndex)
                    scheduledUEIndex = 1;
                end

                % Shift eligibleUEs set such that first eligible UE (as per
                % round-robin assignment) is at first index
                eligibilityOrder = circshift(eligibleUEs,  [0 -(scheduledUEIndex-1)]);
                eligibleUEs = eligibilityOrder(1:numEligibleUEs);

                if numEligibleUEs > availableRBs
                    % Allot 1 RB each till available RBs are exhausted
                    allottedUEs = eligibleUEs(1:availableRBs);
                    allottedRBCount(1:availableRBs) = 1;
                else 
                    nextUEIndex = 0;
                    rbRequirement = schedulerInput.rbRequirement;
                    % Shuffle the eligible UEs so that UEs listed first in list do not get
                    % unfair advantage for extra RBs after equal distribution
                    randomOrder = randperm(length(eligibleUEs));
                    eligibleUEs = eligibleUEs(randomOrder);
                    for i=1:availableRBs
                        nextUEIndex = mod(nextUEIndex+1,numEligibleUEs);
                        if nextUEIndex == 0
                           nextUEIndex = numEligibleUEs;
                        end
                        if allottedRBCount(nextUEIndex) < rbRequirement(eligibleUEs(nextUEIndex))
                            % RB requirement is not satisfied yet for the UE
                            allottedRBCount(nextUEIndex) = allottedRBCount(nextUEIndex) + 1;
                        else
                            % RB requirement is satisfied for the UE. Give the RB to the next UE in
                            % round-robin order
                            for j=1:numEligibleUEs-1
                                nextUEIndex = mod(nextUEIndex+1, numEligibleUEs);
                                if nextUEIndex == 0
                                    nextUEIndex = numEligibleUEs;
                                end
                                if allottedRBCount(nextUEIndex) < rbRequirement(eligibleUEs(nextUEIndex))
                                    allottedRBCount(nextUEIndex) = allottedRBCount(nextUEIndex) + 1;
                                    break;
                                end
                            end
                        end
                    end
                    % Rearrange as per the original order
                    eligibleUEs(randomOrder) = eligibleUEs(1:numEligibleUEs);
                    allottedRBCount(randomOrder) = allottedRBCount(1:numEligibleUEs);
                    allottedUEs = eligibleUEs;
                end

                % Check if MUMIMO is enabled for DL
                if (schedulerInput.linkDir == 0) && ~isempty(obj.UserPairingMatrix)
                    % Get updated allocation information after user pairing
                    % logic
                    [allottedUEs, allottedRBCount, pairedStatus] = userPairingRAT1(obj, schedulerInput, allottedRBCount, availableRBs, eligibleUEs);
                    allottedUEs=allottedUEs(allottedUEs~=0);
                end

                % AllottedRBCount should not exceed allocation limit
                allottedRBCount(allottedRBCount>schedulerInput.rbAllocationLimit) = schedulerInput.rbAllocationLimit;

                for index = 1:length(allottedUEs)
                    allottedRB = allottedRBCount(index);
                    % Allot RBs to the selected UE in this TTI
                    freqAllocation(index, :) = [startRBIndex allottedRB];
                    % Calculate average CQI for the allotted resource blocks
                    cqiRB = schedulerInput.channelQuality(allottedUEs(index), startRBIndex+1:startRBIndex+allottedRB);
                    cqiSetRB = floor(mean(cqiRB, 2));
                    % Calculate average MCS value corresponding to cqiSetRB
                    mcsIndex(index) = getMCSIndex(obj, cqiSetRB, schedulerInput.linkDir);
                    if ~pairedStatus(index)
                        startRBIndex = startRBIndex+allottedRB;
                    end
                end
                % Read the valid rows
                freqAllocation = freqAllocation(1:length(allottedUEs), :);
                mcsIndex = mcsIndex(1:length(allottedUEs));
                pairedStatus = pairedStatus(1:length(allottedUEs));
            end
        end
    end
end