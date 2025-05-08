classdef nrGNBMAC < nr5g.internal.nrMAC
    %nrGNBMAC Implements gNB MAC functionality
    %   The class implements the gNB MAC and its interactions with RLC and
    %   Phy for Tx and Rx chains. Both, frequency division duplex (FDD) and
    %   time division duplex (TDD) modes are supported. It contains
    %   scheduler entity which takes care of uplink (UL) and downlink (DL)
    %   scheduling. Using the output of UL and DL schedulers, it implements
    %   transmission of UL and DL assignments. UL and DL assignments are
    %   sent out-of-band from MAC itself (without using frequency resources
    %   and with guaranteed reception), as physical downlink control
    %   channel (PDCCH) is not modeled. Physical uplink control channel
    %   (PUCCH) is not modeled too, so the control packets from UEs: buffer
    %   status report (BSR), PDSCH feedback, and DL channel state
    %   information (CSI) report are also received out-of-band. Hybrid
    %   automatic repeat request (HARQ) control mechanism to enable
    %   retransmissions is implemented. MAC controls the HARQ processes
    %   residing in physical layer
    %
    %   Note: This is an internal undocumented class and its API and/or
    %   functionality may change in subsequent releases.

    %   Copyright 2022 The MathWorks, Inc.

    properties(Hidden)
        %Scheduler Scheduler object
        Scheduler

        %RxContextFeedback Rx context at gNB used for feedback reception (ACK/NACK) of PDSCH transmissions
        % N-by-P-by-K cell array where 'N' is the number of UEs, 'P' is the
        % number of symbols in a 10 milliseconds (ms) frame and K is the number of
        % downlink HARQ processes. This is used by gNB in the reception of
        % ACK/NACK from UEs. An element at index (i, j, k) in this array,
        % stores the downlink grant for the UE with RNTI 'i' where
        % 'j' is the symbol number from the start of the frame where
        % ACK/NACK is expected for UE's HARQ process number 'k'
        RxContextFeedback
    end

    properties(SetAccess = private)
        %UEs RNTIs of the UEs connected to the gNB
        UEs

        %ScheduledResources Structure containing information about scheduling event
        ScheduledResources

        %UEInfo Information about the UEs connected to the GNB
        % N-by-1 array where 'N' is the number of UEs. Each element in the
        % array is a structure with two fields:
        %   ID - Node id of the UE
        %   Name - Node Name of the UE
        UEInfo
    end

    properties (Access = private)
        %DownlinkTxContext Tx context used for PDSCH transmissions
        % N-by-P cell array where is N is number of UEs and 'P' is number of
        % symbols in a 10 ms frame. An element at index (i, j) stores the
        % downlink grant for UE with RNTI 'i' with PDSCH transmission scheduled to
        % start at symbol 'j' from the start of the frame. If no PDSCH
        % transmission scheduled, cell element is empty
        DownlinkTxContext

        %UplinkRxContext Rx context used for PUSCH reception
        % N-by-P cell array where 'N' is the number of UEs and 'P' is the
        % number of symbols in a 10 ms frame. It stores uplink resource
        % assignment details done to UEs. This is used by gNB in the
        % reception of uplink packets. An element at position (i, j) stores
        % the uplink grant corresponding to a PUSCH reception expected from
        % UE with RNTI 'i' starting at symbol 'j' from the start of the frame. If
        % there is no assignment, cell element is empty
        UplinkRxContext

        %CSIRSTxInfo Contains the information about CSI-RS transmissions
        % It is an array of size N-by-2 where N is the number of unique
        % CSI-RS periodicity, slot offset pairs configured for the UEs. Each
        % row of the array contains CSI-RS transmission periodicity (in
        % nanoseconds) and the next absolute transmission start time (in
        % nanoseconds) to the UEs.
        CSIRSTxInfo = [Inf 0]

        %SRSRxInfo Contains the information about SRS receptions
        % It is an array of size N-by-2 where N is the number of unique
        % SRS periodicity, slot offset pairs configured for the UEs. Each
        % row of the array contains SRS reception periodicity (in
        % nanoseconds) and the next absolute reception start time (in
        % nanoseconds) from the UEs.
        SRSRxInfo = [Inf 0]

        %SchedulerNextInvokeTime Time (in nanoseconds) at which scheduler will get invoked next time
        SchedulerNextInvokeTime = 0;

        %ULGrantFieldNames Contains the field names in the uplink grant
        ULGrantFieldNames;

        %ULGrantFieldNamesCount Stores the total number of field names in the uplink grant
        ULGrantFieldNamesCount;

        %DLGrantFieldNames Contains the field names in the downlink grant
        DLGrantFieldNames;

        %DLGrantFieldNames Stores the total number of field names in the downlink grant
        DLGrantFieldNamesCount;
    end

    properties (Access = protected)
        %% Transient objects maintained for optimization
        %CarrierConfigUL nrCarrierConfig object for UL
        CarrierConfigUL
        %CarrierConfigDL nrCarrierConfig object for DL
        CarrierConfigDL
    end

    methods
        function obj = nrGNBMAC(param, notificationFcn)
            %nrGNBMAC Construct a gNB MAC object
            %
            % PARAM is a structure including the following fields:
            %   NCellID            - Physical cell ID. Values: 0 to 1007 (TS 38.211, sec 7.4.2.1)
            %   SubcarrierSpacing  - Subcarrier spacing used
            %   NumHARQ            - Number of HARQ processes
            %
            % NOTIFICATIONFCN - It is a handle of the node's processEvents
            % method

            obj.NotificationFcn = notificationFcn;
            obj.MACType = 0; % gNB MAC type
            obj.NCellID = param.NCellID;
            obj.SubcarrierSpacing = param.SubcarrierSpacing;
            obj.NumHARQ = param.NumHARQ;

            slotDuration = 1/(obj.SubcarrierSpacing/15); % In ms
            obj.SlotDurationInNS = slotDuration * 1e6; % In nanoseconds
            obj.NumSlotsFrame = 10/slotDuration; % Number of slots in a 10 ms frame
            obj.NumSymInFrame = obj.NumSlotsFrame*obj.NumSymbols;
            % Calculate symbol end times (in nanoseconds) in a slot for the
            % given SCS
            obj.SymbolEndTimesInSlot = round(((1:obj.NumSymbols)*slotDuration)/obj.NumSymbols, 4) * 1e6;
            % Duration of each symbol (in nanoseconds)
            obj.SymbolDurationsInSlot = obj.SymbolEndTimesInSlot(1:obj.NumSymbols) - [0 obj.SymbolEndTimesInSlot(1:13)];

            % No SRS resource
            obj.SRSRxInfo = Inf(1, 2);
            % Create carrier configuration object for UL
            obj.CarrierConfigUL = nrCarrierConfig("SubcarrierSpacing",obj.SubcarrierSpacing);

            % Resource scheduling event data
            obj.ScheduledResources = struct('CurrentTime', 0, ...
                'NCellID', obj.NCellID, ...
                'TimingInfo', [0 0 0], ...
                'ULGrants', struct([]), ...
                'DLGrants', struct([]));

            obj.PacketStruct.Type= 2; % 5G packet
            obj.PacketStruct.Metadata = struct('NCellID', obj.NCellID, 'RNTI', [], 'PacketType', []);

            % Store the uplink and downlink grant related information
            obj.ULGrantFieldNames = fieldnames(obj.UplinkGrantStruct);
            obj.ULGrantFieldNamesCount = numel(obj.ULGrantFieldNames);
            obj.DLGrantFieldNames = fieldnames(obj.DownlinkGrantStruct);
            obj.DLGrantFieldNamesCount = numel(obj.DLGrantFieldNames);
        end

        function addConnection(obj, ueInfo)
            %addConnection Configures the GNB MAC with UE connection information
            %
            % connectionInfo is a structure including the following fields:
            %
            % RNTI                     - Radio network temporary identifier
            %                            specified within [1, 65519]. Refer
            %                            table 7.1-1 in 3GPP TS 38.321.
            % UEID                     - Node ID of the UE
            % UEName                   - Node name of the UE
            % CSIRSConfiguration       - Cell array containing the CSI-RS configuration information as an
            %                            object of type nrCSIRSConfig.
            % CSIRSConfigurationRSRP   - CSI-RS resource set configurations corresponding to the SSB directions.
            %                            It is a cell array of length N-by-1 where 'N' is the number of
            %                            maximum number of SSBs in a SSB burst. Each element of the array
            %                            at index 'i' corresponds to the CSI-RS resource set associated
            %                            with SSB 'i-1'. The number of CSI-RS resources in each resource
            %                            set is same for all configurations.
            % SRSConfiguration         - SRS configuration specified as an object of type nrSRSConfig

            obj.UEs = [obj.UEs ueInfo.RNTI];
            nodeInfo = struct('ID', ueInfo.UEID, 'Name', ueInfo.UEName);
            obj.UEInfo = [obj.UEInfo nodeInfo];

            if isfield(ueInfo, 'CSIRSConfigurationRSRP') && ~isempty(ueInfo.CSIRSConfigurationRSRP)
                obj.CSIRSConfigurationRSRP{end+1} = ueInfo.CSIRSConfigurationRSRP;
            end

            % Append CSI-RS configuration (only if it is unique)
            if ~isempty(ueInfo.CSIRSConfiguration)
                uniqueConfiguration = true;
                for idx = 1:numel(obj.CSIRSConfiguration)
                    if isequal(obj.CSIRSConfiguration{idx}, ueInfo.CSIRSConfiguration)
                        uniqueConfiguration = false;
                        break;
                    end
                end
                if uniqueConfiguration
                    obj.CSIRSConfiguration{end+1} = ueInfo.CSIRSConfiguration;
                end
            end

            obj.SRSConfiguration{end+1} = ueInfo.SRSConfiguration;
            % Update the MAC context after each UE is connected
            updateMACContext(obj);
        end

        function nextInvokeTime = run(obj, currentTime, packets)
            %run Run the gNB MAC layer operations and return the next invoke time in nanoseconds
            %   NEXTINVOKETIME = run(OBJ, CURRENTTIME, PACKETS) runs the
            %   MAC layer operations and returns the next invoke time.
            %
            %   NEXTINVOKETIME is the next invoke time (in nanoseconds) for
            %   MAC.
            %
            %   CURRENTTIME is the current time (in nanoseconds).
            %
            %   PACKETS are the received packets from other nodes.

            elapsedTime = currentTime - obj.LastRunTime; % In nanoseconds
            if currentTime > obj.LastRunTime
                % Update the LCP timers
                obj.ElapsedTimeSinceLastLCP  = obj.ElapsedTimeSinceLastLCP + round(elapsedTime*1e-6, 4);
                obj.LastRunTime = currentTime;

                % Find the current SFN
                obj.SFN = mod(floor(currentTime/obj.FrameDurationInNS), 1024);
                absoluteSlotNum = floor(currentTime/obj.SlotDurationInNS);
                % Current slot number in 10 ms frame
                obj.CurrSlot = mod(absoluteSlotNum, obj.NumSlotsFrame);

                scheduler = obj.Scheduler;
                if scheduler.DuplexMode % TDD
                    % Current slot number in DL-UL pattern
                    obj.CurrDLULSlotIndex = mod(absoluteSlotNum, scheduler.NumDLULPatternSlots);
                end

                % Find the current symbol in the current slot
                durationCompletedInCurrSlot = mod(currentTime, obj.SlotDurationInNS);
                obj.CurrSymbol = find(durationCompletedInCurrSlot < obj.SymbolEndTimesInSlot, 1) - 1;

                % Update timing info context
                obj.TimingInfo.SFN = obj.SFN;
                obj.TimingInfo.Slot = obj.CurrSlot;
                obj.TimingInfo.Symbol = obj.CurrSymbol;
            end

            % Receive and process control packet
            controlRx(obj, packets);

            % Avoid running MAC operations more than once in the same symbol
            symNumFrame = obj.CurrSlot * obj.NumSymbols + obj.CurrSymbol;
            if obj.PreviousSymbol == symNumFrame && elapsedTime < obj.SlotDurationInNS/obj.NumSymbols
                if obj.NCellID == 1
                    obj.SchedulerNextInvokeTime = obj.SchedulerNextInvokeTime + 200000; %% CHECK HERE I ADDED THIS IF 
                end
                nextInvokeTime = getNextInvokeTime(obj, currentTime);
                return;
            end

            % Send data Tx request to Phy for transmission(s) which is(are)
            % scheduled to start at current symbol. Construct and send the
            % DL MAC PDUs scheduled for current symbol to Phy
            dataTx(obj, currentTime);

            % Send data Rx request to Phy for reception(s) which is(are) scheduled to start at current symbol
            dataRx(obj, currentTime);

            % Run schedulers (UL and DL) and send the resource assignment information to the UEs.
            % Resource assignments returned by a scheduler (either UL or
            % DL) is empty, if either scheduler was not scheduled to run at
            % the current time or no resource got assigned
            if currentTime == obj.SchedulerNextInvokeTime % Run scheduler at slot boundary
                resourceAssignmentsUL = runULScheduler(obj);
                resourceAssignmentsDL = runDLScheduler(obj);
                % Check if UL/DL assignments are done
                if ~isempty(resourceAssignmentsUL) || ~isempty(resourceAssignmentsDL)
                    % Construct and send UL assignments and DL assignments to
                    % UEs. UL and DL assignments are assumed to be sent
                    % out-of-band without using any frequency-time resources,
                    % from gNB's MAC to UE's MAC
                    controlTx(obj, resourceAssignmentsUL, resourceAssignmentsDL);
                end
                if (currentTime >= 1000000) && (mod(currentTime,500000)==0) && (obj.NCellID == 1)

                    obj.SchedulerNextInvokeTime = currentTime + 200000;

                else
                    obj.SchedulerNextInvokeTime = currentTime + obj.SlotDurationInNS;
                end
            
                %obj.SchedulerNextInvokeTime = obj.SchedulerNextInvokeTime + obj.SlotDurationInNS; %%CHECK HERE THIS IS THE NEXT INVOKE TIME 
            end

            % Send request to Phy for:
            % (i) Non-data transmissions scheduled in this slot (currently
            % only CSI-RS supported)
            % (ii) Non-data receptions scheduled in this slot (currently
            % only SRS supported)
            %
            % Send at the first symbol of the slot for all the non-data
            % transmissions/receptions scheduled in the entire slot
            idxList = find(obj.CSIRSTxInfo(:, 2) == currentTime);
            if ~isempty(idxList)
                dlControlRequest(obj, currentTime);
                % Update the next CSI-RS Tx times
                obj.CSIRSTxInfo(idxList, 2) = obj.CSIRSTxInfo(idxList, 1) + currentTime;
            end
            idxList = find(obj.SRSRxInfo(:, 2) == currentTime);
            if ~isempty(idxList)
                ulControlRequest(obj, currentTime);
                % Update the next SRS Rx times
                obj.SRSRxInfo(idxList, 2) = obj.SRSRxInfo(idxList, 1) + currentTime;
            end

            % Update the previous symbol to the current symbol in the frame
            obj.PreviousSymbol = symNumFrame;
            % Return the next invoke time for MAC
            nextInvokeTime = getNextInvokeTime(obj, currentTime);
        end

        function addScheduler(obj, scheduler)
            %addScheduler Add scheduler object to MAC
            %   addScheduler(OBJ, SCHEDULER) adds the scheduler to MAC.
            %
            %   SCHEDULER Scheduler object.

            obj.Scheduler = scheduler;

            obj.PDSCHInfo.PDSCHConfig.DMRS = nrPDSCHDMRSConfig('DMRSConfigurationType', obj.Scheduler.PDSCHDMRSConfigurationType, ...
                'DMRSTypeAPosition', obj.Scheduler.DMRSTypeAPosition);
            obj.PUSCHInfo.PUSCHConfig.DMRS = nrPUSCHDMRSConfig('DMRSConfigurationType', obj.Scheduler.PUSCHDMRSConfigurationType, ...
                'DMRSTypeAPosition', obj.Scheduler.DMRSTypeAPosition);

            obj.CarrierConfigUL.NSizeGrid = obj.Scheduler.NumResourceBlocks;
            % Create carrier configuration object for DL
            obj.CarrierConfigDL = obj.CarrierConfigUL;

            % Set the MACPDUReceived event information
            obj.MACPDUReceived.DuplexMode = scheduler.DuplexMode;
            obj.MACPDUReceived.NCellID = obj.NCellID;
        end

        function rxIndication(obj, rxInfo)
            %rxIndication Packet reception from Phy
            %   rxIndication(OBJ, RXINFO) receives a MAC PDU from
            %   Phy.
            %   RXINFO is a structure containing information about the
            %   reception.
            %       RNTI   - Radio network temporary identifier
            %       HARQID - HARQ process identifier
            %       MACPDU - It is a vector of decimal octets received from Phy.
            %       CRCFlag- It is the success(value as 0)/failure(value as 1)
            %       indication from Phy.

            isRxSuccess = ~rxInfo.CRCFlag; % CRC value 0 indicates successful reception

            % Notify PUSCH Rx result to scheduler for updating the HARQ context
            rxResultInfo.RNTI = rxInfo.RNTI;
            rxResultInfo.RxResult = isRxSuccess;
            rxResultInfo.HARQID = rxInfo.HARQID;
            handleULRxResult(obj.Scheduler, rxResultInfo);
            if isRxSuccess % Packet received is error free
                [lcidList, sduList] = nrMACPDUDecode(rxInfo.MACPDU, obj.ULType);
                for sduIndex = 1:numel(lcidList)
                    if lcidList(sduIndex) >=4 && lcidList(sduIndex) <= 32
                        obj.RLCRxFcn{rxInfo.RNTI, lcidList(sduIndex)}(sduList{sduIndex});
                    end
                end
                obj.StatReceivedBytes(rxResultInfo.RNTI) = obj.StatReceivedBytes(rxResultInfo.RNTI) + length(rxInfo.MACPDU);
                obj.StatReceivedPackets(rxResultInfo.RNTI) = obj.StatReceivedPackets(rxResultInfo.RNTI) + 1;
            end

            % Invoke the event handler
            macPDUReceived = obj.MACPDUReceived;
            macPDUReceived.RNTI = rxInfo.RNTI;
            macPDUReceived.TimingInfo = [obj.SFN obj.CurrSlot obj.CurrSymbol];
            macPDUReceived.LinkType = obj.ULType; % Uplink
            macPDUReceived.HARQID = rxInfo.HARQID;
            macPDUReceived.MACPDU = rxInfo.MACPDU;
            obj.NotificationFcn('MACPDUReceived', macPDUReceived);
        end

        function srsIndication(obj, csiMeasurement)
            %srsIndication Reception of SRS measurements from Phy
            %   srsIndication(OBJ, csiMeasurement) receives the UL channel
            %   measurements from Phy, measured on the configured SRS for the
            %   UE.
            %   csiMeasurement - It is a structure and contains following
            %   fields
            %       RNTI - UE corresponding to the SRS
            %       RankIndicator - Rank indicator
            %       TPMI - Measured transmitted precoding matrix indicator (TPMI)
            %       CQI - CQI corresponding to RANK and TPMI. It is a vector
            %       of size 'N', where 'N' is number of RBs in bandwidth. Value
            %       at index 'i' represents CQI value at RB-index 'i'.

            updateChannelQualityUL(obj.Scheduler, csiMeasurement);
        end

        function updateBufferStatus(obj, lchBufferStatus)
            %updateBufferStatus Update DL buffer status for UEs, as notified by RLC
            %
            %   updateBufferStatus(obj, LCHBUFFERSTATUS) updates the
            %   DL buffer status for a logical channel of specified UE
            %
            %   LCHBUFFERSTATUS is the report sent by RLC. It is a
            %   structure with 3 fields:
            %       RNTI - Specified UE
            %       LogicalChannelID - ID of logical channel
            %       BufferStatus - Pending amount of data in bytes for the
            %       specified logical channel of UE.

            updateLCBufferStatusDL(obj.Scheduler, lchBufferStatus);
            obj.LCHBufferStatus(lchBufferStatus.RNTI, lchBufferStatus.LogicalChannelID) = ...
                lchBufferStatus.BufferStatus;
        end

        function status = ueInformation(obj)
            %ueInformation Get the status information of the UEs at gNB
            %
            %   STATUS = ueInformation(OBJ) returns the status information
            %   of UEs at gNB MAC
            %   STATUS - Nx1 array of structures, where N is the number
            %   of UEs. Each structure contains following fields.
            %       ID   - Node ID of the UE
            %       Name - Node name of the UE
            %       RNTI - RNTI of the UE
            %       BufferSize - Represents the buffer size in bytes
            %       ULChannelQuality - It is a structure and contains
            %       information about the downlink channel quality
            %           RANKINDICATOR - Rank indicator
            %           TPMI - Measured transmitted precoded matrix indicator (TPMI)
            %           CQI - CQI corresponding to RANK and PMISET. It is a
            %           vector of size 'N', where 'N' is number of RBs in
            %           bandwidth. Value at index 'i' represents CQI value
            %           at RB-index 'i'.

            numUEs = numel(obj.UEs);
            status = cell(numUEs, 1);
            for ueIdx=1:numUEs
                status{ueIdx} = struct('ID', obj.UEInfo(ueIdx).ID, 'Name', obj.UEInfo(ueIdx).Name, ...
                    'RNTI', obj.UEs(ueIdx), 'BufferSize', sum(obj.LCHBufferStatus(ueIdx, :)), ...
                    'ULChannelQuality', obj.Scheduler.CSIMeasurementUL(ueIdx));
            end
            status = [status{1:numUEs}]';
        end

        function pdu = constructMACPDU(obj, tbs, rnti)
            %CONSTRUCTMACPDU Construct and return a MAC PDU based on transport block size
            %
            %   CONSTRUCTMACPDU(OBJ, TBS, RNTI) returns a DL MAC PDU for
            %   UE identified with specified RNTI.
            %
            %   TBS Transport block size in bytes.
            %
            %   RNTI RNTI of the UE for which DL MAC PDU needs to be
            %   constructed.

            controlPDUList = {};
            paddingSubPDU = [];

            % Run LCP and construct MAC PDU
            [dataSubPDUList, remainingBytes] = performLCP(obj, tbs, rnti);
            if remainingBytes > 0
                paddingSubPDU = nrMACSubPDU(remainingBytes);
            end
            % Construct MAC PDU by concatenating subPDUs. Downlink MAC PDU constructed
            % as per 3GPP TS 38.321 Figure 6.1.2-4
            pdu = [vertcat(controlPDUList{:}); vertcat(dataSubPDUList{:}); paddingSubPDU];
        end

        function macStats = statistics(obj)
            %statistics Return the gNB MAC statistics for each UE
            %
            %   MACSTATS = statistics(OBJ) Returns the MAC statistics of
            %   each UE at gNB MAC
            %
            %   MACSTATS - Nx1 array of structures, where N is the number
            %   of UEs. Each structure contains following fields.
            %       UEID                 - Node ID of the UE
            %       UEName               - Node name of the UE
            %       RNTI                 - RNTI of the UE
            %       TransmittedPackets   - Number of packets transmitted in DL
            %                              corresponding to new transmissions
            %       TransmittedBytes     - Number of bytes transmitted in DL
            %                              corresponding to new transmissions
            %       ReceivedPackets      - Number of packets received in UL
            %       ReceivedBytes        - Number of bytes received in UL
            %       Retransmissions      - Number of retransmission indications in DL
            %       RetransmissionBytes  - Number of bytes corresponding to retransmissions
            %                              retransmitted in DL

            numUEs = numel(obj.UEs);
            macStats = cell(1,numUEs);
            for ueIdx=1:numUEs
                macStats{ueIdx} = struct('UEID', obj.UEInfo(ueIdx).ID, 'UEName', obj.UEInfo(ueIdx).Name, ...
                    'RNTI', obj.UEs(ueIdx), 'TransmittedPackets', obj.StatTransmittedPackets(ueIdx), ...
                    'TransmittedBytes', obj.StatTransmittedBytes(ueIdx), 'ReceivedPackets', ...
                    obj.StatReceivedPackets(ueIdx), 'ReceivedBytes', obj.StatReceivedBytes(ueIdx), ...
                    'Retransmissions', obj.StatRetransmittedPackets(ueIdx), ...
                    'RetransmissionBytes', obj.StatRetransmittedBytes(ueIdx));
            end
            macStats = [macStats{1:numUEs}]';
        end
    end

    methods (Hidden)
        function resourceAssignments = runULScheduler(obj)
            %runULScheduler Run the UL scheduler
            %
            %   RESOURCEASSIGNMENTS = runULScheduler(OBJ) runs the UL scheduler
            %   and returns the resource assignments structure array.
            %
            %   RESOURCEASSIGNMENTS is a structure that contains the
            %   UL resource assignments information.

            resourceAssignments = runULScheduler(obj.Scheduler, obj.TimingInfo);
            % Set Rx context at gNB by storing the UL grants. It is set at
            % symbol number in the 10 ms frame, where UL reception is
            % expected to start. gNB uses this to anticipate the reception
            % start time of uplink packets
            for i = 1:length(resourceAssignments)
                grant = resourceAssignments{i};
                slotNum = mod(obj.CurrSlot + grant.SlotOffset, obj.NumSlotsFrame); % Slot number in the frame for the grant
                obj.UplinkRxContext{grant.RNTI, slotNum*obj.NumSymbols + grant.StartSymbol + 1} = grant;
            end
        end

        function resourceAssignments = runDLScheduler(obj)
            %runDLScheduler Run the DL scheduler
            %
            %   RESOURCEASSIGNMENTS = runDLScheduler(OBJ) runs the DL scheduler
            %   and returns the resource assignments structure array.
            %
            %   RESOURCEASSIGNMENTS is a structure that contains the
            %   DL resource assignments information.

            resourceAssignments = runDLScheduler(obj.Scheduler, obj.TimingInfo);
            % Update Tx context at gNB by storing the DL grants at the
            % symbol number (in the 10 ms frame) where DL transmission
            % is scheduled to start
            for i = 1:length(resourceAssignments)
                grant = resourceAssignments{i};
                slotNum = mod(obj.CurrSlot + grant.SlotOffset, obj.NumSlotsFrame); % Slot number in the frame for the grant
                obj.DownlinkTxContext{grant.RNTI, slotNum*obj.NumSymbols + grant.StartSymbol + 1} = grant;
            end
        end

        function dataTx(obj, currentTime)
            % dataTx Construct and send the DL MAC PDUs scheduled for current symbol to Phy
            %
            % dataTx(OBJ, CURRENTTIME) Based on the downlink grants sent earlier, if
            % current symbol is the start symbol of downlink transmissions then
            % send the DL MAC PDUs to Phy.
            %
            % CURRENTTIME is the current time (in nanoseconds).

            symbolNumFrame = obj.CurrSlot*obj.NumSymbols + obj.CurrSymbol; % Current symbol number in the 10 ms frame
            for rnti = 1:length(obj.UEs) % For all UEs
                downlinkGrant = obj.DownlinkTxContext{rnti, symbolNumFrame + 1};
                % If there is any downlink grant corresponding to which a transmission is scheduled at the current symbol
                if ~isempty(downlinkGrant)
                    % Construct and send MAC PDU in adherence to downlink grant
                    % properties
                    sentPDULen = sendMACPDU(obj, rnti, downlinkGrant, currentTime);
                    type = downlinkGrant.Type;
                    % Tx done. Clear the context
                    obj.DownlinkTxContext{rnti, symbolNumFrame + 1} = [];

                    % Calculate the slot number where PDSCH ACK/NACK is
                    % expected
                    feedbackSlot = mod(obj.CurrSlot + downlinkGrant.FeedbackSlotOffset, obj.NumSlotsFrame);

                    % For TDD, the selected symbol at which feedback would
                    % be transmitted by UE is the first UL symbol in
                    % feedback slot. For FDD, it is the first symbol in the
                    % feedback slot (as every symbol is UL)
                    scheduler = obj.Scheduler;
                    if scheduler.DuplexMode % TDD
                        feedbackSlotDLULIdx = mod(obj.CurrDLULSlotIndex + downlinkGrant.FeedbackSlotOffset, scheduler.NumDLULPatternSlots);
                        feedbackSlotPattern = scheduler.DLULSlotFormat(feedbackSlotDLULIdx + 1, :);
                        feedbackSym = (find(feedbackSlotPattern == obj.ULType, 1, 'first')) - 1; % Check for location of first UL symbol in the feedback slot
                    else % FDD
                        feedbackSym = 0;  % First symbol
                    end

                    % Update the context for this UE at the symbol number
                    % w.r.t start of the frame where feedback is expected
                    % to be received
                    obj.RxContextFeedback{rnti, ((feedbackSlot*obj.NumSymbols) + feedbackSym + 1), downlinkGrant.HARQID + 1} = downlinkGrant;

                    if strcmp(type, 'newTx') % New transmission
                        obj.StatTransmittedBytes(rnti) = obj.StatTransmittedBytes(rnti) + sentPDULen;
                        obj.StatTransmittedPackets(rnti) = obj.StatTransmittedPackets(rnti) + 1;
                    else % Retransmission
                        obj.StatRetransmittedBytes(rnti) = obj.StatRetransmittedBytes(rnti) + sentPDULen;
                        obj.StatRetransmittedPackets(rnti) = obj.StatRetransmittedPackets(rnti) + 1;
                    end
                end
            end
        end

        function controlTx(obj, resourceAssignmentsUL, resourceAssignmentsDL)
            %controlTx Construct and send the uplink and downlink assignments to the UEs
            %
            %   controlTx(obj, RESOURCEASSIGNMENTSUL, RESOURCEASSIGNMENTSDL)
            %   Based on the resource assignments done by uplink and
            %   downlink scheduler, send assignments to UEs. UL and DL
            %   assignments are sent out-of-band without the need of
            %   frequency resources.
            %
            %   RESOURCEASSIGNMENTSUL is a cell array of structures that
            %   contains the UL resource assignments information.
            %
            %   RESOURCEASSIGNMENTSDL is a cell array of structures that
            %   contains the DL resource assignments information.

            scheduledResources = obj.ScheduledResources;
            scheduledResources.NCellID = obj.NCellID;
            scheduledResources.TimingInfo = [obj.SFN obj.CurrSlot obj.CurrSymbol];
            % Construct and send uplink grants
            if ~isempty(resourceAssignmentsUL)
                scheduledResources.ULGrants = [resourceAssignmentsUL{:}];
                pktInfo = obj.PacketStruct;
                uplinkGrant = obj.UplinkGrantStruct;
                grantFieldNames = obj.ULGrantFieldNames;
                for i = 1:length(resourceAssignmentsUL) % For each UL assignment
                    grant = resourceAssignmentsUL{i};
                    for ind = 1:obj.ULGrantFieldNamesCount
                        uplinkGrant.(grantFieldNames{ind}) = grant.(grantFieldNames{ind});
                    end
                    % Construct packet information
                    pktInfo.DirectToDestination = obj.UEInfo(grant.RNTI).ID;
                    pktInfo.Data = uplinkGrant;
                    pktInfo.Metadata.PacketType = obj.ULGrant;
                    pktInfo.Metadata.RNTI = grant.RNTI;
                    obj.TxOutofBandFcn(pktInfo); % Send the UL grant out-of-band to UE's MAC
                end
            end

            % Construct and send downlink grants
            if ~isempty(resourceAssignmentsDL)
                scheduledResources.DLGrants = [resourceAssignmentsDL{:}];
                pktInfo = obj.PacketStruct;
                downlinkGrant = obj.DownlinkGrantStruct;
                grantFieldNames = obj.DLGrantFieldNames;
                for i = 1:length(resourceAssignmentsDL) % For each DL assignment
                    grant = resourceAssignmentsDL{i};
                    for ind = 1:obj.DLGrantFieldNamesCount
                        downlinkGrant.(grantFieldNames{ind}) = grant.(grantFieldNames{ind});
                    end
                    % Construct packet information and send the DL grant out-of-band to UE's MAC
                    pktInfo.DirectToDestination = obj.UEInfo(grant.RNTI).ID;
                    pktInfo.Data = downlinkGrant;
                    pktInfo.Metadata.PacketType = obj.DLGrant;
                    pktInfo.Metadata.RNTI = grant.RNTI;
                    obj.TxOutofBandFcn(pktInfo);
                end
            end

            % Notify the node about resource allocation event
            obj.NotificationFcn('ScheduledResources', scheduledResources);
        end

        function controlRx(obj, packets)
            %controlRx Receive callback for BSR, feedback(ACK/NACK) for
            % PDSCH, and CSI report. CSI report can either be of the format
            % ri-pmi-cqi or cri-l1RSRP. The ri-pmi-cqi format specifies the
            % rank indicator (RI), precoding matrix indicator (PMI) and the channel
            % quality indicator (CQI) values. the cri-rsrp format specifies the
            % CSI-RS resource indicator (CRI) and layer-1 reference signal
            % received power (L1-RSRP) values.

            for pktIdx = 1:numel(packets)
                pktInfo = packets(pktIdx);
                if packets(pktIdx).DirectToDestination ~= 0 && ...
                        packets(pktIdx).Metadata.NCellID == obj.NCellID

                    pktType = pktInfo.Metadata.PacketType;
                    rnti = pktInfo.Metadata.RNTI;
                    switch(pktType)
                        case obj.BSR % BSR received
                            bsr = pktInfo.Data;
                            [lcid, payload] = nrMACPDUDecode(bsr, obj.ULType); % Parse the BSR
                            macCEInfo.RNTI = rnti;
                            macCEInfo.LCID = lcid;
                            macCEInfo.Packet = payload{1};
                            processMACControlElement(obj.Scheduler, macCEInfo, obj.LCGPriority(rnti,:));

                        case obj.PDSCHFeedback % PDSCH feedback received
                            feedbackList = pktInfo.Data;
                            symNumFrame = obj.CurrSlot*obj.NumSymbols + obj.CurrSymbol;
                            for harqId = 0:obj.Scheduler.NumHARQ-1 % Check for all HARQ processes
                                feedbackContext =  obj.RxContextFeedback{rnti, symNumFrame+1, harqId+1};
                                if ~isempty(feedbackContext) % If any ACK/NACK expected from the UE for this HARQ process
                                    rxResult = feedbackList(feedbackContext.HARQID+1); % Read Rx success/failure result
                                    % Notify PDSCH Rx result to scheduler for updating the HARQ context
                                    rxResultInfo.RNTI = rnti;
                                    rxResultInfo.RxResult = rxResult;
                                    rxResultInfo.HARQID = harqId;
                                    handleDLRxResult(obj.Scheduler, rxResultInfo);
                                    obj.RxContextFeedback{rnti, symNumFrame+1, harqId+1} = []; % Clear the context
                                end
                            end

                        case obj.CSIReport % CSI report received containing RI, PMI and CQI
                            csiReport = pktInfo.Data;
                            channelQualityInfo.RNTI = rnti;
                            channelQualityInfo.RankIndicator = csiReport.RankIndicator;
                            channelQualityInfo.PMISet = csiReport.PMISet;
                            channelQualityInfo.CQI = csiReport.CQI;
                            channelQualityInfo.W = csiReport.W;
                            updateChannelQualityDL(obj.Scheduler, channelQualityInfo);

                        case obj.CSIReportRSRP % CSI report received containing CRI and RSRP
                            csiReport = pktInfo.Data;
                            channelQualityInfo.RNTI = rnti;
                            channelQualityInfo.CRI = csiReport.CRI;
                            channelQualityInfo.L1RSRP = csiReport.L1RSRP;
                            updateChannelQualityDL(obj.Scheduler, channelQualityInfo);
                    end
                end
            end
        end

        function dataRx(obj, currentTime)
            %dataRx Send Rx start request to Phy for the receptions scheduled to start now
            %
            %   dataRx(OBJ, CURRENTTIME) sends the Rx start request to Phy for the
            %   receptions scheduled to start now, as per the earlier sent
            %   uplink grants.
            %
            %   CURRENTTIME is the current time (in nanoseconds).

            if ~isempty(obj.UplinkRxContext)
                gNBRxContext = obj.UplinkRxContext(:, (obj.CurrSlot * obj.NumSymbols) + obj.CurrSymbol + 1); % Rx context of current symbol
                txUEs = find(~cellfun(@isempty, gNBRxContext)); % UEs which are assigned uplink grants starting at this symbol
                for i = 1:length(txUEs)
                    % For the UE, get the uplink grant information
                    uplinkGrant = gNBRxContext{txUEs(i)};
                    % Send the UE uplink Rx context to Phy
                    rxRequestToPhy(obj, txUEs(i), uplinkGrant, currentTime);
                end
                obj.UplinkRxContext(:, (obj.CurrSlot * obj.NumSymbols) + obj.CurrSymbol + 1) = {[]}; % Clear uplink RX context
            end
        end

        function updateSRSPeriod(obj, rnti, srsPeriod)
            %updateSRSPeriod Update the SRS periodicity of UE

            obj.SRSConfiguration{rnti}.SRSPeriod = srsPeriod;
            % Calculate unique SRS reception time and periodicity
            obj.SRSRxInfo = calculateSRSPeriodicity(obj, obj.SRSConfiguration);
        end
    end

    methods (Access = private)
        function updateMACContext(obj)
            %updateMACContext Update the MAC context when new UE is connected

            obj.StatTransmittedPackets = [obj.StatTransmittedPackets; 0];
            obj.StatTransmittedBytes = [obj.StatTransmittedBytes; 0];
            obj.StatRetransmittedPackets = [obj.StatRetransmittedPackets; 0];
            obj.StatRetransmittedBytes = [obj.StatRetransmittedBytes; 0];
            obj.StatReceivedPackets = [obj.StatReceivedPackets; 0];
            obj.StatReceivedBytes = [obj.StatReceivedBytes; 0];

            obj.ElapsedTimeSinceLastLCP = [obj.ElapsedTimeSinceLastLCP; 0];
            % Configuration of logical channels for UEs
            obj.LogicalChannelConfig = [obj.LogicalChannelConfig; cell(1, obj.MaxLogicalChannels)];
            obj.LCHBjList = [obj.LCHBjList; zeros(1, obj.MaxLogicalChannels)];
            obj.LCHBufferStatus = [obj.LCHBufferStatus; zeros(1, obj.MaxLogicalChannels)];
            % Initialize LCG with lowest priority level for all the UEs. Here
            % lowest priority level is indicated by higher value
            obj.LCGPriority = [obj.LCGPriority; obj.MaxPriorityForLCH*ones(1,8)];
            % Extend the cell array to hold the RLC entity callbacks of the UE
            obj.RLCTxFcn = [obj.RLCTxFcn; cell(1, obj.MaxLogicalChannels)];
            obj.RLCRxFcn = [obj.RLCRxFcn; cell(1, obj.MaxLogicalChannels)];

            % Create Tx/Rx contexts
            obj.UplinkRxContext = [obj.UplinkRxContext; cell(1, obj.NumSymInFrame)];
            obj.DownlinkTxContext = [obj.DownlinkTxContext; cell(1, obj.NumSymInFrame)];
            obj.RxContextFeedback = [obj.RxContextFeedback; cell(1, obj.NumSymInFrame, obj.NumHARQ)];

            % Calculate unique CSI-RS transmission time and periodicity
            obj.CSIRSTxInfo = calculateCSIRSPeriodicity(obj, [obj.CSIRSConfiguration obj.CSIRSConfigurationRSRP]);

            % Calculate unique SRS reception time and periodicity
            obj.SRSRxInfo = calculateSRSPeriodicity(obj, obj.SRSConfiguration);
        end

        function dlControlRequest(obj, currentTime)
            %dlControlRequest Request from MAC to Phy to send non-data DL transmissions
            %   dlControlRequest(OBJ) sends a request to Phy for non-data downlink
            %   transmission scheduled for the current slot. MAC sends it at the
            %   start of a DL slot for all the scheduled DL transmissions in
            %   the slot (except PDSCH, which is sent using dataTx
            %   function of this class).

            % Check if current slot is a slot with DL symbols. For FDD (Value 0),
            % there is no need to check as every slot is a DL slot. For
            % TDD (Value 1), check if current slot has any DL symbols
            maxNumCSIRS = length(obj.CSIRSConfigurationRSRP) + length(obj.CSIRSConfiguration);
            dlControlType = zeros(1, maxNumCSIRS);
            dlControlPDUs = cell(1, maxNumCSIRS);
            scheduler = obj.Scheduler;
            numDLControlPDU = 0; % Variable to hold the number of DL control PDUs
            % Set carrier configuration object
            carrier = obj.CarrierConfigDL;
            carrier.NSlot = obj.CurrSlot;
            carrier.NFrame = obj.SFN;
            if ~isempty(obj.CSIRSConfigurationRSRP) % CSI-RS resource set for downlink beam refinement
                if(scheduler.DuplexMode == 0 || ~isempty(find(scheduler.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, :) == obj.DLType, 1)))
                    % Determine the SSB directions currently in use for all the UEs
                    activeSSBs = unique(scheduler.SSBIdx);
                    for ssbIdx = 1:length(activeSSBs)
                        csirsLocations = obj.CSIRSConfigurationRSRP{activeSSBs(ssbIdx)}.SymbolLocations; % CSI-RS symbol locations
                        if scheduler.DuplexMode == 0 || all(scheduler.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, cell2mat(csirsLocations)+1) == obj.DLType)
                            csirsIndRSRP = nrCSIRSIndices(carrier, obj.CSIRSConfigurationRSRP{activeSSBs(ssbIdx)});

                            if ~isempty(csirsIndRSRP)
                                numDLControlPDU = numDLControlPDU + 1;
                                dlControlType(numDLControlPDU) = 0; % CSIRS PDU
                                numCSIRS = length(obj.CSIRSConfigurationRSRP{1}.RowNumber);
                                dlControlPDUs{numDLControlPDU} = {obj.CSIRSConfigurationRSRP{activeSSBs(ssbIdx)}, (activeSSBs(ssbIdx)-1)*numCSIRS + (1:numCSIRS)};
                            end
                        end
                    end
                end
            end
            csirsConfigLen = length(obj.CSIRSConfiguration);
            % To account for consecutive symbols in CDM pattern
            additionalCSIRSSyms = [0 0 0 0 1 0 1 1 0 1 1 1 1 1 3 1 1 3];
            for csirsIdx = 1:csirsConfigLen % CSI-RS for downlink channel measurement
                csirsSymbolRange(1) = min(obj.CSIRSConfiguration{csirsIdx}.SymbolLocations); % First CSI-RS symbol
                csirsSymbolRange(2) = max(obj.CSIRSConfiguration{csirsIdx}.SymbolLocations) + ... % Last CSI-RS symbol
                    additionalCSIRSSyms(obj.CSIRSConfiguration{csirsIdx}.RowNumber);
                % Check whether the mode is FDD OR if it is TDD then all the CSI-SRS symbols must be DL symbols
                if scheduler.DuplexMode == 0 || all(scheduler.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, csirsSymbolRange+1) == obj.DLType)
                    csirsInd = nrCSIRSIndices(carrier, obj.CSIRSConfiguration{csirsIdx});
                    if ~isempty(csirsInd) % Empty value means CSI-RS is not scheduled in the current slot
                        numDLControlPDU = numDLControlPDU + 1;
                        dlControlType(numDLControlPDU) = 0; % CSIRS PDU
                        if ~isempty(scheduler.CSIMeasurementDL(csirsIdx).CSIResourceIndicator)
                            numCSIRSBeams = length(obj.CSIRSConfigurationRSRP{1}.RowNumber);
                            beamIdx = (scheduler.SSBIdx(csirsIdx)-1)*numCSIRSBeams + scheduler.CSIMeasurementDL(csirsIdx).CSIResourceIndicator;
                        else
                            beamIdx = [];
                        end
                        dlControlPDUs{numDLControlPDU} = {obj.CSIRSConfiguration{csirsIdx}, beamIdx};
                    end
                end
            end
            obj.TimingInfo.Timestamp = currentTime;
            obj.DlControlRequestFcn(dlControlType(1:numDLControlPDU), dlControlPDUs(1:numDLControlPDU), obj.TimingInfo); % Send DL control request to Ph
        end

        function ulControlRequest(obj, currentTime)
            %ulControlRequest Request from MAC to Phy to receive non-data UL transmissions
            %   ulControlRequest(OBJ) sends a request to Phy for non-data
            %   uplink reception scheduled for the current slot. MAC
            %   sends it at the start of a UL slot for all the scheduled UL
            %   receptions in the slot (except PUSCH, which is received
            %   using dataRx function of this class).

            if ~isempty(obj.SRSConfiguration) % Check if SRS is enabled
                % Check if current slot is a slot with UL symbols. For FDD
                % (value 0), there is no need to check as every slot is a
                % UL slot. For TDD (value 1), check if current slot has any
                % UL symbols
                scheduler = obj.Scheduler;
                if scheduler.DuplexMode == 0 || ~isempty(find(scheduler.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, :) == obj.ULType, 1))
                    ulControlType = zeros(1, length(obj.UEs));
                    ulControlPDUs = cell(1, length(obj.UEs));
                    numSRSUEs = 0; % Initialize number of UEs from which SRS is expected in this slot
                    % Set carrier configuration object
                    carrier = obj.CarrierConfigUL;
                    carrier.NSlot = obj.CurrSlot;
                    carrier.NFrame = obj.SFN;
                    for rnti=1:length(obj.UEs) % Send SRS reception request to Phy for the UEs
                        srsConfigUE = obj.SRSConfiguration{rnti};
                        if ~isempty(srsConfigUE)
                            srsLocations = srsConfigUE.SymbolStart : (srsConfigUE.SymbolStart + srsConfigUE.NumSRSSymbols-1); % SRS symbol locations
                            % Check whether the mode is FDD OR if it is TDD then all the SRS symbols must be UL symbols
                            if scheduler.DuplexMode == 0 || all(scheduler.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, srsLocations+1) == obj.ULType)
                                srsInd = nrSRSIndices(carrier, srsConfigUE);
                                if ~isempty(srsInd) % Empty value means SRS is not scheduled to be received in the current slot for this UE
                                    numSRSUEs = numSRSUEs+1;
                                    ulControlType(numSRSUEs) = 1; % SRS PDU
                                    ulControlPDUs{numSRSUEs}{1} = rnti;
                                    ulControlPDUs{numSRSUEs}{2} = srsConfigUE;
                                end
                            end
                        end
                    end
                    ulControlType = ulControlType(1:numSRSUEs);
                    ulControlPDUs = ulControlPDUs(1:numSRSUEs);
                    obj.TimingInfo.Timestamp = currentTime;
                    obj.UlControlRequestFcn(ulControlType, ulControlPDUs, obj.TimingInfo); % Send UL control request to Phy
                end
            end
        end

        function pduLen = sendMACPDU(obj, rnti, downlinkGrant, currentTime)
            %sendMACPDU Sends MAC PDU to Phy as per the parameters of the downlink grant
            % Based on the NDI in the downlink grant, either new
            % transmission or retransmission would be indicated to Phy

            macPDU = [];
            % Populate PDSCH information to be sent to Phy, along with the MAC
            % PDU
            pdschInfo = obj.PDSCHInfo;
            frequencyAllocation = downlinkGrant.FrequencyAllocation;
            scheduler = obj.Scheduler;
            % Create downlink grant RBs based on resource allocation type (RAT)
            if downlinkGrant.ResourceAllocationType % RAT-1
                startRBIndex = frequencyAllocation(1);
                numResourceBlocks = frequencyAllocation(2);
                dlGrantRBs(1:numResourceBlocks) =  startRBIndex : (startRBIndex + numResourceBlocks -1); % Store RB indices of DL grant
            else % RAT-0
                dlGrantRBs = -1*ones(scheduler.NumResourceBlocks, 1); % Store RB indices of DL grant
                rbgSizeDL = scheduler.RBGSize;
                for rbgIndex = 0:(length(frequencyAllocation)-1) % Get RB indices of DL grant
                    if frequencyAllocation(rbgIndex+1) == 1
                        startRBInRBG = rbgSizeDL * rbgIndex;
                        % If the last RBG of BWP is assigned, then it might
                        % not have the same number of RBs as other RBG.
                        if rbgIndex == length(frequencyAllocation)-1
                            dlGrantRBs(startRBInRBG+1 : end) =  ...
                                startRBInRBG : scheduler.NumResourceBlocks-1;
                        else
                            dlGrantRBs(startRBInRBG+1 : (startRBInRBG + rbgSizeDL)) =  ...
                                startRBInRBG : (startRBInRBG + rbgSizeDL - 1) ;
                        end
                    end
                end
                dlGrantRBs = dlGrantRBs(dlGrantRBs >= 0);
            end
            pdschInfo.PDSCHConfig.PRBSet = dlGrantRBs;
            % Get the corresponding row from the mcs table
            mcsInfo = scheduler.MCSTableDL(downlinkGrant.MCS + 1, :);
            modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme(stored in column 1)
            pdschInfo.TargetCodeRate = mcsInfo(2)/1024; % Coderate (stored in column 2)
            % Modulation scheme and corresponding bits/symbol
            fullmodlist = ["pi/2-BPSK", "BPSK", "QPSK", "16QAM", "64QAM", "256QAM"]';
            qm = [1 1 2 4 6 8];
            modScheme = fullmodlist((modSchemeBits == qm)); % Get modulation scheme string
            pdschInfo.PDSCHConfig.Modulation = modScheme(1);
            pdschInfo.PDSCHConfig.SymbolAllocation = [downlinkGrant.StartSymbol downlinkGrant.NumSymbols];
            pdschInfo.PDSCHConfig.RNTI = rnti;
            pdschInfo.PDSCHConfig.NID = obj.NCellID;
            pdschInfo.NSlot = obj.CurrSlot;
            pdschInfo.HARQID = downlinkGrant.HARQID;
            pdschInfo.RV = downlinkGrant.RV;
            pdschInfo.PrecodingMatrix = downlinkGrant.PrecodingMatrix;
            pdschInfo.BeamIndex = downlinkGrant.BeamIndex;
            pdschInfo.MUMIMO = downlinkGrant.MUMIMO;
            pdschInfo.PDSCHConfig.MappingType = downlinkGrant.MappingType;
            pdschInfo.PDSCHConfig.NumLayers = downlinkGrant.NumLayers;
            if isequal(downlinkGrant.MappingType, 'A')
                dmrsAdditonalPos = scheduler.PDSCHDMRSAdditionalPosTypeA;
            else
                dmrsAdditonalPos = scheduler.PDSCHDMRSAdditionalPosTypeB;
            end
            pdschInfo.PDSCHConfig.DMRS.DMRSLength =  downlinkGrant.DMRSLength;
            pdschInfo.PDSCHConfig.DMRS.DMRSAdditionalPosition = dmrsAdditonalPos;
            pdschInfo.PDSCHConfig.DMRS.NumCDMGroupsWithoutData =  downlinkGrant.NumCDMGroupsWithoutData;

            % Carrier configuration
            carrierConfig = obj.CarrierConfigDL;
            carrierConfig.NFrame = obj.SFN;
            carrierConfig.NSlot = pdschInfo.NSlot;

            downlinkGrantHarqIndex = downlinkGrant.HARQID;
            if strcmp(downlinkGrant.Type, 'newTx')
                [~, pdschIndicesInfo] = nrPDSCHIndices(carrierConfig, pdschInfo.PDSCHConfig); % Calculate PDSCH indices
                tbs = nrTBS(pdschInfo.PDSCHConfig.Modulation, pdschInfo.PDSCHConfig.NumLayers, length(dlGrantRBs), ...
                    pdschIndicesInfo.NREPerPRB, pdschInfo.TargetCodeRate, scheduler.XOverheadPDSCH); % Calculate the transport block size
                pduLen = floor(tbs/8); % In bytes
                % Generate MAC PDU
                macPDU = constructMACPDU(obj, pduLen, rnti);
            else
                pduLen = scheduler.TBSizeDL(rnti, downlinkGrantHarqIndex+1);
            end

            pdschInfo.TBS = pduLen;
            % Set reserved REs information. Generate 0-based
            % carrier-oriented CSI-RS indices in linear indexed form
            for csirsIdx = 1:length(obj.CSIRSConfiguration)
                csirsLocations = obj.CSIRSConfiguration{csirsIdx}.SymbolLocations; % CSI-RS symbol locations
                if scheduler.DuplexMode == 0 || all(scheduler.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, csirsLocations+1) == obj.DLType)
                    % (Mode is FDD) or (Mode is TDD and CSI-RS symbols are DL symbols)
                    pdschInfo.PDSCHConfig.ReservedRE = [pdschInfo.PDSCHConfig.ReservedRE; nrCSIRSIndices(carrierConfig, obj.CSIRSConfiguration{csirsIdx}, 'IndexBase', '0based')]; % Reserve CSI-RS REs
                end
            end
            for idx = 1:length(obj.CSIRSConfigurationRSRP)
                csirsLocations = obj.CSIRSConfigurationRSRP{idx}.SymbolLocations; % CSI-RS symbol locations
                if scheduler.DuplexMode == 0 || all(scheduler.DLULSlotFormat(obj.CurrDLULSlotIndex + 1, cell2mat(csirsLocations) + 1) == obj.DLType)
                    % (Mode is FDD) or (Mode is TDD and CSI-RS symbols are DL symbols)
                    pdschInfo.PDSCHConfig.ReservedRE = [pdschInfo.PDSCHConfig.ReservedRE; nrCSIRSIndices(carrierConfig, obj.CSIRSConfigurationRSRP{idx}, 'IndexBase', '0based')]; % Reserve CSI-RS REs
                end
            end

            obj.TimingInfo.Timestamp = currentTime;
            obj.TxDataRequestFcn(pdschInfo, macPDU, obj.TimingInfo);
        end

        function rxRequestToPhy(obj, rnti, uplinkGrant, currentTime)
            %rxRequestToPhy Send Rx request to Phy

            puschInfo = obj.PUSCHInfo; % Information to be passed to Phy for PUSCH reception
            frequencyAllocation = uplinkGrant.FrequencyAllocation;
            scheduler = obj.Scheduler;
            numPUSCHRBs = scheduler.NumResourceBlocks;
            % Create uplink grant RBs based on the resource allocation type
            if uplinkGrant.ResourceAllocationType % RAT-1
                startRBIndex = frequencyAllocation(1);
                numResourceBlocks = frequencyAllocation(2);
                ulGrantRBs(1:numResourceBlocks) =  startRBIndex : (startRBIndex + numResourceBlocks -1); % Store RB indices of UL grant
            else % RAT-0
                ulGrantRBs = -1*ones(numPUSCHRBs, 1); % Store RB indices of UL grant
                rbgSizeUL = scheduler.RBGSize;
                for rbgIndex = 0:(length(frequencyAllocation)-1) % For all RBGs
                    if frequencyAllocation(rbgIndex+1) % If RBG is set in bitmap
                        startRBInRBG = rbgSizeUL*rbgIndex;
                        % If the last RBG of BWP is assigned, then it might
                        % not have the same number of RBs as other RBG
                        if rbgIndex == (length(frequencyAllocation)-1)
                            ulGrantRBs(startRBInRBG + 1 : end) =  ...
                                startRBInRBG : numPUSCHRBs-1 ;
                        else
                            ulGrantRBs((startRBInRBG + 1) : (startRBInRBG + rbgSizeUL)) =  ...
                                startRBInRBG : (startRBInRBG + rbgSizeUL -1);
                        end
                    end
                end
                ulGrantRBs = ulGrantRBs(ulGrantRBs >= 0);
            end
            puschInfo.PUSCHConfig.PRBSet = ulGrantRBs;
            % Get the corresponding row from the mcs table
            mcsInfo = scheduler.MCSTableUL(uplinkGrant.MCS + 1, :);
            modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme (stored in column 1)
            puschInfo.TargetCodeRate = mcsInfo(2)/1024; % Coderate (stored in column 2)
            % Modulation scheme and corresponding bits/symbol
            fullmodlist = ["pi/2-BPSK", "BPSK", "QPSK", "16QAM", "64QAM", "256QAM"]';
            qm = [1 1 2 4 6 8];
            modScheme = fullmodlist(modSchemeBits == qm); % Get modulation scheme string
            puschInfo.PUSCHConfig.Modulation = modScheme(1);
            puschInfo.PUSCHConfig.RNTI = rnti;
            puschInfo.PUSCHConfig.NID = obj.NCellID;
            puschInfo.NSlot = obj.CurrSlot;
            puschInfo.HARQID = uplinkGrant.HARQID;
            puschInfo.RV = uplinkGrant.RV;
            puschInfo.PUSCHConfig.SymbolAllocation = [uplinkGrant.StartSymbol uplinkGrant.NumSymbols];
            puschInfo.PUSCHConfig.MappingType = uplinkGrant.MappingType;
            puschInfo.PUSCHConfig.NumLayers = uplinkGrant.NumLayers;
            puschInfo.PUSCHConfig.TransmissionScheme = 'codebook';
            puschInfo.PUSCHConfig.NumAntennaPorts = uplinkGrant.NumAntennaPorts;
            puschInfo.PUSCHConfig.TPMI = uplinkGrant.TPMI;
            if isequal(uplinkGrant.MappingType, 'A')
                dmrsAdditonalPos = scheduler.PUSCHDMRSAdditionalPosTypeA;
            else
                dmrsAdditonalPos = scheduler.PUSCHDMRSAdditionalPosTypeB;
            end
            puschInfo.PUSCHConfig.DMRS.DMRSLength = uplinkGrant.DMRSLength;
            puschInfo.PUSCHConfig.DMRS.DMRSAdditionalPosition = dmrsAdditonalPos;
            puschInfo.PUSCHConfig.DMRS.NumCDMGroupsWithoutData = uplinkGrant.NumCDMGroupsWithoutData;

            % Carrier configuration
            carrierConfig = obj.CarrierConfigUL;
            carrierConfig.NSlot = puschInfo.NSlot;

            if strcmp(uplinkGrant.Type, 'newTx') % New transmission
                % Calculate TBS
                [~, puschIndicesInfo] = nrPUSCHIndices(carrierConfig, puschInfo.PUSCHConfig);
                tbs = nrTBS(puschInfo.PUSCHConfig.Modulation, puschInfo.PUSCHConfig.NumLayers, length(ulGrantRBs), ...
                    puschIndicesInfo.NREPerPRB, puschInfo.TargetCodeRate);
                puschInfo.TBS = floor(tbs/8); % TBS in bytes
                puschInfo.NewData = 1;
            else % Retransmission
                % Use TBS of the original transmission
                puschInfo.TBS = scheduler.TBSizeUL(rnti, uplinkGrant.HARQID+1);
                puschInfo.NewData = 0;
            end

            obj.TimingInfo.Timestamp = currentTime;
            % Call Phy to start receiving PUSCH
            obj.RxDataRequestFcn(puschInfo, obj.TimingInfo);
        end

        function nextInvokeTime = getNextInvokeTime(obj, currentTime)
            %getNextInvokeTime Return the next invoke time in nanoseconds

            % Find the duration completed in the current symbol
            durationCompletedInCurrSlot = mod(currentTime, obj.SlotDurationInNS);
            currSymDurCompleted = obj.SymbolDurationsInSlot(obj.CurrSymbol+1) - obj.SymbolEndTimesInSlot(obj.CurrSymbol+1) + durationCompletedInCurrSlot;

            totalSymbols = obj.NumSymInFrame;
            symbolNumFrame = obj.CurrSlot*obj.NumSymbols + obj.CurrSymbol;
            % Next Tx start symbol
            nextTxStartSymbol = Inf;
            if ~isempty(obj.DownlinkTxContext)
                nextTxStartSymbol = find(~cellfun('isempty',obj.DownlinkTxContext(:, symbolNumFrame+2:totalSymbols)), 1);
                nextTxStartSymbol = ceil(nextTxStartSymbol/numel(obj.UEs));
                if isempty(nextTxStartSymbol)
                    nextTxStartSymbol = find(~cellfun('isempty',obj.DownlinkTxContext(:, 1:symbolNumFrame)), 1);
                    nextTxStartSymbol = (totalSymbols-symbolNumFrame-1) + ceil(nextTxStartSymbol/numel(obj.UEs));
                end
            end

            % Next Rx start symbol
            nextRxStartSymbol = Inf;
            if ~isempty(obj.UplinkRxContext)
                nextRxStartSymbol = find(~cellfun('isempty',obj.UplinkRxContext(:, symbolNumFrame+2:totalSymbols)), 1);
                nextRxStartSymbol = ceil(nextRxStartSymbol/numel(obj.UEs));
                if isempty(nextRxStartSymbol)
                    nextRxStartSymbol = find(~cellfun('isempty',obj.UplinkRxContext(:, 1:symbolNumFrame)), 1);
                    nextRxStartSymbol = (totalSymbols-symbolNumFrame-1) + ceil(nextRxStartSymbol/numel(obj.UEs));
                end
            end

            nextInvokeSymbol = min([nextTxStartSymbol nextRxStartSymbol Inf]);
            nextInvokeTime = Inf;
            if nextInvokeSymbol ~= Inf
                numSlots = floor(nextInvokeSymbol/obj.NumSymbols);
                numSymbols = mod(nextInvokeSymbol,obj.NumSymbols);
                if obj.CurrSymbol + numSymbols > obj.NumSymbols
                    totalSymbolsDuration = sum(obj.SymbolDurationsInSlot(obj.CurrSymbol+1:obj.NumSymbols)) + sum(obj.SymbolDurationsInSlot(1:obj.CurrSymbol+numSymbols-obj.NumSymbols));
                else
                    totalSymbolsDuration = sum(obj.SymbolDurationsInSlot(obj.CurrSymbol+1:obj.CurrSymbol+numSymbols));
                end
                nextInvokeTime = currentTime + (numSlots * obj.SlotDurationInNS) + totalSymbolsDuration - currSymDurCompleted;
            end

            % Next control transmission time
            controlTxStartTime = min(obj.CSIRSTxInfo(:, 2));
            % Next control reception time
            %controlRxStartTime = min(obj.SRSRxInfo(:, 2)); %%CHECK HERE; THIS MAKES THE NIT STUCK AT 10^-3
            controlRxStartTime = min(obj.CSIRSTxInfo(:, 2)); %% made the rx time and tx time same
            nextInvokeTime = min([obj.SchedulerNextInvokeTime nextInvokeTime controlTxStartTime controlRxStartTime]); %%CHECK HERE. IF YOU MANUALLY MAKE DELAY THE OTHER NEXTINVOKE TIMES MIGHT BE ACCORDING TO OLD VALUES AND THEY CAN BE CHOOSEN AS NEXT INVOKE TIMES
        end
    end
end