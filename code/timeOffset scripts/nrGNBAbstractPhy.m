classdef nrGNBAbstractPhy < nr5g.internal.nrPhyInterface
    %nrGNBAbstractPhy Implements abstract physical (PHY) layer for gNB.
    %   The class implements an abstract PHY at gNB. It also implements the
    %   interfaces for information exchange between PHY and higher layers.
    %
    %   Note: This is an internal undocumented class and its API and/or
    %   functionality may change in subsequent releases.
    %
    %   nrGNBAbstractPhy methods:
    %       nrGNBAbstractPhy        - Construct an abstract gNB PHY object
    %       run                     - Run the gNB PHY layer operations
    %       registerMACInterfaceFcn - Register MAC interface functions at
    %                                 PHY, for sending information to MAC
    %       txDataRequest           - PDSCH transmission request from MAC to PHY
    %       dlControlRequest        - Downlink control (non-data) transmission
    %                                 request from MAC to PHY
    %       ulControlRequest        - Uplink control (non-data) reception
    %                                 request from MAC to PHY
    %       rxDataRequest           - PUSCH reception request from MAC to PHY

    %   Copyright 2022-2023 The MathWorks, Inc.

    properties (SetAccess = private, Hidden)
        %CSIRSInfo CSI-RS information PDU sent by MAC for the current slot
        % It is an array of nrCSIRSConfig object containing the
        % configuration of CSI-RS to be sent in current slot. If empty,
        % then CSI-RS is not scheduled for the current slot
        CSIRSInfo = {}

        %SRSInfo SRS information PDUs sent by MAC for the reception of SRS
        % in the current slot. It is an array of objects of type nrSRSConfig.
        % Each element corresponds to an SRS configuration which is used to
        % receive the SRS. If empty, then no SRS is scheduled to be received
        % in the current slot
        SRSInfo = {}

        %PDSCHInfo PDSCH information sent by MAC for the current slot
        % It is an array of structures of PDSCHInfo, where each structure
        % index 'i' contains the information required by PHY to transmit a
        % MAC PDU stored at index 'i' of object property 'MacPDU'
        PDSCHInfo = {}

        %MacPDU PDUs sent by MAC which are scheduled to be sent in the current slot
        % It is an array of downlink MAC PDUs to be sent in the current
        % slot. Each object in the array corresponds to a structure in
        % the property PDSCHInfo
        MacPDU = {}

        %UEInfo Information about the UEs connected to the gNB
        % N-by-1 array where 'N' is the number of UEs. Each element in the
        % array is a structure with three fields.
        %   ID      - Node ID of the UE
        %   Name    - Node name of the UE
        %   RNTI    - RNTI of the connected UE
        UEInfo

        %SRSIndicationFcn Function handle to send the measured UL channel quality to MAC
        SRSIndicationFcn

        %HARQBuffers Buffers to store downlink HARQ transport blocks
        % N-by-NumHARQProcesses cell array to buffer transport blocks for the HARQ
        % processes, where 'N' is the number of UEs. The physical layer
        % stores the transport blocks for retransmissions
        HARQBuffers

        %RxBuffer Rx buffer to store received UL packets
        % N-by-P cell array where 'N' is number of symbols in a 10 ms frame
        % and 'P' is number of UEs served by cell. An element at index (i,
        % j) buffers the packet received from UE with RNTI 'j' and whose
        % reception starts at symbol index 'i' in the frame. Packet is read
        % from here in the symbol after the last symbol in the PUSCH
        % duration
        RxBuffer

        %RankIndicator UL Rank to calculate precoding matrix and CQI
        % Vector of length 'N' where N is number of UEs. Value at index 'i'
        % contains UL rank of UE with RNTI 'i'
        RankIndicator

        %L2SMs Link to System Mapping
        % It is an array of objects of length 'N' where N is the number of
        % UEs in the cell
        L2SMs

        %L2SMsSRS L2SMs for holding context of SRS resources
        % It is an array of objects of length 'N' where N is the number of
        % UEs in the cell.
        L2SMsSRS

        %L2SMIntf L2SM for holding context of interfering resources
        L2SMIntf

        %CarrierConfig Carrier Configuration
        % CarrierConfig is an object of type nrCarrierConfig
        CarrierConfig

        %MACPDUInfo PDU information sent to MAC
        % It is a structure with the following fields:
        %   RNTI    - RNTI of the connected UE
        %   TBS     - Transport block size
        %   MACPDU  - PDU sent to the MAC
        %   CRCFlag - Status of the CRC check
        %   HARQID  - HARQ ID of the transmission
        MACPDUInfo

        %CurrTimeInfo Current timing information
        CurrTimeInfo %%   CHECK THIS TERM

        %PHYStatsInfo PHY statistics for all UEs
        PHYStatsInfo

        %SINR Effective SINR of the received packet
        SINR
    end

    properties (SetAccess = private)
        %NumTransmitAntennas Number of transmit antennas
        NumTransmitAntennas

        %NumReceiveAntennas Number of receive antennas
        NumReceiveAntennas

        %TransmitPower Tx power in dBm
        TransmitPower

        %ReceiveGain Rx antenna gain in dBi
        ReceiveGain

        %NoiseFigure Noise figure at the receiver
        NoiseFigure
    end

    properties(Hidden)
        %CQITableValues CQI table corresponding to table name
        CQITableValues
    end

    methods
        function obj = nrGNBAbstractPhy(param)
            %nrGNBAbstractPhy Construct an abstract gNB PHY object
            %   OBJ = nrGNBAbstractPhy(param) constructs a gNB PHY object.
            %
            %   PARAM is a structure with the fields:
            %       NCellID             - Cell ID
            %       DuplexMode          - "FDD" or "TDD"
            %       ChannelBandwidth    - DL or UL channel bandwidth in Hz
            %       DLCarrierFrequency  - DL Carrier frequency in Hz
            %       ULCarrierFrequency  - UL Carrier frequency in Hz
            %       NumResourceBlocks   - Number of resource blocks
            %       SubCarrierSpacing   - Subcarrier spacing
            %       TransmitPower       - Tx power in dBm
            %       NumTransmitAntennas - Number of GNB Tx antennas
            %       NumReceiveAntennas  - Number of GNB Rx antennas
            %       NoiseFigure         - Noise figure
            %       ReceiveGain         - Receiver antenna gain at gNB
            %                             in dBi
            %       CQITable            - Name of the CQI table to be used

            % Set carrier configuration on PHY layer instance
            carrierInformation = struct('SubcarrierSpacing', param.SubcarrierSpacing,'NRBsDL', param.NumResourceBlocks, ...
                'NRBsUL', param.NumResourceBlocks,'DLBandwidth', param.ChannelBandwidth,'ULBandwidth', param.ChannelBandwidth, ...
                'ULFreq', param.ULCarrierFrequency, 'DLFreq', param.DLCarrierFrequency, 'NCellID', param.NCellID, ...
                'DuplexMode', strcmp(param.DuplexMode, "TDD"));
            setCarrierInformation(obj, carrierInformation);

            inputParam = {'TransmitPower', 'NumTransmitAntennas', 'NumReceiveAntennas', 'NoiseFigure', 'ReceiveGain'};
            for idx=1:numel(inputParam)
                obj.(char(inputParam{idx})) = param.(inputParam{idx});
            end
            if isfield(param, 'CQITable')
                cqiTableValues = nr5g.internal.nrCQITables(param.CQITable);
                obj.CQITableValues = cqiTableValues(:, 2:3); % Keep 2 columns: modulation and coderate
            end

            % NR Packet param
            obj.PacketStruct.Type = 2; % 5G packet
            obj.PacketStruct.Abstraction = true; % Abstracted PHY
            obj.PacketStruct.Metadata = struct('NCellID', obj.CarrierInformation.NCellID, 'RNTI', [], ...
                'PrecodingMatrix', [], 'NumSamples', [], 'Channel', obj.PacketStruct.Metadata.Channel);
            obj.PacketStruct.Metadata.Channel.PathGains = 1;
            obj.PacketStruct.Metadata.Channel.PathFilters = 1;
            obj.PacketStruct.Metadata.Channel.SampleTimes = 0;
            obj.PacketStruct.CenterFrequency = carrierInformation.DLFreq;
            obj.PacketStruct.Bandwidth = carrierInformation.DLBandwidth;
            obj.PacketStruct.DirectToDestination = 0;
            obj.PacketStruct.NumTransmitAntennas = obj.NumTransmitAntennas;

            % Carrier Configuration
            obj.CarrierConfig = nrCarrierConfig;
            obj.CarrierConfig.SubcarrierSpacing = param.SubcarrierSpacing;
            obj.CarrierConfig.NSizeGrid = param.NumResourceBlocks;
            obj.CarrierConfig.NCellID = param.NCellID;

            % Initialize currTimingInfo
            obj.CurrTimeInfo = struct('AFN', 0, 'CurrSlot', 0, 'CurrSymbol', 0);

            % Initialize MACPDUInfo
            obj.MACPDUInfo=struct('RNTI', 0, 'TBS', 0, 'MACPDU', [], 'CRCFlag', 1, 'HARQID', 0);

            % Initialize interference buffer
            obj.RxBuffer = wirelessnetwork.internal.interferenceBuffer(CenterFrequency=obj.CarrierInformation.ULFreq, Bandwidth=obj.CarrierInformation.ULBandwidth);

            % Initialize L2SM for holding interference context
            obj.L2SMIntf = nr5g.internal.L2SM.initialize(obj.CarrierConfig);
        end

        function addConnection(obj, connectionConfig)
            %addConnection Configures the GNB PHY with UE connection information
            %
            %   connectionConfig is a structure including the following fields:
            %       RNTI      - RNTI of the UE.
            %       UEID      - Node ID of the UE
            %       UEName    - Node name of the UE
            %       NumHARQ   - Number of HARQ processes for the UE

            nodeInfo = struct('ID', connectionConfig.UEID, 'Name', connectionConfig.UEName, 'RNTI', connectionConfig.RNTI);
            obj.UEInfo = [obj.UEInfo; nodeInfo];

            phyStatsInfo = struct('UEID', connectionConfig.UEID, 'UEName', connectionConfig.UEName, ...
                'RNTI', connectionConfig.RNTI,'TransmittedPackets', 0, ...
                'ReceivedPackets', 0, 'DecodeFailures', 0);
            obj.PHYStatsInfo = [obj.PHYStatsInfo; phyStatsInfo];

            obj.HARQBuffers = [obj.HARQBuffers; cell(1,connectionConfig.NumHARQ)]; % Append HARQ buffers for the UE
            obj.StatTransmittedPackets = [obj.StatTransmittedPackets; 0];
            obj.StatReceivedPackets = [obj.StatReceivedPackets; 0];
            obj.StatDecodeFailures = [obj.StatDecodeFailures; 0];

            % Initialize Rx buffer
            symbolsPerFrame = obj.CarrierInformation.SlotsPerSubframe*10*14;

            % Initialize SRS info buffer to buffer SRS Rx request from MAC
            obj.SRSInfo = [obj.SRSInfo cell(symbolsPerFrame, 1)];

            % UL rank indicator
            obj.RankIndicator = [obj.RankIndicator 1];

            % Initialize L2SMs
            obj.L2SMs = [obj.L2SMs; nr5g.internal.L2SM.initialize(obj.CarrierConfig, connectionConfig.NumHARQ, 1)];
            obj.L2SMsSRS = [obj.L2SMsSRS; nr5g.internal.L2SM.initialize(obj.CarrierConfig)];
        end

        function nextInvokeTime = run(obj, currentTime, packets) %%CHECK HERE: OFFSET HERE?
            %run Run the gNB PHY layer operations and return the next invoke time (in nanoseconds)
            %   NEXTINVOKETIME = run(OBJ, CURRENTTIME, PACKETS)
            %   runs the PHY layer operations and returns the next invoke
            %   time (in nanoseconds).
            %
            %   NEXTINVOKETIME is the next invoke time (in nanoseconds) for
            %   PHY.
            %
            %   CURRENTTIME is the current time (in nanoseconds).
            %
            %   PACKETS are the received packets from other nodes.

            symEndTimes = obj.CarrierInformation.SymbolTimings;
            slotDuration = obj.CarrierInformation.SlotDuration; % In nanoseconds

            % Find the duration completed in the current slot
            durationCompletedInCurrSlot = mod(currentTime, slotDuration);

            % Find the current AFN, slot and symbol
            currTimingInfo = obj.CurrTimeInfo;
            currTimingInfo.AFN = floor(currentTime/obj.FrameDurationInNS);
            currTimingInfo.CurrSlot = mod(floor(currentTime/slotDuration), obj.CarrierInformation.SlotsPerFrame);
            currTimingInfo.CurrSymbol = find(durationCompletedInCurrSlot < symEndTimes, 1) - 1;

            % PHY transmission.
            % It is assumed that MAC has already loaded the PHY Tx
            % context for anything scheduled to be transmitted at the
            % current time
            phyTx(obj, currentTime, currTimingInfo);

            % Store the received packets
            storeReception(obj, packets);

            % Receive PUSCH and send the corresponding PDU to MAC.
            % Reception is done at the end of the last symbol in
            % PUSCH duration (till then the packets are queued in Rx buffer).
            % PHY calculates the last symbol of PUSCH duration based on
            % 'rxDataRequest' call from MAC (which comes at the first
            % symbol of PUSCH Rx time) and the PUSCH duration
            phyRx(obj, currTimingInfo);

            % Get the next invoke time for PHY
            nextInvokeTime = getNextInvokeTime(obj, currentTime);
            % Update the last run time
            obj.LastRunTime = currentTime;
        end

        function registerMACInterfaceFcn(obj, sendMACPDUFcn, sendULChannelQualityFcn)
            %registerMACInterfaceFcn Register MAC interface functions at PHY,
            %   for sending information to MAC
            %
            %   Refer to the base class (nrPhyInterface.m) for the callback
            %   function signature.

            obj.RxIndicationFcn = sendMACPDUFcn;
            obj.SRSIndicationFcn = sendULChannelQualityFcn;
        end

        function txDataRequest(obj, pdschInfo, macPDU, timingInfo)
            %txDataRequest Tx request from MAC to PHY for starting PDSCH transmission
            %   txDataRequest(OBJ, PDSCHINFO, MACPDU, TIMINGINFO) sets the Tx context to
            %   indicate PDSCH transmission in the current symbol
            %
            %   PDSCHInfo is a structure which is sent by MAC and contains
            %   the information required by the PHY for the PDSCH
            %   transmission. The following PDSCHInfo properties are defined,
            %       NSlot           - Slot number of the PDSCH transmission
            %       HARQID          - HARQ process ID
            %       NewData         - Defines if it is a new (value 1) or
            %                         re-transmission (value 0)
            %       RV              - Redundancy version of the transmission
            %       TargetCodeRate  - Target code rate
            %       TBS             - Transport block size in bytes
            %       PrecodingMatrix - Precoding matrix
            %       BeamIndex       - Column index in the beam weights table configured at PHY
            %       PDSCHConfig     - PDSCH configuration object as described in
            %                         <a href="matlab:help('nrPDSCHConfig')">nrPDSCHConfig</a>
            %
            %   MACPDU is the downlink MAC PDU sent by MAC for transmission.
            %
            %   TIMINGINFO is a structure that contains the following
            %   fields.
            %       SFN        - System frame number
            %       Slot       - Slot number in a 10 millisecond frame
            %       Symbol     - Symbol number in the current slot
            %       Timestamp  - Transmission start timestamp in nanoseconds.

            symbolNumFrame = pdschInfo.NSlot * 14 + pdschInfo.PDSCHConfig.SymbolAllocation(1);
            % Find the time at which the MAC PDU will be transmitted and
            % keep the timestamp in PDSCH context
            if (obj.PhyTxProcessingDelay == 0)
                obj.DataTxTime(symbolNumFrame+1) = timingInfo.Timestamp; %% SHOULD WE USE HERE?
            else
                symDur = obj.CarrierInformation.SymbolDurations; % In nanoseconds
                phyProcessingStart = currTimingInfo.CurrSymbol;
                phyProcessingEnd = currTimingInfo.CurrSymbol + obj.PhyTxProcessingDelay - 1;
                phyProcessingSyms = (phyProcessingStart:phyProcessingEnd) + 1;
                obj.DataTxTime(symbolNumFrame+1) = timingInfo.Timestamp + sum(symDur(phyProcessingSyms));
            end

            % Update the Tx context. There can be multiple simultaneous
            % PDSCH transmissions for different UEs
            obj.MacPDU{end+1} = macPDU;
            obj.PDSCHInfo{end+1} = pdschInfo;
        end

        function rxDataRequest(obj, puschInfo, timingInfo)
            %rxDataRequest Rx request from MAC to PHY for starting PUSCH reception
            %   rxDataRequest(OBJ, PUSCHINFO, TIMINGINFO) is a request to
            %   start PUSCH reception. It starts a timer for PUSCH end time
            %   (which on firing receives the PUSCH). The PHY expects the
            %   MAC to send this request at the start of reception time.
            %
            %   PUSCHInfo is a structure which is sent by MAC and contains
            %   the information required by the PHY for the PUSCH
            %   reception. The following PUSCHInfo properties are defined,
            %       NSlot           - Slot number of the PUSCH transmission
            %       HARQID          - HARQ process ID
            %       NewData         - Defines if it is a new (Value 1) or
            %                         re-transmission (Value 0)
            %       RV              - Redundancy version of the transmission
            %       TargetCodeRate  - Target code rate
            %       TBS             - Transport block size in bytes
            %       PUSCHConfig     - PUSCH configuration object as described in
            %                        <a href="matlab:help('nrPUSCHConfig')">nrPUSCHConfig</a>
            %
            %   TIMINGINFO is a structure that contains the following
            %   fields.
            %       SFN        - System frame number
            %       Slot       - Current slot number in a 10 millisecond frame
            %       Symbol     - Current symbol number in the current slot
            %       Timestamp  - Reception start timestamp in nanoseconds

            puschStartSym = puschInfo.PUSCHConfig.SymbolAllocation(1);
            symbolNumFrame = puschInfo.NSlot*14 + puschStartSym; % PUSCH Rx start symbol number w.r.t start of 10 ms frame

            % PUSCH to be read at the end of last symbol in PUSCH reception
            numPUSCHSym =  puschInfo.PUSCHConfig.SymbolAllocation(2);
            puschRxSymbolFrame = mod(symbolNumFrame + numPUSCHSym - 1, obj.CarrierInformation.SymbolsPerFrame);

            symDur = obj.CarrierInformation.SymbolDurations; % In nanoseconds
            startSymbolIdx = puschStartSym + 1;
            endSymbolIdx = puschStartSym + numPUSCHSym;

            % Add the PUSCH Rx information at the index corresponding to
            % the symbol where PUSCH Rx ends
            obj.DataRxContext{puschRxSymbolFrame + 1}{end+1} = puschInfo;
            % Store data reception time (in nanoseconds) information
            obj.DataRxTime(puschRxSymbolFrame + 1) = timingInfo.Timestamp + ...
                sum(symDur(startSymbolIdx:endSymbolIdx));
        end

        function dlControlRequest(obj, pduType, dlControlPDU, ~)
            %dlControlRequest Downlink control (non-data) transmission
            %   request from MAC to PHY
            %   dlControlRequest(OBJ, PDUTYPE, DLCONTROLPDU) is a request from
            %   MAC for downlink transmission. MAC sends it at the start of
            %   a DL slot for all the scheduled non-data DL transmission in
            %   the slot (Data i.e. PDSCH is sent by MAC using
            %   txDataRequest interface of this class).
            %
            %   PDUTYPE is an array of packet types. Currently, only packet
            %   type 0 (CSI-RS) is supported.
            %
            %   DLCONTROLPDU is an array of DL control information PDUs. Each PDU
            %   is stored at the index corresponding to its type in
            %   PDUTYPE. Currently supported CSI-RS information PDU is an object of
            %   type nrCSIRSConfig.

            % Update the Tx context
            obj.CSIRSInfo = cell(1, length(dlControlPDU));
            numCSIRS = 0; % Counter containing the number of CSI-RS PDUs
            for i = 1:length(pduType)
                switch pduType(i)
                    case obj.CSIRSPDUType
                        numCSIRS = numCSIRS + 1;
                        obj.CSIRSInfo{numCSIRS} = dlControlPDU{i};
                end
            end
            obj.CSIRSInfo = obj.CSIRSInfo(1:numCSIRS);
        end

        function ulControlRequest(obj, pduType, ulControlPDU, timingInfo)
            %ulControlRequest Uplink control (non-data) reception request
            %from MAC to PHY
            %   ulControlRequest(OBJ, PDUTYPE, ULCONTROLPDU, TIMINGINFO)
            %   is a request from MAC for uplink reception. MAC sends it at
            %   the start of a UL slot for all the scheduled non-data UL
            %   receptions in the slot (Data i.e. PUSCH rx request is sent
            %   by MAC using rxDataRequest interface of this class).
            %
            %   PDUTYPE is an array of packet types. Currently, only packet
            %   type 1 (SRS) is supported.
            %
            %   ULCONTROLPDU is an array of UL control information PDUs. Each PDU
            %   is stored at the index corresponding to its type in
            %   PDUTYPE. Currently supported SRS information PDU is an object of
            %   type nrSRSConfig.
            %
            %   TIMINGINFO is a structure that contains the following
            %   fields.
            %       SFN        - System frame number
            %       Slot       - Current slot number in a 10 millisecond frame
            %       Symbol     - Current symbol number in the current slot
            %       Timestamp  - Reception start timestamp in nanoseconds

            % Update the Rx context
            for i = 1:length(pduType)
                switch pduType(i)
                    case obj.SRSPDUType
                        % SRS would be read at the end of the current slot
                        rxSymbolFrame = (timingInfo.Slot + 1) * 14;
                        rnti = ulControlPDU{i}{1};
                        srsInfo = ulControlPDU{i}{2};
                        obj.SRSInfo{rxSymbolFrame, rnti} = srsInfo;
                        obj.NextSRSRxTime = timingInfo.Timestamp + (15e6/obj.CarrierInformation.SubcarrierSpacing); % In nanoseconds
                end
            end
        end

        function phyTx(obj, currentTime, currTimingInfo)
            %phyTx Physical layer transmission

            for i=1:length(obj.PDSCHInfo) % For each DL MAC PDU scheduled to be sent now
                if isempty(obj.MacPDU{i})
                    % MAC PDU not sent by MAC. Indicates retransmission. Get
                    % the MAC PDU from the HARQ buffers
                    obj.MacPDU{i} = obj.HARQBuffers{obj.PDSCHInfo{i}.PDSCHConfig.RNTI, obj.PDSCHInfo{i}.HARQID+1};
                else
                    % New transmission. Buffer the transport block
                    obj.HARQBuffers{obj.PDSCHInfo{i}.PDSCHConfig.RNTI, obj.PDSCHInfo{i}.HARQID+1} = obj.MacPDU{i};
                end

                % Apply FFT scaling to the transmit power
                scaledPower = db2mag(obj.TransmitPower-30) * sqrt((obj.WaveformInfoDL.Nfft^2) / (12*obj.CarrierConfig.NSizeGrid * obj.NumTransmitAntennas));

                % Transmit the transport block
                packetInfo = obj.PacketStruct;
                packetInfo.Data = obj.MacPDU{i};
                packetInfo.Power = mag2db(scaledPower) + 30; %dBm
                packetInfo.Metadata.PrecodingMatrix = obj.PDSCHInfo{i}.PrecodingMatrix;
                packetInfo.Metadata.PacketConfig = obj.PDSCHInfo{i}.PDSCHConfig; % PDSCH Configuration
                packetInfo.Metadata.RNTI = obj.PDSCHInfo{i}.PDSCHConfig.RNTI;
                packetInfo.Metadata.NumSamples = samplesInSlot(obj, obj.CarrierConfig);
                packetInfo.Metadata.PacketType = obj.PXSCHPacket;
                symInfo = obj.PDSCHInfo{i}.PDSCHConfig.SymbolAllocation;
                startSymbol = symInfo(1) + 1;
                endSymbol = symInfo(1) + symInfo(2);
                packetInfo.Duration = round(sum(obj.CarrierInformation.SymbolDurations(startSymbol:endSymbol))/1e9,9);
                packetInfo.StartTime = currentTime/1e9;
                obj.CarrierConfig.NSlot = currTimingInfo.CurrSlot;
                obj.StatTransmittedPackets(packetInfo.Metadata.RNTI) = obj.StatTransmittedPackets(packetInfo.Metadata.RNTI) + 1;
                obj.SendPacketFcn(packetInfo);
            end

            for idx = 1:length(obj.CSIRSInfo)
                % Apply FFT Scaling to the transmit power
                scaledPower = db2mag(obj.TransmitPower-30) * sqrt((obj.WaveformInfoDL.Nfft^2) / (12*obj.CarrierConfig.NSizeGrid * obj.NumTransmitAntennas));
                csirsPacketInfo = obj.PacketStruct;
                % Timing info
                startSymbol = min(obj.CSIRSInfo{idx}{1}.SymbolLocations) + 1;
                endSymbol = max(obj.CSIRSInfo{idx}{1}.SymbolLocations) + 1;
                csirsPacketInfo.StartTime = currentTime/1e9 + round(sum(obj.CarrierInformation.SymbolDurations(1:startSymbol-1))/1e9,9);
                csirsPacketInfo.Duration = round(sum(obj.CarrierInformation.SymbolDurations(startSymbol:endSymbol))/1e9, 9);
                csirsPacketInfo.Metadata.PacketConfig = obj.CSIRSInfo{idx}{1}; % CSI-RS Configuration
                csirsPacketInfo.Power = mag2db(scaledPower) + 30; %dBm;
                csirsPacketInfo.Metadata.PacketType = obj.CSIRSPacket;
                obj.CarrierConfig.NSlot = currTimingInfo.CurrSlot;
                csirsPacketInfo.Metadata.NumSamples = samplesInSlot(obj, obj.CarrierConfig);
                obj.SendPacketFcn(csirsPacketInfo);
            end

            % Transmission done. Clear the Tx contexts
            obj.PDSCHInfo = {};
            obj.MacPDU = {};
            obj.CSIRSInfo = {};
            obj.DataTxTime(currTimingInfo.CurrSlot*14 + currTimingInfo.CurrSymbol + 1) = Inf;
        end

        function phyRx(obj, currTimingInfo)
            %phyRx Physical layer reception procedure for scheduled PUSCH and/or SRS
            % transmissions

            symbolNumFrame = mod(currTimingInfo.CurrSlot*14 + currTimingInfo.CurrSymbol - 1, ...
                obj.CarrierInformation.SymbolsPerFrame); % Previous symbol in a 10 ms frame
            puschInfo = obj.DataRxContext{symbolNumFrame+1};

            % For all PUSCH receptions which ended in the last symbol, send
            % the corresponding PDUs to MAC
            for i=1:length(puschInfo)
                puschRx(obj, puschInfo{i}, currTimingInfo);
            end

            % Process SRS(s)
            if ~isempty(obj.SRSInfo)
                srsInfoList = obj.SRSInfo(symbolNumFrame+1, :);

                idx=find(~cellfun(@isempty, srsInfoList), 1);
                if ~isempty(idx) % If any SRS is scheduled to be read
                    % Get the Tx slot
                    if currTimingInfo.CurrSlot > 0
                        txSlot = currTimingInfo.CurrSlot-1;
                        txSlotAFN = currTimingInfo.AFN; % Tx slot was in the current frame
                    else
                        txSlot = obj.WaveformInfoUL.SlotsPerSubframe*10-1;
                        txSlotAFN = currTimingInfo.AFN - 1; % Tx slot was in the previous frame
                    end

                    % Calculate Rx start symbol number w.r.t start of the 10 ms frame
                    if symbolNumFrame == 0 % Packet was received in the previous frame
                        rxStartSymbol = obj.CarrierInformation.SymbolsPerFrame - 14;
                    else % Packet was received in the current frame
                        rxStartSymbol = (symbolNumFrame + 1) - 14;
                    end

                    % Carrier information
                    carrierConfigInfo = obj.CarrierConfig;
                    carrierConfigInfo.SubcarrierSpacing = obj.CarrierInformation.SubcarrierSpacing;
                    carrierConfigInfo.NSizeGrid = obj.CarrierInformation.NRBsUL;
                    carrierConfigInfo.NSlot = txSlot;
                    carrierConfigInfo.NFrame = txSlotAFN;

                    % Noise Variance
                    nVar = calculateThermalNoise(obj, 1);

                    % Timing info
                    startSymbol = srsInfoList{idx(1)}.SymbolStart + 1;
                    endSymbol = srsInfoList{idx(1)}.SymbolStart + srsInfoList{idx(1)}.NumSRSSymbols;

                    packetType = obj.SRSPacket; % SRS packet
                    [packetInfoList, srsPacket] = packetListIntfBuffer(obj,startSymbol, ...
                        endSymbol,txSlotAFN,rxStartSymbol,packetType);
                    intf = combineIntfInfo(obj, carrierConfigInfo, packetInfoList, nVar);

                    % Process the SRS and send the measurements to MAC
                    for i = 1:length(srsPacket)

                        % Receive SRSPacketInfo
                        packetInfo = srsPacket(i);

                        rnti = packetInfo.Metadata.RNTI;

                        srsConfig = srsInfoList{rnti};
                        srsRefInd = nrSRSIndices(carrierConfigInfo, srsConfig);

                        if ~isempty(srsRefInd)
                            % Scale path gains to accommodate for receiver
                            % gains and pathloss
                            pathGains = packetInfo.Metadata.Channel.PathGains * db2mag(packetInfo.Power-30) * db2mag(obj.ReceiveGain);

                            % Timing and channel estimation
                            offset = nrPerfectTimingEstimate(pathGains, packetInfo.Metadata.Channel.PathFilters.');
                            Hest = nrPerfectChannelEstimate(carrierConfigInfo, pathGains, packetInfo.Metadata.Channel.PathFilters.', ...
                                offset, packetInfo.Metadata.Channel.SampleTimes);

                            % Rank Indicator
                            ulRank = obj.RankIndicator(rnti);
                            srsSymbols = srsConfig.SymbolStart + (1:srsConfig.NumSRSSymbols);
                            [pmi, ~, ~] = nr5g.internal.nrPMISelect(ulRank, Hest(:,srsSymbols,:,:), nVar, obj.CarrierInformation.NRBsUL);

                            cqiRBs = ones(obj.CarrierInformation.NRBsUL, 1);
                            blerThreshold = 0.1;
                            overhead = 0;
                            puschConfiguration = nrPUSCHConfig;
                            puschConfiguration.NumLayers = 1;
                            puschConfiguration.PRBSet = (0:obj.CarrierConfig.NSizeGrid-1);
                            wtx = nrPUSCHCodebook(ulRank,size(Hest,4),pmi);

                            % For the given precoder prepare the LQM input
                            [obj.L2SMsSRS(rnti), sig] = nr5g.internal.L2SM.prepareLQMInput(obj.L2SMsSRS(rnti),carrierConfigInfo,packetInfo.Metadata.PacketConfig,Hest,nVar,wtx);
                            % Determine SINRs from Link Quality Model (LQM)
                            [obj.L2SMsSRS(rnti),SINRs] = nr5g.internal.L2SM.linkQualityModel(obj.L2SMsSRS(rnti),sig,intf);
                            % CQI Selection
                            [obj.L2SMsSRS(rnti),cqi,~] = nr5g.internal.L2SM.cqiSelect(obj.L2SMsSRS(rnti), ...
                                carrierConfigInfo,puschConfiguration,overhead,SINRs,obj.CQITableValues,blerThreshold);

                            if ~isempty(cqi)
                                cqiRBs(:) = cqi;
                            end
                            cqiRBs(cqiRBs<=1) = 1; % Ensuring minimum CQI as 1
                            % Send the measurement report to MAC
                            csiMeasurement = struct('RNTI',rnti,'RankIndicator',ulRank,'TPMI',pmi,'CQI',cqiRBs);
                            obj.SRSIndicationFcn(csiMeasurement);
                        end
                    end
                    obj.SRSInfo(symbolNumFrame + 1, :) = {[]}; % Clear the context
                end
            end
            obj.DataRxContext{symbolNumFrame+1} = {}; % Clear the context
            obj.DataRxTime(symbolNumFrame+1) = Inf;
        end

        function phyStats = statistics(obj)
            %statistics Return the gNB PHY statistics for all UEs
            %
            %   PHYSTATS = statistics(OBJ) Returns the PHY statistics for
            %   all UEs
            %
            %   PHYSTATS - Nx1 array of structures, where N is the number
            %   of UEs. Each structure contains following fields.
            %       UEID                - Node ID of the UE
            %       UEName              - Node name of the UE
            %       RNTI                - RNTI of the UE
            %       TransmittedPackets  - Number of transmitted packets from PHY
            %                             for PDSCH transmission
            %       ReceivedPackets     - Number of received packets at PHY
            %                             for PUSCH reception
            %       DecodeFailures      - Number of decode failures at PHY
            %                             for PUSCH reception

            numUEs = numel(obj.UEInfo);
            phyStats = obj.PHYStatsInfo;

            for ueIdx=1:numUEs
                phyStats(ueIdx).TransmittedPackets = obj.StatTransmittedPackets(ueIdx);
                phyStats(ueIdx).ReceivedPackets = obj.StatReceivedPackets(ueIdx);
                phyStats(ueIdx).DecodeFailures = obj.StatDecodeFailures(ueIdx);
            end
        end

        function storeReception(obj, packets)
            %storeReception Receives the incoming packets and adds them to the reception buffer

            % Loop for all packets
            for pktIdx = 1:numel(packets)
                packetInfo = packets(pktIdx);

                % Do not process the packets that are not transmitted on the
                % receiver frequency or configured as DirecttoDestination
                if packetInfo.DirectToDestination == 0
                    if ~isempty(packetInfo.Data) || packetInfo.Metadata.PacketType == obj.SRSPacket
                        % PUSCH or SRS Packet
                        addPacket(obj.RxBuffer, packetInfo);
                    end
                end
            end
        end
    end

    methods (Hidden)
        function setCarrierInformation(obj, carrierInformation)
            %setCarrierInformation Set the carrier configuration
            %   setCarrierInformation(OBJ, CARRIERINFORMATION) sets the
            %   carrier configuration, CARRIERINFORMATION.
            %
            %   CARRIERINFORMATION is a structure including the following
            %   fields:
            %       SubcarrierSpacing  - Subcarrier spacing
            %       NRBsDL             - Downlink bandwidth in terms of
            %                            number of resource blocks
            %       NRBsUL             - Uplink bandwidth in terms of
            %                            number of resource blocks
            %       DLBandwidth        - Downlink bandwidth in Hz
            %       ULBandwidth        - Uplink bandwidth in Hz
            %       DLFreq             - Downlink carrier frequency in Hz
            %       ULFreq             - Uplink carrier frequency in Hz
            %       NCellID            - Physical cell ID. Values: 0 to 1007
            %                            (TS 38.211, sec 7.4.2.1)
            %       DuplexMode         - Duplexing mode. FDD (value 0) or TDD (value 1)

            setCarrierInformation@nr5g.internal.nrPhyInterface(obj, carrierInformation);

            % Initialize data Rx context
            obj.DataRxContext = cell(obj.CarrierInformation.SymbolsPerFrame, 1);
            % Set waveform properties
            setWaveformProperties(obj, obj.CarrierInformation);
        end
    end

    methods (Access = private)
        function puschRx(obj, puschInfo, currTimingInfo)
            %puschRx Receive the MAC PDU corresponding to PUSCH and send it to MAC

            symbolNumFrame = currTimingInfo.CurrSlot*14 + currTimingInfo.CurrSymbol; % Current symbol number w.r.t start of 10 ms frame

            % Calculate Rx start symbol number w.r.t start of the 10 ms frame
            if symbolNumFrame == 0 % Packet was received in the previous frame
                rxStartSymbol = obj.CarrierInformation.SymbolsPerFrame -  puschInfo.PUSCHConfig.SymbolAllocation(2);
            else % Packet was received in the current frame
                rxStartSymbol = symbolNumFrame - puschInfo.PUSCHConfig.SymbolAllocation(2);
            end

            % Update macPDUInfo
            macPDUInfo = obj.MACPDUInfo;
            macPDUInfo.RNTI = puschInfo.PUSCHConfig.RNTI;
            macPDUInfo.TBS = puschInfo.TBS;
            macPDUInfo.HARQID = puschInfo.HARQID;

            % Get slot information
            slotsPerSubframe=obj.WaveformInfoUL.SlotsPerSubframe;
            [txSlot, txSlotAFN] = txSlotInfo(obj, slotsPerSubframe, currTimingInfo);

            % Compute slot duration based on the subcarrier spacing
            slotDuration = (15/obj.CarrierInformation.SubcarrierSpacing)*1e-3;

            symInfo = puschInfo.PUSCHConfig.SymbolAllocation;
            startSymbol = symInfo(1) + 1;
            endSymbol = symInfo(1) + symInfo(2);
            receptionDuration = sum(obj.CarrierInformation.SymbolDurations(startSymbol:endSymbol));

            % Compute start and end time for packet extraction from
            % interference buffer
            numSlotPerSubFrame = (obj.CarrierInformation.SubcarrierSpacing/15);
            pktStartTime = ((txSlotAFN*140*numSlotPerSubFrame +  rxStartSymbol)/14) * slotDuration;
            pktEndTime = pktStartTime + receptionDuration/1e9;

            % Get packet list from interference buffer
            packetInfoList = packetList(obj.RxBuffer, pktStartTime, pktEndTime);

            % Check if valid packet exists for the puschInfo and return
            % packet index
            validPktOfInterestIdx = checkPktOfInterest(obj, packetInfoList, puschInfo.PUSCHConfig.RNTI);

            if ~isempty(validPktOfInterestIdx)
                % Carrier information
                carrierConfigInfo = obj.CarrierConfig;
                carrierConfigInfo.SubcarrierSpacing = obj.CarrierInformation.SubcarrierSpacing;
                carrierConfigInfo.NSizeGrid = obj.CarrierInformation.NRBsUL;
                carrierConfigInfo.NSlot = txSlot;
                carrierConfigInfo.NFrame = txSlotAFN;

                rnti = puschInfo.PUSCHConfig.RNTI;

                % Extract PUSCH Indices for the packet of interest
                [~, info] = nrPUSCHIndices(carrierConfigInfo, puschInfo.PUSCHConfig);

                % Prepare HARQ context for the packet of interest
                harqInfo = struct('HARQProcessID', puschInfo.HARQID, 'RedundancyVersion', puschInfo.RV, ...
                    'TransportBlockSize', puschInfo.TBS*8, 'NewData', puschInfo.NewData);

                numPkts = numel(packetInfoList);
                % Remove those packets from the packet list which are not overlapping in RBs
                prbSetSignal = puschInfo.PUSCHConfig.PRBSet;
                intfPktFlag = zeros(1,numPkts);
                for pktIdx = 1:numPkts
                    % Check for PUSCH packet
                    if (packetInfoList(pktIdx).Metadata.PacketType == obj.PXSCHPacket)
                        prbSetInterferer = packetInfoList(pktIdx).Metadata.PacketConfig.PRBSet;
                        if ~isempty(intersect(prbSetSignal,prbSetInterferer))
                            intfPktFlag(pktIdx)=1;
                        end
                    end
                end
                packetInfoList(intfPktFlag==0)=[];
                numPkts = numel(packetInfoList); % Number of packets for updated packetInfoList

                % Filter for relevant packets i.e. packet of interest, inter cell interferers
                % and inter user interferers. Estimate channel for all valid packets.
                [estChannelGrid, pktOfInterestIdx] = estPerfectChannelGrid(obj, carrierConfigInfo, packetInfoList, rnti);

                % Noise Variance
                nVar = calculateThermalNoise(obj, 1);
                intf = [];
                intfCounter = 0;

                % Loop for valid packets and prepare Link Quality Model (LQM)
                for pktIdx = 1:numPkts
                    % Packet to be processed by LQM
                    packetInfoLQM = packetInfoList(pktIdx);

                    % Access the configuration of the packet
                    pusch = packetInfoLQM.Metadata.PacketConfig;
                    puschPrecoder = packetInfoLQM.Metadata.PrecodingMatrix;

                    if (pktIdx==pktOfInterestIdx)
                        % Update HARQ information for the packet of interest
                        obj.L2SMs(rnti) = nr5g.internal.L2SM.txHARQ(obj.L2SMs(rnti),harqInfo,puschInfo.TargetCodeRate,info.G);
                        % Prepare Link Quality Model inputs for the current
                        % packets
                        [obj.L2SMs(rnti), sig]  =nr5g.internal.L2SM.prepareLQMInput(obj.L2SMs(rnti),carrierConfigInfo,pusch,estChannelGrid{pktIdx},nVar,puschPrecoder);
                    else
                        [~, lqmiInfo] = nr5g.internal.L2SM.prepareLQMInput(obj.L2SMIntf,carrierConfigInfo,pusch,estChannelGrid{pktIdx},nVar,puschPrecoder);
                        intfCounter = intfCounter + 1;
                        if isempty(intf)
                            intf = repmat(lqmiInfo,numPkts-1,1);
                        else
                            intf(intfCounter) = lqmiInfo;
                        end
                    end
                end

                % Link Quality Model (LQM) with interference
                [obj.L2SMs(rnti),sinr] = nr5g.internal.L2SM.linkQualityModel(obj.L2SMs(rnti),sig,intf);

                % Link Performance Model
                [obj.L2SMs(rnti), crcFlag] = nr5g.internal.L2SM.linkPerformanceModel(obj.L2SMs(rnti),harqInfo,puschInfo.PUSCHConfig,sinr);

                % Update PHY statistics
                % Increment the number of received packets for UE
                obj.StatReceivedPackets(puschInfo.PUSCHConfig.RNTI) = obj.StatReceivedPackets(puschInfo.PUSCHConfig.RNTI) + 1;
                % Increment the number of decode failures received for UE
                obj.StatDecodeFailures(puschInfo.PUSCHConfig.RNTI) = obj.StatDecodeFailures(puschInfo.PUSCHConfig.RNTI) + crcFlag;

                macPDUInfo.MACPDU = packetInfoList(pktOfInterestIdx).Data;
                macPDUInfo.CRCFlag = crcFlag;

                % SINR for the received packet
                obj.SINR = sinr;
            end

            % Rx callback to MAC
            obj.RxIndicationFcn(macPDUInfo);
        end

        function nextInvokeTime = getNextInvokeTime(obj, currentTime) 
            %getNextInvokeTime Return the next invoke time in nanoseconds

            % Find the next invoke time for PHY Tx
            pdschTxNextInvokeTime = min(obj.DataTxTime);

            % Find the next invoke time for SRS reception
            if obj.NextSRSRxTime > currentTime
                srsRxNextInvokeTime = obj.NextSRSRxTime;
            else
                srsRxNextInvokeTime = Inf;
            end

            % Find the next PHY Rx invoke time
            puschRxNextInvokeTime = min(obj.DataRxTime);

            nextInvokeTime = min([pdschTxNextInvokeTime puschRxNextInvokeTime srsRxNextInvokeTime]); 
        end
    end
end
