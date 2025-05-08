classdef (Abstract) nrScheduler < handle
    %nrScheduler Implements physical uplink shared channel (PUSCH) and physical downlink shared channel (PDSCH) resource scheduling
    %   The class implements uplink (UL) and downlink (DL) scheduling for
    %   both FDD and TDD modes. It supports both slot based and symbol
    %   based scheduling. Scheduling is only done at slot boundary when
    %   start symbol is DL so that output (resource assignments) can be
    %   immediately conveyed to UEs in DL direction, assuming zero run time
    %   for scheduler algorithm. Hence, in frequency division duplex (FDD)
    %   mode the schedulers (DL and UL) run periodically (configurable) as
    %   every slot is DL while for time division duplex (TDD) mode, DL time
    %   is checked. In FDD mode, schedulers run to assign the resources
    %   from the next unscheduled slot onwards and a count of slots equal
    %   to scheduler periodicity in terms of number of slots are scheduled.
    %   In TDD mode, the UL scheduler schedules the resources as close to
    %   the transmission time as possible. The DL scheduler in TDD mode
    %   runs to assign DL resources of the next slot with unscheduled DL
    %   resources. Scheduler does the UL resource allocation while
    %   considering the PUSCH preparation capability of UEs. Scheduling
    %   decisions are based on selected scheduling strategy, scheduler
    %   configuration and the context (buffer status, served data rate,
    %   channel conditions and pending retransmissions) maintained for each
    %   UE. The information available to scheduler for making scheduling
    %   decisions is present as various properties of this class. The class
    %   also implements the MAC portion of the HARQ functionality for
    %   retransmissions.
    %
    %   Note: This is an internal undocumented class and its API and/or
    %   functionality may change in subsequent releases.

    %   Copyright 2022-2023 The MathWorks, Inc.

    properties (SetAccess = protected, GetAccess = public)
        %UEs RNTIs of the UEs connected to the gNB
        UEs

        %SCS Subcarrier spacing used. The default value is 15 kHz
        SCS

        %Slot slot duration in ms
        SlotDuration

        %NumSlotsFrame Number of slots in a 10 ms frame. Depends on the SCS used
        NumSlotsFrame

        %SchedulingType Type of scheduling (slot based or symbol based)
        % Value 0 means slot based and value 1 means symbol based. The
        % default value is 0
        SchedulingType (1, 1) {mustBeInteger, mustBeInRange(SchedulingType, 0, 1)} = 0;

        %DuplexMode Duplexing mode (FDD or TDD)
        % Value 0 means FDD and 1 means TDD. The default value is 0
        DuplexMode (1, 1) {mustBeInteger, mustBeInRange(DuplexMode, 0, 1)} = 0;

        %ResourceAllocationType Type for resource allocation type (RAT)
        % Value 0 means RAT-0 and value 1 means RAT-1. The default value is 0
        ResourceAllocationType (1, 1) {mustBeInteger, mustBeInRange(ResourceAllocationType, 0, 1)} = 0;

        %NumDLULPatternSlots Number of slots in DL-UL pattern (for TDD mode)
        % The default value is 5 slots
        NumDLULPatternSlots (1, 1) {mustBeInteger, mustBeGreaterThanOrEqual(NumDLULPatternSlots, 0), mustBeFinite} = 5;

        %NumDLSlots Number of full DL slots at the start of DL-UL pattern (for TDD mode)
        % The default value is 2 slots
        NumDLSlots (1, 1) {mustBeInteger, mustBeGreaterThanOrEqual(NumDLSlots, 0), mustBeFinite} = 2;

        %NumDLSymbols Number of DL symbols after full DL slots in the DL-UL pattern (for TDD mode)
        % The default value is 8 symbols
        NumDLSymbols (1, 1) {mustBeInteger, mustBeInRange(NumDLSymbols, 0, 13)} = 8;

        %NumULSymbols Number of UL symbols before full UL slots in the DL-UL pattern (for TDD mode)
        % The default value is 4 symbols
        NumULSymbols (1, 1) {mustBeInteger, mustBeInRange(NumULSymbols, 0, 13)} = 4;

        %NumULSlots Number of full UL slots at the end of DL-UL pattern (for TDD mode)
        % The default value is 2 slots
        NumULSlots (1, 1) {mustBeInteger, mustBeGreaterThanOrEqual(NumULSlots, 0), mustBeFinite} = 2;

        %DLULSlotFormat Format of the slots in DL-UL pattern (for TDD mode)
        % N-by-14 matrix where 'N' is number of slots in DL-UL pattern.
        % Each row contains the symbol type of the 14 symbols in the slot.
        % Value 0, 1 and 2 represent DL symbol, UL symbol, guard symbol,
        % respectively
        DLULSlotFormat

        %NextULSchedulingSlot Slot to be scheduled next by UL scheduler
        % Slot number in the 10 ms frame whose resources will be scheduled
        % when UL scheduler runs next (for TDD mode)
        NextULSchedulingSlot

        %NumResourceBlocks Number of resource blocks (RB) in the uplink and downlink bandwidth
        % The default value is 52 RBs
        NumResourceBlocks (1, 1){mustBeNonempty, mustBeInteger, mustBeInRange(NumResourceBlocks, 1, 275)} = 52;

        %SchedulerPeriodicity Periodicity at which the schedulers (DL and UL) run in terms of number of slots (for FDD mode)
        % Default value is 1 slot. Maximum number of slots in a frame is
        % 160 (i.e SCS 240 kHz)
        SchedulerPeriodicity {mustBeInteger, mustBeInRange(SchedulerPeriodicity, 1, 160)} = 1;

        %PUSCHPrepSymDur PUSCH preparation time in terms of number of symbols
        % Scheduler ensures that PUSCH grant arrives at UEs at least these
        % many symbols before the transmission time
        PUSCHPrepSymDur

        %BufferStatusDL Stores pending buffer amount in DL direction for logical channels of UEs
        % N-by-32 (maximum logical channels) matrix where 'N' is the number of UEs. Each row represents a
        % UE and has 32 columns to store the pending DL buffer (in bytes)
        % for logical channel IDs 1 to 32
        BufferStatusDL

        %BufferStatusDLPerUE Total pending DL buffer amount for UEs
        % N-by-1 matrix where 'N' is the number of UEs. Each row represents
        % the cumulative sum of all LCH's pending DL buffer (in bytes) for
        % a UE. It accounts for total amount of data scheduled since the
        % last RLC buffer status update
        BufferStatusDLPerUE

        %BufferStatusUL Stores pending buffer amount in UL direction for logical channel groups of UEs
        % N-by-8 matrix where 'N' is the number of UEs. Each row represents a
        % UE and has 8 columns to store the pending UL buffer amount (in
        % bytes) for each logical channel group.
        BufferStatusUL

        %BufferStatusULPerUE Total pending UL buffer amount for UEs
        % N-by-1 matrix where 'N' is the number of UEs. Each row represents
        % the cumulative sum of all LCG's pending UL buffer (in bytes) for
        % a UE. It accounts for total amount of data scheduled since the
        % last BSR update
        BufferStatusULPerUE

        %TTIGranularity Minimum time-domain assignment in terms of number of symbols (for symbol based scheduling).
        % The default value is 4 symbols
        TTIGranularity {mustBeMember(TTIGranularity, [2, 4, 7])} = 4;

        %DMRSTypeAPosition Position of DM-RS in type A transmission
        DMRSTypeAPosition (1, 1) {mustBeMember(DMRSTypeAPosition, [2, 3])} = 2;

        %PUSCHMappingType PUSCH mapping type
        PUSCHMappingType (1,1) {mustBeMember(PUSCHMappingType, ['A', 'B'])} = 'A';

        %PUSCHDMRSConfigurationType PUSCH DM-RS configuration type (1 or 2)
        PUSCHDMRSConfigurationType (1,1) {mustBeMember(PUSCHDMRSConfigurationType, [1, 2])} = 1;

        %PUSCHDMRSLength PUSCH demodulation reference signal (DM-RS) length
        PUSCHDMRSLength (1, 1) {mustBeMember(PUSCHDMRSLength, [1, 2])} = 1;

        %PUSCHDMRSAdditionalPosTypeA Additional PUSCH DM-RS positions for type A (0..3)
        PUSCHDMRSAdditionalPosTypeA (1, 1) {mustBeMember(PUSCHDMRSAdditionalPosTypeA, [0, 1, 2, 3])} = 0;

        %PUSCHDMRSAdditionalPosTypeB Additional PUSCH DM-RS positions for type B (0..3)
        PUSCHDMRSAdditionalPosTypeB (1, 1) {mustBeMember(PUSCHDMRSAdditionalPosTypeB, [0, 1, 2, 3])} = 0;

        %PDSCHMappingType PDSCH mapping type
        PDSCHMappingType (1, 1) {mustBeMember(PDSCHMappingType, ['A', 'B'])} = 'A';

        %PDSCHDMRSConfigurationType PDSCH DM-RS configuration type (1 or 2)
        PDSCHDMRSConfigurationType (1,1) {mustBeMember(PDSCHDMRSConfigurationType, [1, 2])} = 1;

        %PDSCHDMRSLength PDSCH demodulation reference signal (DM-RS) length
        PDSCHDMRSLength (1, 1) {mustBeMember(PDSCHDMRSLength, [1, 2])} = 1;

        %PDSCHDMRSAdditionalPosTypeA Additional PDSCH DM-RS positions for type A (0..3)
        PDSCHDMRSAdditionalPosTypeA (1, 1) {mustBeMember(PDSCHDMRSAdditionalPosTypeA, [0, 1, 2, 3])} = 0;

        %PDSCHDMRSAdditionalPosTypeB Additional PDSCH DM-RS positions for type B (0 or 1)
        PDSCHDMRSAdditionalPosTypeB (1, 1) {mustBeMember(PDSCHDMRSAdditionalPosTypeB, [0, 1])} = 0;

        %CSIMeasurementDL Reported DL CSI measurements
        % Array of size 'N', where 'N' is the number of UEs. Each element is a structure with the fields: 'RankIndicator', 'PMISet', 'CQI'
        % RankIndicator is a scalar value to representing the rank reported by a UE.
        % PMISet has the following fields:
        %   i1 - Indicates wideband PMI (1-based). It a three-element vector in the
        %        form of [i11 i12 i13].
        %   i2 - Indicates subband PMI (1-based). It is a vector of length equal to
        %        the number of subbands or number of PRGs.
        % CQI - Array of size equal to number of RBs in the bandwidth. Each index
        % contains the CQI value corresponding to the RB index.
        % W - Precoder corresponding to the reported PMISet
        % If CSI reporting for CSI-RS Resource Indicator (CRI) & layer-1 reference
        % signal received power(L1-RSRP) measurements are configured, it contains the following additional fields
        %   CSIResourceIndicator - CRI corresponding to the beam with the
        %                          highest RSRP measurement
        %   L1RSRP               - Highest L1-RSRP measurement among all the
        %                          CSI-RS beam directions used for DL beam
        %                          refinement
        CSIMeasurementDL

        %CSIMeasurementUL Reported UL CSI measurements
        % Array of size 'N', where 'N' is the number of UEs. Each element is a structure with the fields: 'RankIndicator', 'TPMI', 'CQI'
        % RankIndicator is a scalar value to representing the rank estimated for a UE.
        % TPMI - Transmission precoding matrix indicator
        % CQI - Array of size equal to number of RBs in the bandwidth. Each index
        % contains the CQI value corresponding to the RB index.
        CSIMeasurementUL

        %NumTransmitAntennas Number of transmit antennas at gNB
        NumTransmitAntennas

        %NumReceiveAntennas Number of receive antennas at gNB
        NumReceiveAntennas

        %NumTransmitAntennasUE Number of transmit antennas at UEs
        NumTransmitAntennasUE

        %NumReceiveAntennasUE Number of receive antennas at UEs
        NumReceiveAntennasUE

        %SSBIdx Index of the SSB associated with the UEs
        % It is a vector of length N, where 'N' is the number of UEs
        % connected to the gNB. The element at position 'i' corresponds to
        % the SSB beam associated with the UE with RNTI 'i'
        SSBIdx

        %NumCSIRSBeams Number of directions for CSI-RS beam refinement within an SSB
        NumCSIRSBeams = 4;

        %BeamWeightTable Digital beamforming weights table
        % It is a matrix of size M-by-N where M is equal to the number of
        % transmit antennas and N is the number of beam directions. Each
        % column corresponds to the beam weight used to steer the downlink
        % transmission in a particular direction.
        BeamWeightTable

        %NumCSIRSPorts Number of CSI-RS antenna ports for the UEs
        % Vector of length 'N' where 'N' is the number of UEs. Value at
        % index 'i' contains the number of CSI-RS ports for UE with RNTI
        % 'i'
        NumCSIRSPorts

        %NumSRSPorts Number of SRS antenna ports for the UEs
        % Vector of length 'N' where 'N' is the number of UEs. Value at
        % index 'i' contains the number of SRS ports for UE with RNTI 'i'
        NumSRSPorts

        %NumHARQ Number of HARQ processes
        % The default value is 16 HARQ processes
        NumHARQ (1, 1) {mustBeInteger, mustBeInRange(NumHARQ, 1, 16)} = 16;

        %HarqProcessesUL Uplink HARQ processes context
        % N-by-P structure array where 'N' is the number of UEs and 'P' is
        % the number of HARQ processes. Each row in this matrix stores the
        % context of all the uplink HARQ processes of a particular UE.
        HarqProcessesUL

        %HarqProcessesDL Downlink HARQ processes context
        % N-by-P structure array where 'N' is the number of UEs and 'P' is
        % the number of HARQ processes. Each row in this matrix stores the
        % context of all the downlink HARQ processes of a particular UE.
        HarqProcessesDL

        %HarqStatusUL Status (free or busy) of each uplink HARQ process of the UEs
        % N-by-P cell array where 'N' is the number of UEs and 'P' is the number
        % of HARQ processes. A non-empty value at index (i,j) indicates
        % that HARQ process is busy with value being the uplink grant for
        % the UE with RNTI 'i' and HARQ index 'j'. Empty value indicates
        % that the HARQ process is free.
        HarqStatusUL

        %HarqStatusDL Status (free or busy) of each downlink HARQ process of the UEs
        % N-by-P cell array where 'N' is the number of UEs and 'P' is the number
        % of HARQ processes. A non-empty value at index (i,j) indicates
        % that HARQ process is busy with value being the downlink grant for
        % the UE with RNTI 'i' and HARQ index 'j'. Empty value indicates
        % that the HARQ process is free.
        HarqStatusDL

        %HarqNDIDL Last sent NDI value for the DL HARQ processes of the UEs
        % N-by-P logical array where 'N' is the number of UEs and 'P' is the number
        % of HARQ processes. Values at index (i,j) stores the last sent NDI
        % for the UE with RNTI 'i' and DL HARQ process index 'j'
        HarqNDIDL

        %HarqNDIUL Last sent NDI value for the UL HARQ processes of the UEs
        % N-by-P logical array where 'N' is the number of UEs and 'P' is the number
        % of HARQ processes. Values at index (i,j) stores the last sent NDI
        % for the UE with RNTI 'i' and UL HARQ process index 'j'
        HarqNDIUL

        %RetransmissionContextUL Information about uplink retransmission requirements of the UEs
        % N-by-P cell array where 'N' is the number of UEs and 'P' is the
        % number of HARQ processes. It stores the information of HARQ
        % processes for which the reception failed at gNB. This information
        % is used for assigning uplink grants for retransmissions. Each row
        % corresponds to a UE and a non-empty value in one of its columns
        % indicates that the reception has failed for this particular HARQ
        % process governed by the column index. The value in the cell
        % element would be uplink grant information used by the UE for the
        % previous failed transmission
        RetransmissionContextUL

        %RetransmissionContextDL Information about downlink retransmission requirements of the UEs
        % N-by-P cell array where 'N' is the number of UEs and 'P' is the
        % number of HARQ processes. It stores the information of HARQ
        % processes for which the reception failed at UE. This information
        % is used for assigning downlink grants for retransmissions. Each
        % row corresponds to a UE and a non-empty value in one of its
        % columns indicates that the reception has failed for this
        % particular HARQ process governed by the column index. The value
        % in the cell element would be downlink grant information used by
        % the gNB for the previous failed transmission
        RetransmissionContextDL

        %TBSizeDL Stores the size of transport block sent for DL HARQ processes
        % N-by-P matrix where 'N' is the number of UEs and P is number of
        % HARQ process. Value at index (i,j) stores size of transport block
        % sent for UE with RNTI 'i' for HARQ process index 'j'.
        % Value is 0 if DL HARQ process is free
        TBSizeDL

        %TBSizeUL Stores the size of transport block to be received for UL HARQ processes
        % N-by-P matrix where 'N' is the number of UEs and P is number of
        % HARQ process. Value at index (i,j) stores size of transport block
        % to be received from UE with RNTI 'i' for HARQ process index 'j'.
        % Value is 0, if no UL packet expected for HARQ process of the UE
        TBSizeUL

        %MaxNumUsersPerTTI Maximum users that can be scheduled per TTI
        MaxNumUsersPerTTI

        %FixedMCSIndexDL MCS index that will be used to allocate DL
        %resources without considering any channel quality information
        FixedMCSIndexDL

        %FixedMCSIndexUL MCS index that will be used to allocate UL
        %resources without considering any channel quality information
        FixedMCSIndexUL

        %MUMIMOConfigDL Structure that contains these DL MU-MIMO parameters
        %   MaxNumUsersPaired - Maximum number of users that can be paired for a
        %                       MU-MIMO transmission
        %   MinNumRBs         - Minimum number of RBs that must be allocated to a
        %                       UE to be considered for MU-MIMO
        %   MinCQI            - Minimum CQI for a UE to be considered as a MU-MIMO
        %                       candidate
        %   SemiOrthogonalityFactor - Inter-user interference (IUI) orthogonality
        %                             factor based on which users can be paired for
        %                             a MU-MIMO transmission
        MUMIMOConfigDL

        %UserPairingMatrix Precomputed orthogonality matrix for all UEs based on the
        % CSI type II reports
        UserPairingMatrix
    end

    properties (Access = protected)
        %CurrSlot Current running slot number in the 10 ms frame at the time of scheduler invocation
        CurrSlot = 0;

        %CurrSymbol Current running symbol of the current slot at the time of scheduler invocation
        CurrSymbol = 0;

        %SFN System frame number (0 ... 1023) at the time of scheduler invocation
        SFN = 0;

        %CurrDLULSlotIndex Slot index of the current running slot in the DL-UL pattern at the time of scheduler invocation (for TDD mode)
        CurrDLULSlotIndex = 0;

        %SlotsSinceSchedulerRunDL Number of slots elapsed since last DL scheduler run (for FDD mode)
        % It is incremented every slot and when it reaches the
        % 'SchedulerPeriodicity', it is reset to zero and DL scheduler runs
        SlotsSinceSchedulerRunDL

        %SlotsSinceSchedulerRunUL Number of slots elapsed since last UL scheduler run (for FDD mode)
        % It is incremented every slot and when it reaches the
        % 'SchedulerPeriodicity', it is reset to zero and UL scheduler runs
        SlotsSinceSchedulerRunUL

        %LastSelectedUEUL The RNTI of UE which was assigned the last scheduled uplink resource
        LastSelectedUEUL = 0;

        %LastSelectedUEDL The RNTI of UE which was assigned the last scheduled downlink resource
        LastSelectedUEDL = 0;

        %GuardDuration Guard period in the DL-UL pattern in terms of number of symbols (for TDD mode)
        GuardDuration

        %Type1SinglePanelCodebook Type-1 single panel precoding matrix codebook
        Type1SinglePanelCodebook = []

        %PrecodingGranularity PDSCH precoding granularity in terms of physical resource blocks (PRBs)
        PrecodingGranularity = 2

        %UEInfo Information about the UEs connected to the GNB
        % N-by-1 array where 'N' is the number of UEs. Each element in the
        % array is a structure with two fields.
        %   ID - Node id of the UE
        %   Name - Node Name of the UE
        UEInfo
    end

    properties (Constant)
        %NominalRBGSizePerBW Nominal RBG size for the specified bandwidth in accordance with 3GPP TS 38.214, Section 5.1.2.2.1
        NominalRBGSizePerBW = [
            36   2   4
            72   4   8
            144  8   16
            275  16  16 ];

        %DLType Value to specify downlink direction or downlink symbol type
        DLType = 0;

        %ULType Value to specify uplink direction or uplink symbol type
        ULType = 1;

        %GuardType Value to specify guard symbol type
        GuardType = 2;

        %SchedulerInput Format of the context that will be sent to the scheduling strategy
        SchedulerInput = struct('linkDir', 0, 'eligibleUEs', 1, 'slotNum', 0, 'startSym', 0, ...
            'numSym', 0, 'RBGIndex', 0, 'RBGSize', 0, 'bufferStatus', 0, 'cqiRBG', 1, ...
            'mcsRBG', 1, 'ttiDur', 1, 'UEs', 1, 'selectedRank', 1, 'lastSelectedUE', 1);

        %ULGrantInfo Format of the UL grant information
        ULGrantInfo = struct('RNTI',[],'Type',[],'HARQID',[],'ResourceAllocationType',[],'FrequencyAllocation',[], ...
            'StartSymbol',[],'NumSymbols',[],'SlotOffset',[],'MCS',[],'NDI',[], ...
            'DMRSLength',[],'MappingType',[],'NumLayers',[],'NumCDMGroupsWithoutData',[], ...
            'NumAntennaPorts',[],'TPMI',[],'RV',[]);

        %DLGrantInfo Format of the DL grant information
        DLGrantInfo = struct('RNTI',[],'Type',[],'HARQID',[],'ResourceAllocationType',[],'FrequencyAllocation',[], ...
            'StartSymbol',[],'NumSymbols',[],'SlotOffset',[],'MCS',[],'NDI',[], ...
            'DMRSLength',[],'MappingType',[],'NumLayers',[],'NumCDMGroupsWithoutData',[], ...
            'BeamIndex',[],'PrecodingMatrix',[],'FeedbackSlotOffset',[],'RV',[],'MUMIMO', 0);
    end

    properties (Access = protected)
        %% Transient object maintained for optimization
        %PUSCHConfig nrPUSCHConfig object
        PUSCHConfig
        %PDSCHConfig nrPDSCHConfig object
        PDSCHConfig
        %CarrierConfigUL nrCarrierConfig object for UL
        CarrierConfigUL
        %CarrierConfigDL nrCarrierConfig object for DL
        CarrierConfigDL
    end

    properties(Hidden)
        %AdaptiveRetransmission Retransmission mechanism (adaptive or non-adaptive)
        % Value 0 means non-adaptive retransmissions and value 1 means
        % adaptive retransmissions. The default value is 0
        AdaptiveRetransmission (1, 1) {mustBeInteger, mustBeInRange(AdaptiveRetransmission, 0, 1)} = 0;

        %CQITableUL CQI table used for uplink
        % It contains the mapping of CQI indices with Modulation and Coding
        % schemes
        CQITableUL

        %MCSTableUL MCS table used for uplink
        % It contains the mapping of MCS indices with Modulation and Coding
        % schemes
        MCSTableUL

        %CQITableDL CQI table used for downlink
        % It contains the mapping of CQI indices with Modulation and Coding
        % schemes
        CQITableDL

        %MCSTableDL MCS table used for downlink
        % It contains the mapping of MCS indices with Modulation and Coding
        % schemes
        MCSTableDL

        %XOverheadPDSCH Additional overheads in PDSCH transmission
        XOverheadPDSCH = 0;

        %RBGSize Size of a resource block group (RBG) in terms of number of RBs
        RBGSize

        %NumRBGs Number of RBGs in uplink bandwidth
        NumRBGs

        %ULReservedResource Reserved resources information for UL direction
        % Array of three elements: [symNum slotPeriodicity slotOffset].
        % These symbols are not available for PUSCH scheduling as per the
        % slot offset and periodicity. Currently, it is used for SRS
        % resources reservation
        ULReservedResource

        %RBAllocationLimitUL Maximum limit on number of RBs that can be allotted for a PUSCH
        % The limit is applicable for new PUSCH transmissions and not for
        % retransmissions
        RBAllocationLimitUL {mustBeInteger, mustBeInRange(RBAllocationLimitUL, 1, 275)};

        %RBAllocationLimitDL Maximum limit on number of RBs that can be allotted for a PDSCH
        % The limit is applicable for new PDSCH transmissions and not for
        % retransmissions
        RBAllocationLimitDL {mustBeInteger, mustBeInRange(RBAllocationLimitDL, 1, 275)};

        %RVSequenceRedundancy version (RV) sequence
        RVSequence = [0 3 2 1]
    end

    methods
        function obj = nrScheduler(param)
            %nrScheduler Construct gNB MAC scheduler object
            %
            % param is a structure including the following fields:
            % DuplexMode       - Duplexing mode as 'FDD' or 'TDD'
            % SchedulingType   - Slot based scheduling (value 0) or symbol based
            %                    scheduling (value 1)
            % TTIGranularity   - Smallest TTI size in terms of number of symbols (for
            %                    symbol based scheduling)
            % ResourceAllocationType - RAT-0 (value 0) or RAT-1 (value 1)
            % NumResourceBlocks      - Number of resource blocks in PUSCH and PDSCH
            %                          bandwidth
            % SubcarrierSpacing      - Subcarrier spacing
            % SchedulerPeriodicity   - Scheduler run periodicity in slots (for FDD
            %                          mode)
            % RBAllocationLimitUL    - Maximum limit on the number of RBs allotted to a
            %                          UE for a PUSCH
            % RBAllocationLimitDL    - Maximum limit on the number of RBs allotted to a
            %                          UE for a PDSCH
            % NumHARQ                - Number of HARQ processes
            % EnableHARQ             - Flag to enable/disable retransmissions
            % RVSequence             - Redundancy version sequence to be followed
            % DLULConfigTDD          - TDD specific configuration. It is a structure
            %                          with following fields.
            %       DLULPeriodicity - Duration of the DL-UL pattern in ms (for TDD
            %                         mode)
            %       NumDLSlots      - Number of full DL slots at the start of DL-UL
            %                         pattern (for TDD mode)
            %       NumDLSymbols    - Number of DL symbols after full DL slots of DL-UL
            %                         pattern (for TDD mode)
            %       NumULSymbols    - Number of UL symbols before full UL slots of
            %                         DL-UL pattern (for TDD mode)
            %       NumULSlots      - Number of full UL slots at the end of DL-UL
            %                         pattern (for TDD mode)
            % PUSCHPrepTime         - PUSCH preparation time required by UEs (in
            %                         microseconds).
            % RBGSizeConfig         - RBG size configuration as 1 (configuration-1 RBG
            %                         table) or 2 (configuration-2 RBG table) as
            %                         defined in 3GPP TS 38.214 Section 5.1.2.2.1. It
            %                         defines the number of RBs in an RBG. Default
            %                         value is 1.
            % DMRSTypeAPosition            - DM-RS type A position (2 or 3)
            % PUSCHMappingType             - PUSCH mapping type ('A' or 'B')
            % PUSCHDMRSConfigurationType   - PUSCH DM-RS configuration type (1 or 2)
            % PUSCHDMRSLength              - PUSCH DM-RS length (1 or 2)
            % PUSCHDMRSAdditionalPosTypeA  - Additional PUSCH DM-RS positions for Type A (0..3)
            % PUSCHDMRSAdditionalPosTypeB  - Additional PUSCH DM-RS positions for Type B (0..3)
            % PDSCHMappingType             - PDSCH mapping type ('A' or 'B')
            % PDSCHDMRSConfigurationType   - PDSCH DM-RS configuration type (1 or 2)
            % PDSCHDMRSLength              - PDSCH DM-RS length (1 or 2)
            % PDSCHDMRSAdditionalPosTypeA  - Additional PDSCH DM-RS positions for Type A (0..3)
            % PDSCHDMRSAdditionalPosTypeB  - Additional PDSCH DM-RS positions for Type B (0 or 1)
            % NumTransmitAntennas          - Number of GNB Tx antennas
            % NumReceiverAntennas          - Number of GNB Rx antennas
            % CSIReportConfig - Cell array containing the CSI-RS report configuration
            %                   information as a structure. The element at index 'i'
            %                   corresponds to the CSI-RS report configured for a UE
            %                   with RNTI 'i'. If only one CSI-RS report configuration
            %                   is specified, it is assumed to be applicable for all
            %                   the UEs in the cell. Each element is a structure with
            %                   the following fields:
            % CQIMode         - CQI reporting mode. Value as 'Subband' or 'Wideband'
            % SubbandSize     - Subband size for CQI or PMI reporting as per TS 38.214
            %                   Table 5.2.1.4-2 Additional fields for MIMO systems:
            % PanelDimensions - Antenna panel configuration as a two-element vector
            %                   in the form of [N1 N2]. N1 represents the number of
            %                   antenna elements in horizontal direction and N2
            %                   represents the number of antenna elements in vertical
            %                   direction Valid combinations of [N1 N2] are defined in
            %                   3GPP TS 38.214 Table 5.2.2.2.1-2
            % PMIMode          - PMI reporting mode. Value as 'Subband' or 'Wideband'
            % CodebookMode     - Codebook mode. Value as 1 or 2
            % SRSSubbandSize   - SRS subband size (in RBs)
            % SSBIndex         - Index of the SSB associated with the UEs.It is a
            %                    vector of length N, where 'N'
            %                    is the number of UEs connected to the gNB. The element
            %                    at position 'i' corresponds to the SSB beam associated
            %                    with the UE with RNTI 'i'
            % BeamWeightTable  - It is a matrix of size M-by-N where M is equal to the
            %                    number of transmit antennas and N is the number of
            %                    beam directions. Each column corresponds to the beam
            %                    weight used to steer the downlink transmission in a
            %                    particular direction.
            % SRSReservedResource - SRS reserved resource as [symbolNum slotPeriodicity
            %                       slotOffset]
            % MaxNumUsersPerTTI   - Maximum users that can be scheduled per TTI
            % FixedMCSIndexDL     - MCS index that will be used to allocate DL
            %                       resources without considering any channel quality
            %                       information
            % FixedMCSIndexUL     - MCS index that will be used to allocate UL
            %                       resources without considering any channel quality
            %                       information
            % MUMIMOConfigDL   - MU-MIMO configuration structure contains these fields.
            %   MaxNumUsersPaired - Maximum number of users that can be paired for a
            %                       MU-MIMO transmission
            %   MinNumRBs         - Minimum number of RBs that should be allocated to a
            %                       UE to be considered for MU-MIMO
            %   MinCQI            - Minimum CQI for a UE to be considered as a MU-MIMO
            %                       candidate
            %   SemiOrthogonalityFactor - Inter-user interference (IUI) orthogonality
            %                             factor based on which users can be paired for
            %                             a MU-MIMO transmission

            inputParam = {'NumHARQ', 'NumResourceBlocks', 'NumTransmitAntennas'};
            for idx=1:numel(inputParam)
                obj.(char(inputParam{idx})) = param.(inputParam{idx});
            end

            % Set resource allocation type
            obj.ResourceAllocationType = param.ResourceAllocationType;

            if ~strcmp(param.DuplexMode, 'FDD')
                obj.DuplexMode = 1; % TDD
            end
            obj.SCS = param.SubcarrierSpacing;
            obj.SlotDuration = 1/(obj.SCS/15); % In ms
            obj.NumSlotsFrame = 10/obj.SlotDuration; % Number of slots in a 10 ms frame

            rbgSizeConfig = 1; % Set it to 1 or 2
            rbgSizeIndex = min(find(obj.NumResourceBlocks <= obj.NominalRBGSizePerBW(:, 1), 1));
            if rbgSizeConfig == 1
                obj.RBGSize = obj.NominalRBGSizePerBW(rbgSizeIndex, 2);
            else % RBGSizeConfig is 2
                obj.RBGSize = obj.NominalRBGSizePerBW(rbgSizeIndex, 3);
            end
            obj.NumRBGs = ceil(obj.NumResourceBlocks/obj.RBGSize);
            if obj.DuplexMode % TDD
                obj.NumDLULPatternSlots = param.DLULConfigTDD.DLULPeriodicity/obj.SlotDuration;
                obj.NumDLSlots = param.DLULConfigTDD.NumDLSlots;
                obj.NumULSlots = param.DLULConfigTDD.NumULSlots;
                obj.NumDLSymbols = param.DLULConfigTDD.NumDLSymbols;
                obj.NumULSymbols = param.DLULConfigTDD.NumULSymbols;

                % All the remaining symbols in DL-UL pattern are assumed to
                % be guard symbols
                obj.GuardDuration = (obj.NumDLULPatternSlots * 14) - ...
                    (((obj.NumDLSlots + obj.NumULSlots)*14) + ...
                    obj.NumDLSymbols + obj.NumULSymbols);

                % Set format of slots in the DL-UL pattern. Value 0, 1 and 2 means
                % symbol type as DL, UL and guard, respectively
                obj.DLULSlotFormat = obj.GuardType * ones(obj.NumDLULPatternSlots, 14);
                obj.DLULSlotFormat(1:obj.NumDLSlots, :) = obj.DLType; % Mark all the symbols of full DL slots as DL
                obj.DLULSlotFormat(obj.NumDLSlots + 1, 1 : obj.NumDLSymbols) = obj.DLType; % Mark DL symbols following the full DL slots
                obj.DLULSlotFormat(obj.NumDLSlots + floor(obj.GuardDuration/14) + 1, (obj.NumDLSymbols + mod(obj.GuardDuration, 14) + 1) : end)  ...
                    = obj.ULType; % Mark UL symbols at the end of slot before full UL slots
                obj.DLULSlotFormat((end - obj.NumULSlots + 1):end, :) = obj.ULType; % Mark all the symbols of full UL slots as UL type

                % Get the first slot with UL symbols
                slotNum = 0;
                while slotNum < obj.NumSlotsFrame && slotNum < obj.NumDLULPatternSlots
                    if find(obj.DLULSlotFormat(slotNum + 1, :) == obj.ULType, 1)
                        break; % Found a slot with UL symbols
                    end
                    slotNum = slotNum + 1;
                end

                obj.NextULSchedulingSlot = slotNum; % Set the first slot to be scheduled by UL scheduler
            else % FDD
                if isfield(param, 'SchedulerPeriodicity')
                    % Number of slots in a frame
                    numSlotsFrame = 10 *(obj.SCS / 15);
                    validateattributes(param.SchedulerPeriodicity, {'numeric'}, {'nonempty', ...
                        'integer', 'scalar', '>', 0, '<=', numSlotsFrame}, 'param.SchedulerPeriodicity', ...
                        'SchedulerPeriodicity');
                    obj.SchedulerPeriodicity = param.SchedulerPeriodicity;
                end
                % Initialization to make sure that schedulers run in the
                % very first slot of simulation run
                obj.SlotsSinceSchedulerRunDL = obj.SchedulerPeriodicity - 1;
                obj.SlotsSinceSchedulerRunUL = obj.SchedulerPeriodicity - 1;
            end

            if isfield(param, 'PUSCHPrepTime')
                validateattributes(param.PUSCHPrepTime, {'numeric'}, ...
                    {'nonempty', 'integer', 'scalar', 'finite', '>=', 0}, ...
                    'param.PUSCHPrepTime', 'PUSCHPrepTime');
                obj.PUSCHPrepSymDur = ceil(param.PUSCHPrepTime/((obj.SlotDuration*1000)/14));
            else
                % Default value is 100 microseconds
                obj.PUSCHPrepSymDur = ceil(100/((obj.SlotDuration*1000)/14));
            end

            if isfield(param, 'SchedulingType')
                obj.SchedulingType = param.SchedulingType;
            end
            if obj.SchedulingType % Symbol based scheduling
                % Set TTI granularity
                if isfield(param, 'TTIGranularity')
                    obj.TTIGranularity = param.TTIGranularity;
                end
            end

            if isfield(param, 'RBAllocationLimitUL')
                validateattributes(param.RBAllocationLimitUL, {'numeric'}, ...
                    {'nonempty', 'integer', 'scalar', '>=', 1, '<=',obj.NumResourceBlocks},...
                    'param.RBAllocationLimitUL', 'RBAllocationLimitUL');
                obj.RBAllocationLimitUL = param.RBAllocationLimitUL;
            else
                % Set RB limit to half of the total number of RBs
                obj.RBAllocationLimitUL = obj.NumResourceBlocks;
            end

            if isfield(param, 'RBAllocationLimitDL')
                validateattributes(param.RBAllocationLimitDL, {'numeric'}, ...
                    {'nonempty', 'integer', 'scalar', '>=', 1, '<=',obj.NumResourceBlocks},...
                    'param.RBAllocationLimitDL', 'RBAllocationLimitDL');
                obj.RBAllocationLimitDL = param.RBAllocationLimitDL;
            else
                % Set RB limit to half of the total number of RBs
                obj.RBAllocationLimitDL = obj.NumResourceBlocks;
            end

            if isfield(param, 'SSBIndex')
                validateattributes(param.SSBIndex, {'numeric'}, ...
                    {'nonempty', 'integer', 'numel', param.NumUEs},...
                    'param.SSBIndex', 'SSBIndex')
                obj.SSBIdx = param.SSBIndex; % SSB associated with each UE
            end

            % Number of CSI-RS beams available for beam refinement with each SSB's angular range
            if isfield(param, 'NumCSIRSBeams')
                obj.NumCSIRSBeams = param.NumCSIRSBeams;
            end

            if isfield(param, 'BeamWeightTable')
                obj.BeamWeightTable = param.BeamWeightTable;
            end

            % Store the CQI tables as matrices
            obj.CQITableUL = nr5g.internal.MACConstants.CQITable;
            obj.CQITableDL = nr5g.internal.MACConstants.CQITable;

            % Context initialization for HARQ processes
            if isfield(param, 'NumHARQ')
                obj.NumHARQ = param.NumHARQ;
            end

            if isfield(param, 'DMRSTypeAPosition')
                obj.DMRSTypeAPosition = param.DMRSTypeAPosition;
            end

            % PUSCH DM-RS configuration
            if isfield(param, 'PUSCHDMRSConfigurationType')
                obj.PUSCHDMRSConfigurationType = param.PUSCHDMRSConfigurationType;
            end
            if isfield(param, 'PUSCHMappingType')
                obj.PUSCHMappingType = param.PUSCHMappingType;
            end
            if isfield(param, 'PUSCHDMRSLength')
                obj.PUSCHDMRSLength = param.PUSCHDMRSLength;
            end
            if isfield(param, 'PUSCHDMRSAdditionalPosTypeA')
                obj.PUSCHDMRSAdditionalPosTypeA = param.PUSCHDMRSAdditionalPosTypeA;
            end
            if isfield(param, 'PUSCHDMRSAdditionalPosTypeB')
                obj.PUSCHDMRSAdditionalPosTypeB = param.PUSCHDMRSAdditionalPosTypeB;
            end

            % PDSCH DM-RS configuration
            if isfield(param, 'PDSCHDMRSConfigurationType')
                obj.PDSCHDMRSConfigurationType = param.PDSCHDMRSConfigurationType;
            end
            if isfield(param, 'PDSCHMappingType')
                obj.PDSCHMappingType = param.PDSCHMappingType;
            end
            if isfield(param, 'PDSCHDMRSLength')
                obj.PDSCHDMRSLength = param.PDSCHDMRSLength;
            end
            if isfield(param, 'PDSCHDMRSAdditionalPosTypeA')
                obj.PDSCHDMRSAdditionalPosTypeA = param.PDSCHDMRSAdditionalPosTypeA;
            end
            if isfield(param, 'PDSCHDMRSAdditionalPosTypeB')
                obj.PDSCHDMRSAdditionalPosTypeB = param.PDSCHDMRSAdditionalPosTypeB;
            end
            % Set the MCS tables as matrices
            obj.MCSTableUL = nr5g.internal.MACConstants.MCSTable;
            obj.MCSTableDL = nr5g.internal.MACConstants.MCSTable;

            % Reserve UL resource for SRS
            obj.ULReservedResource = param.SRSReservedResource;

            % Create carrier configuration object for UL
            obj.CarrierConfigUL = nrCarrierConfig;
            obj.CarrierConfigUL.SubcarrierSpacing = obj.SCS;
            obj.CarrierConfigUL.NSizeGrid = obj.NumResourceBlocks;
            % Create carrier configuration object for DL
            obj.CarrierConfigDL = obj.CarrierConfigUL;
            obj.CarrierConfigDL.NSizeGrid = obj.NumResourceBlocks;

            % Create PUSCH and PDSCH configuration objects and use them to
            % optimize performance
            obj.PUSCHConfig = nrPUSCHConfig;
            obj.PUSCHConfig.DMRS = nrPUSCHDMRSConfig('DMRSConfigurationType', obj.PUSCHDMRSConfigurationType, ...
                'DMRSTypeAPosition', obj.DMRSTypeAPosition, 'DMRSLength', obj.PUSCHDMRSLength);
            obj.PDSCHConfig = nrPDSCHConfig;
            obj.PDSCHConfig.DMRS = nrPDSCHDMRSConfig('DMRSConfigurationType', obj.PDSCHDMRSConfigurationType, ...
                'DMRSTypeAPosition', obj.DMRSTypeAPosition, 'DMRSLength', obj.PDSCHDMRSLength);

            % Set the maximum users that can be scheduled per TTI
            obj.MaxNumUsersPerTTI = param.MaxNumUsersPerTTI;

            % Set the MCS index that will be used to allocate DL and UL
            % resources irrespective of channel condition
            obj.FixedMCSIndexDL = param.FixedMCSIndexDL;
            obj.FixedMCSIndexUL = param.FixedMCSIndexUL;

            % Set MU-MIMO related parameters
            obj.MUMIMOConfigDL = param.MUMIMOConfigDL;
        end

        function addConnectionContext(obj, connectionConfig)
            %addConnectionContext Configures the scheduler with UE connection information

            obj.UEs = [obj.UEs connectionConfig.RNTI];
            nodeInfo = struct('ID', connectionConfig.UEID, 'Name', connectionConfig.UEName);
            obj.UEInfo = [obj.UEInfo nodeInfo];
            obj.NumTransmitAntennasUE = [obj.NumTransmitAntennasUE connectionConfig.NumTransmitAntennas];
            obj.NumReceiveAntennasUE = [obj.NumReceiveAntennasUE connectionConfig.NumReceiveAntennas];
            obj.BufferStatusDL = [obj.BufferStatusDL; zeros(1, 32)]; % 32 logical channels
            obj.BufferStatusUL = [obj.BufferStatusUL; zeros(1, 8)]; % 8 logical channel groups
            obj.BufferStatusDLPerUE = [obj.BufferStatusDLPerUE; 0];
            obj.BufferStatusULPerUE = [obj.BufferStatusULPerUE; 0];

            harqProcess.RVSequence = obj.RVSequence;
            ncw = 1; % Only single codeword
            harqProcess.ncw = ncw; % Set number of codewords
            harqProcess.blkerr = zeros(1, ncw); % Initialize block errors
            harqProcess.RVIdx = ones(1, ncw);  % Add RVIdx to process
            harqProcess.RV = harqProcess.RVSequence(ones(1,ncw));
            % Create HARQ processes context array for each UE
            obj.HarqProcessesUL = [obj.HarqProcessesUL; repmat(harqProcess, 1, obj.NumHARQ)];
            obj.HarqProcessesDL = [obj.HarqProcessesDL; repmat(harqProcess, 1, obj.NumHARQ)];

            obj.HarqProcessesUL(end,:) = nr5g.internal.nrNewHARQProcesses(obj.NumHARQ, harqProcess.RVSequence, ncw);
            obj.HarqProcessesDL(end,:) = nr5g.internal.nrNewHARQProcesses(obj.NumHARQ, harqProcess.RVSequence, ncw);

            % Initialize HARQ status and NDI
            obj.HarqStatusUL = [obj.HarqStatusUL; cell(1, obj.NumHARQ)];
            obj.HarqStatusDL = [obj.HarqStatusDL; cell(1, obj.NumHARQ)];
            obj.HarqNDIUL = [obj.HarqNDIUL; false(1, obj.NumHARQ)];
            obj.HarqNDIDL = [obj.HarqNDIDL; false(1, obj.NumHARQ)];

            % Create retransmission context
            obj.RetransmissionContextUL = [obj.RetransmissionContextUL; cell(1, obj.NumHARQ)];
            obj.RetransmissionContextDL = [obj.RetransmissionContextDL; cell(1, obj.NumHARQ)];

            obj.TBSizeDL = [obj.TBSizeDL; zeros(1, obj.NumHARQ)];
            obj.TBSizeUL = [obj.TBSizeUL; zeros(1, obj.NumHARQ)];

            if ~isempty(connectionConfig.SRSConfiguration)
                obj.NumSRSPorts = [obj.NumSRSPorts; connectionConfig.SRSConfiguration.NumSRSPorts];
            else
                obj.NumSRSPorts = [obj.NumSRSPorts; connectionConfig.NumTransmitAntennas];
            end

            % Set CSI-RS ports
            if ~isempty(connectionConfig.CSIRSConfiguration)
                obj.NumCSIRSPorts =[obj.NumCSIRSPorts; connectionConfig.CSIRSConfiguration.NumCSIRSPorts];
                obj.XOverheadPDSCH = 18;
            else
                obj.NumCSIRSPorts =[obj.NumCSIRSPorts; obj.NumTransmitAntennas];
            end

            % CSI measurements initialization
            obj.CSIMeasurementDL = [obj.CSIMeasurementDL; struct('RankIndicator', [], 'PMISet', [], 'CQI', [], 'CSIResourceIndicator', [], 'L1RSRP', [], 'W', [])];
            obj.CSIMeasurementUL = [obj.CSIMeasurementUL; struct('RankIndicator', [], 'TPMI', [], 'CQI', [])];
            initialRank = 1; % Initial ranks for UEs
            obj.CSIMeasurementDL(connectionConfig.RNTI).RankIndicator = initialRank;
            obj.CSIMeasurementUL(connectionConfig.RNTI).RankIndicator = initialRank;
            obj.CSIMeasurementDL(connectionConfig.RNTI).PMISet.i1 = [1 1 1];
            obj.CSIMeasurementDL(connectionConfig.RNTI).PMISet.i2 = 1;
            obj.CSIMeasurementDL(connectionConfig.RNTI).W = ones(obj.NumCSIRSPorts(connectionConfig.RNTI), 1) ...
                ./sqrt(obj.NumCSIRSPorts(connectionConfig.RNTI));
            if isempty(connectionConfig.SRSSubbandSize)
                connectionConfig.SRSSubbandSize = 4;
            else
                validateattributes(connectionConfig.SRSSubbandSize, {'numeric'},...
                    {'scalar', 'integer', '>', 0, '<=', obj.NumResourceBlocks}, 'connectionConfig.SRSSubbandSize', 'SRSSubbandSize');
            end
            numSRSSubbands = ceil(obj.NumResourceBlocks/connectionConfig.SRSSubbandSize);
            obj.CSIMeasurementUL(end).TPMI = zeros(numSRSSubbands,1);
            % Initialize DL and UL channel quality as CQI index 7
            obj.CSIMeasurementDL(connectionConfig.RNTI).CQI = connectionConfig.InitialCQIDL*ones(1, obj.NumResourceBlocks);
            obj.CSIMeasurementUL(connectionConfig.RNTI).CQI = connectionConfig.InitialCQIUL*ones(1, obj.NumResourceBlocks);
        end

        function resourceAssignments = runDLScheduler(obj, currentTimeInfo)
            %runDLScheduler Run the DL scheduler
            %
            %   RESOURCEASSIGNMENTS = runDLScheduler(OBJ, CURRENTTIMEINFO)
            %   runs the DL scheduler and returns the resource assignments
            %   structure array.
            %
            %   CURRENTTIMEINFO is the information passed to scheduler for
            %   scheduling. It is a structure with following fields:
            %       SFN - Current system frame number
            %       Slot - Current slot number
            %       Symbol - Current symbol number
            %
            %   RESOURCEASSIGNMENTS is a structure that contains the
            %   DL resource assignments information.

            % Set current time information before doing the scheduling
            obj.CurrSlot = currentTimeInfo.Slot;
            obj.CurrSymbol = currentTimeInfo.Symbol;
            obj.SFN = currentTimeInfo.SFN;
            if obj.DuplexMode % TDD
                % Calculate DL-UL slot index in the DL-UL pattern
                obj.CurrDLULSlotIndex = mod(obj.SFN*obj.NumSlotsFrame + obj.CurrSlot, obj.NumDLULPatternSlots);
            end

            % Select the slots to be scheduled and then schedule them
            resourceAssignments = {};
            numDLGrants = 0;
            slotsToBeScheduled = selectDLSlotsToBeScheduled(obj);
            for i=1:length(slotsToBeScheduled)
                % Schedule each selected slot
                slotDLGrants = scheduleDLResourcesSlot(obj, slotsToBeScheduled(i));
                resourceAssignments(numDLGrants + 1 : numDLGrants + length(slotDLGrants)) = slotDLGrants(:);
                numDLGrants = numDLGrants + length(slotDLGrants);
                updateHARQContextDL(obj, slotDLGrants);
                updateBufferStatusForGrants(obj, 0, slotDLGrants);
            end
        end

        function resourceAssignments = runULScheduler(obj, currentTimeInfo)
            %runULScheduler Run the UL scheduler
            %
            %   RESOURCEASSIGNMENTS = runULScheduler(OBJ, CURRENTTIMEINFO)
            %   runs the UL scheduler and returns the resource assignments
            %   structure array.
            %
            %   CURRENTTIMEINFO is the information passed to scheduler for
            %   scheduling. It is a structure with following fields:
            %       SFN - Current system frame number
            %       Slot - Current slot number
            %       Symbol - Current symbol number
            %
            %   RESOURCEASSIGNMENTS is a structure that contains the
            %   UL resource assignments information.

            %Set current time information before doing the scheduling
            obj.CurrSlot = currentTimeInfo.Slot;
            obj.CurrSymbol = currentTimeInfo.Symbol;
            obj.SFN = currentTimeInfo.SFN;
            if obj.DuplexMode % TDD
                % Calculate current DL-UL slot index in the DL-UL pattern
                obj.CurrDLULSlotIndex = mod(obj.SFN*obj.NumSlotsFrame + obj.CurrSlot, obj.NumDLULPatternSlots);
            end

            % Select the slots to be scheduled now and schedule them
            resourceAssignments = {};
            numULGrants = 0;
            slotsToBeSched = selectULSlotsToBeScheduled(obj); % Select the set of slots to be scheduled in this UL scheduler run
            for i=1:length(slotsToBeSched)

                % Schedule each selected slot
                slotULGrants = scheduleULResourcesSlot(obj, slotsToBeSched(i));
                resourceAssignments(numULGrants + 1 : numULGrants + length(slotULGrants)) = slotULGrants(:);
                numULGrants = numULGrants + length(slotULGrants);
                updateHARQContextUL(obj, slotULGrants);
                updateBufferStatusForGrants(obj, 1, slotULGrants);
            end

            if obj.DuplexMode % TDD
                % Update the next to-be-scheduled UL slot. Next UL
                % scheduler run starts assigning resources this slot
                % onwards
                if ~isempty(slotsToBeSched)
                    % If any UL slots are scheduled, set the next
                    % to-be-scheduled UL slot as the next UL slot after
                    % last scheduled UL slot
                    lastSchedULSlot = slotsToBeSched(end);
                    obj.NextULSchedulingSlot = getToBeSchedULSlotNextRun(obj, lastSchedULSlot);
                end
            end
        end

        function updateLCBufferStatusDL(obj, lcBufferStatus)
            %updateLCBufferStatusDL Update DL buffer status for a logical channel of the specified UE
            %
            %   updateLCBufferStatusDL(obj, LCBUFFERSTATUS) updates the
            %   DL buffer status for a logical channel of the specified UE.
            %
            %   LCBUFFERSTATUS is a structure with following three fields.
            %       RNTI - RNTI of the UE
            %       LogicalChannelID - Logical channel ID
            %       BufferStatus - Pending amount in bytes for the specified logical channel of UE

            obj.BufferStatusDL(lcBufferStatus.RNTI, lcBufferStatus.LogicalChannelID) = lcBufferStatus.BufferStatus;
            % Calculate the cumulative sum of all the logical channels
            % pending buffer amount for a specific UE
            obj.BufferStatusDLPerUE(lcBufferStatus.RNTI) = sum(obj.BufferStatusDL(lcBufferStatus.RNTI, :), 2);
        end

        function processMACControlElement(obj, macCEInfo, varargin)
            %processMACControlElement Process the received MAC control element
            %
            %   processMACControlElement(OBJ, MACCEINFO) processes the
            %   received MAC control element (CE). This interface currently
            %   supports buffer status report (BSR) only.
            %
            %   processMACControlElement(OBJ, MACCEINFO, LCGPRIORITY) processes the
            %   received MAC control element (CE). This interface currently
            %   supports long truncated buffer status report (BSR) only.
            %
            %   MACCEINFO is a structure with following fields.
            %       RNTI - RNTI of the UE which sent the MAC CE
            %       LCID - Logical channel ID of the MAC CE
            %       Packet - MAC CE
            %
            %   LCGPRIORITY is a vector of priorities of all the LCGs of UE
            %   with rnti value RNTI, used for processing long truncated
            %   BSR

            % Values 59, 60, 61, 62 represents LCIDs corresponding to
            % different BSR formats as per 3GPP TS 38.321
            if(macCEInfo.LCID == 59 || macCEInfo.LCID == 60 || macCEInfo.LCID == 61 || macCEInfo.LCID == 62)
                [lcgIDList, bufferSizeList] = nrMACBSRDecode(macCEInfo.LCID, macCEInfo.Packet);
                % When buffer size is not 0 for the logical channel groups
                % but the BSR is long truncated BSR, map the lcgIDList
                % values to bufferSizeList values using priority and then
                % set the buffer status context
                if macCEInfo.LCID == 60
                    [~, priorityOrder] = sort(varargin{1}(lcgIDList+1));
                    lcgIDList = lcgIDList(priorityOrder);
                    numBufferSizeLCGs = size(bufferSizeList,1);
                    obj.BufferStatusUL(macCEInfo.RNTI, lcgIDList(1:numBufferSizeLCGs)+1) = bufferSizeList(:,2);
                    ulcgIDList = lcgIDList(numBufferSizeLCGs+1:end); % LCGs with unreported data

                    % Check whether the buffer status is zero for LCGs with unreported data
                    Idx = find(obj.BufferStatusUL(macCEInfo.RNTI, ulcgIDList+1) == 0);

                    % For LCGs having data and are not reported, assume the
                    % buffer size of 10 bytes which is the first non zero
                    % entry in 3GPP TS 38.321 Table 6.1.3.1-2
                    if ~isempty(Idx)
                        obj.BufferStatusUL(macCEInfo.RNTI, ulcgIDList(Idx)+1) = 10;
                    end

                    % When buffer size is 0 for the logical channel groups
                    % in the BSR packet, set the buffer status context of
                    % all logical channel groups to 0 by considering that
                    % no logical channel group has data for transmission
                elseif isempty(bufferSizeList) || bufferSizeList(2) == 0
                    obj.BufferStatusUL(macCEInfo.RNTI, :) = 0;
                else
                    obj.BufferStatusUL(macCEInfo.RNTI, lcgIDList+1) = bufferSizeList(:,2);
                end
                % Calculate the cumulative sum of all LCG's pending buffer
                % amount for a specific UE
                obj.BufferStatusULPerUE(macCEInfo.RNTI) = sum(obj.BufferStatusUL(macCEInfo.RNTI, :), 2);
            end
        end

        function updateChannelQualityUL(obj, channelQualityInfo)
            %updateChannelQualityUL Update uplink channel quality information for a UE
            %   UPDATECHANNELQUALITYUL(OBJ, CHANNELQUALITYINFO) updates
            %   uplink (UL) channel quality information for a UE.
            %   CHANNELQUALITYINFO is a structure with following fields.
            %       RNTI - RNTI of the UE
            %       RankIndicator - Rank indicator for the UE
            %       TPMI - Measured transmitted precoded matrix indicator (TPMI)
            %       CQI - CQI corresponding to RANK and TPMI. It is a
            %       vector of size 'N', where 'N' is number of RBs in UL
            %       bandwidth. Value at index 'i' represents CQI value at
            %       RB-index 'i'

            obj.CSIMeasurementUL(channelQualityInfo.RNTI).CQI = channelQualityInfo.CQI;
            if isfield(channelQualityInfo, 'TPMI')
                obj.CSIMeasurementUL(channelQualityInfo.RNTI).TPMI = channelQualityInfo.TPMI;
            end
            if isfield(channelQualityInfo, 'RankIndicator')
                obj.CSIMeasurementUL(channelQualityInfo.RNTI).RankIndicator = channelQualityInfo.RankIndicator;
            end
        end

        function updateChannelQualityDL(obj, channelQualityInfo)
            %updateChannelQualityDL Update downlink channel quality information for a UE
            %   UPDATECHANNELQUALITYDL(OBJ, CHANNELQUALITYINFO) updates
            %   downlink (DL) channel quality information for a UE.
            %   CHANNELQUALITYINFO is a structure with following fields for RI, PMI & CQI measurements.
            %       RNTI - RNTI of the UE
            %       RankIndicator - Rank indicator for the UE
            %       PMISet - Precoding matrix indicator. It is a structure with following fields.
            %           i1 - Indicates wideband PMI (1-based). It a three-element vector in the
            %                form of [i11 i12 i13].
            %           i2 - Indicates subband PMI (1-based). It is a vector of length equal to
            %                the number of subbands or number of PRGs.
            %       CQI - CQI corresponding to RANK and TPMI. It is a
            %       vector of size 'N', where 'N' is number of RBs in UL
            %       bandwidth. Value at index 'i' represents CQI value at
            %       RB-index 'i'
            %   For CRI, L1-RSRP measurements the structure has these fields
            %       CRI    - CSI-RS Resource Indicator corresponding to the
            %                beam with the highest RSRP measurement
            %       L1RSRP - Highest L1-RSRP measurement among all the
            %                refined CSI-RS beam directions

            % If the CSI Report is of the format cri-rsrp
            if isfield(channelQualityInfo, 'CRI')
                obj.CSIMeasurementDL(channelQualityInfo.RNTI).CSIResourceIndicator = channelQualityInfo.CRI;
                obj.CSIMeasurementDL(channelQualityInfo.RNTI).L1RSRP = channelQualityInfo.L1RSRP;
            else
                % If the CSI Report is of the format ri-pmi-cqi
                obj.CSIMeasurementDL(channelQualityInfo.RNTI).CQI = channelQualityInfo.CQI;
                if isfield(channelQualityInfo, 'RankIndicator')
                    obj.CSIMeasurementDL(channelQualityInfo.RNTI).RankIndicator = channelQualityInfo.RankIndicator;
                end
                if isfield(channelQualityInfo, 'PMISet')
                    obj.CSIMeasurementDL(channelQualityInfo.RNTI).PMISet = channelQualityInfo.PMISet;
                end
                if isfield(channelQualityInfo, 'W')
                    obj.CSIMeasurementDL(channelQualityInfo.RNTI).W = channelQualityInfo.W;
                    if ~isempty(obj.MUMIMOConfigDL)
                        updateUserPairingMatrix(obj);
                    end
                end
            end
        end

        function handleDLRxResult(obj, rxResultInfo)
            %handleDLRxResult Update the HARQ process context based on the Rx success/failure for DL packets
            % handleDLRxResult(OBJ, RXRESULTINFO) updates the HARQ
            % process context, based on the ACK/NACK received by gNB for
            % the DL packet.
            %
            % RXRESULTINFO is a structure with following fields.
            %   RNTI - UE that sent the ACK/NACK for its DL reception.
            %
            %   HARQID - HARQ process ID
            %
            %   RxResult - 0 means NACK or no feedback received. 1 means ACK.

            rnti = rxResultInfo.RNTI;
            harqID = rxResultInfo.HARQID;
            if rxResultInfo.RxResult % Rx success
                % Update the DL HARQ process context
                obj.HarqStatusDL{rnti, harqID+1} = []; % Mark the HARQ process as free
                harqProcess = obj.HarqProcessesDL(rnti, harqID+1);
                harqProcess.blkerr(1) = 0;
                obj.HarqProcessesDL(rnti, harqID+1) = harqProcess;

                % Clear the retransmission context for the HARQ
                % process of the UE. It would already be empty if
                % this feedback was not for a retransmission.
                obj.RetransmissionContextDL{rnti, harqID+1}= [];
            else % Rx failure or no feedback received
                harqProcess = obj.HarqProcessesDL(rnti, harqID+1);
                harqProcess.blkerr(1) = 1;
                if harqProcess.RVIdx(1) == length(harqProcess.RVSequence)
                    % Packet reception failed for all redundancy
                    % versions. Mark the HARQ process as free. Also
                    % clear the retransmission context to not allow any
                    % further retransmissions for this packet
                    harqProcess.blkerr(1) = 0;
                    obj.HarqStatusDL{rnti, harqID+1} = []; % Mark the HARQ process as free
                    obj.HarqProcessesDL(rnti, harqID+1) = harqProcess;
                    obj.RetransmissionContextDL{rnti, harqID+1}= [];
                else
                    % Update the retransmission context for the UE
                    % and HARQ process to indicate retransmission
                    % requirement
                    obj.HarqProcessesDL(rnti, harqID+1) = harqProcess;
                    lastDLGrant = obj.HarqStatusDL{rnti, harqID+1};
                    if lastDLGrant.RV == 0 % Only store the original transmission grant's TBS
                        % Calculate grantRBs based on resource allocation type
                        if lastDLGrant.ResourceAllocationType % RAT-1
                            grantRBs = lastDLGrant.FrequencyAllocation(1):lastDLGrant.FrequencyAllocation(1) + ...
                                lastDLGrant.FrequencyAllocation(2) - 1;
                        else % RAT-0
                            grantRBs = convertRBGBitmapToRBs(obj, lastDLGrant.FrequencyAllocation);
                        end
                        mcsInfo = obj.MCSTableDL(lastDLGrant.MCS + 1, :);
                        modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme
                        modScheme = modSchemeStr(obj, modSchemeBits);
                        codeRate = mcsInfo(2)/1024;
                        % Calculate tbs capability of grant
                        lastTBS = floor(tbsCapability(obj, 0, lastDLGrant.NumLayers, lastDLGrant.MappingType, lastDLGrant.StartSymbol, ...
                            lastDLGrant.NumSymbols, grantRBs, modScheme, codeRate, lastDLGrant.NumCDMGroupsWithoutData)/8);
                        obj.TBSizeDL(rnti, harqID+1) = lastTBS;
                    end
                    obj.RetransmissionContextDL{rnti, harqID+1} = lastDLGrant;
                end
            end
        end

        function handleULRxResult(obj, rxResultInfo)
            %handleULRxResult Update the HARQ process context based on the Rx success/failure for UL packets
            % handleULRxResult(OBJ, RXRESULTINFO) updates the HARQ
            % process context, based on the reception success/failure of
            % UL packets.
            %
            % RXRESULTINFO is a structure with following fields.
            %   RNTI - UE corresponding to the UL packet.
            %
            %   HARQID - HARQ process ID.
            %
            %   RxResult - 0 means Rx failure or no reception. 1 means Rx success.

            rnti = rxResultInfo.RNTI;
            harqID = rxResultInfo.HARQID;
            rxResult = rxResultInfo.RxResult;

            if rxResult % Rx success
                % Update the HARQ process context
                obj.HarqStatusUL{rnti, harqID + 1} = []; % Mark HARQ process as free
                harqProcess = obj.HarqProcessesUL(rnti, harqID + 1);
                harqProcess.blkerr(1) = 0;
                obj.HarqProcessesUL(rnti, harqID+1) = harqProcess;

                % Clear the retransmission context for the HARQ process
                % of the UE. It would already be empty if this
                % reception was not a retransmission.
                obj.RetransmissionContextUL{rnti, harqID+1}= [];
            else % Rx failure or no packet received
                % No packet received (or corrupted) from UE although it
                % was scheduled to send. Store the transmission uplink
                % grant in retransmission context, which will be used
                % while assigning grant for retransmission
                harqProcess = obj.HarqProcessesUL(rnti, harqID+1);
                harqProcess.blkerr(1) = 1;
                if harqProcess.RVIdx(1) == length(harqProcess.RVSequence)
                    % Packet reception failed for all redundancy
                    % versions. Mark the HARQ process as free. Also
                    % clear the retransmission context to not allow any
                    % further retransmissions for this packet
                    harqProcess.blkerr(1) = 0;
                    obj.HarqStatusUL{rnti, harqID+1} = []; % Mark HARQ as free
                    obj.HarqProcessesUL(rnti, harqID+1) = harqProcess;
                    obj.RetransmissionContextUL{rnti, harqID+1}= [];
                else
                    obj.HarqProcessesUL(rnti, harqID+1) = harqProcess;
                    lastULGrant = obj.HarqStatusUL{rnti, harqID+1};
                    if lastULGrant.RV == 0 % Only store the original transmission grant TBS
                        % Calculate grantRBs based on resource allocation type
                        if lastULGrant.ResourceAllocationType % RAT-1
                            grantRBs = lastULGrant.FrequencyAllocation(1):lastULGrant.FrequencyAllocation(1) + ...
                                lastULGrant.FrequencyAllocation(2) - 1;
                        else % RAT-0
                            grantRBs = convertRBGBitmapToRBs(obj, lastULGrant.FrequencyAllocation);
                        end
                        mcsInfo = obj.MCSTableUL(lastULGrant.MCS + 1, :);
                        modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme
                        modScheme = modSchemeStr(obj, modSchemeBits);
                        codeRate = mcsInfo(2)/1024;
                        % Calculate tbs capability of grant
                        lastTBS = floor(tbsCapability(obj, 1, lastULGrant.NumLayers, lastULGrant.MappingType, lastULGrant.StartSymbol, ...
                            lastULGrant.NumSymbols, grantRBs, modScheme, codeRate, lastULGrant.NumCDMGroupsWithoutData)/8);
                        obj.TBSizeUL(rnti, harqID+1) = lastTBS;
                    end
                    obj.RetransmissionContextUL{rnti, harqID+1} = lastULGrant;
                end
            end
        end
    end

    methods (Access = protected)
        function selectedSlots = selectULSlotsToBeScheduled(obj)
            %selectULSlotsToBeScheduled Select UL slots to be scheduled
            % SELECTEDSLOTS = selectULSlotsToBeScheduled(OBJ) selects the
            % slots to be scheduled by UL scheduler in the current run. The
            % time of current scheduler run is inferred from the values of
            % object properties: SFN, CurrSlot and CurrSymbol.
            %
            % SELECTEDSLOTS is the array of slot numbers selected for
            % scheduling in the current invocation of UL scheduler by MAC

            if ~obj.DuplexMode % FDD
                selectedSlots = selectULSlotsToBeScheduledFDD(obj);
            else % TDD
                selectedSlots = selectULSlotsToBeScheduledTDD(obj);
            end
        end

        function selectedSlots = selectDLSlotsToBeScheduled(obj)
            %selectDLSlotsToBeScheduled Select DL slots to be scheduled
            % SELECTEDSLOTS = selectDLSlotsToBeScheduled(OBJ) selects the
            % slots to be scheduled by DL scheduler in the current run. The
            % time of current scheduler run is inferred from the values of
            % object properties: SFN, CurrSlot and CurrSymbol.
            %
            % SELECTEDSLOTS is the array of slot numbers selected for
            % scheduling in the current invocation of DL scheduler by MAC

            if ~obj.DuplexMode % FDD
                selectedSlots = selectDLSlotsToBeScheduledFDD(obj);
            else % TDD
                selectedSlots = selectDLSlotsToBeScheduledTDD(obj);
            end
        end

        function uplinkGrants = scheduleULResourcesSlot(obj, slotNum)
            %scheduleULResourcesSlot Schedule UL resources of a slot
            %   UPLINKGRANTS = scheduleULResourcesSlot(OBJ, SLOTNUM)
            %   assigns UL resources of the slot, SLOTNUM. Based on the UL
            %   assignment done, it also updates the UL HARQ process
            %   context.
            %
            %   SLOTNUM is the slot number in the 10 ms frame whose UL
            %   resources are getting scheduled. For FDD, all the symbols
            %   can be used for UL. For TDD, the UL resources can stretch
            %   the full slot or might just be limited to few symbols in
            %   the slot.
            %   The time of current scheduler run is inferred
            %   from the value of object properties: SFN, CurrSlot and
            %   CurrSymbol.
            %
            %   UPLINKGRANTS is a cell array where each cell-element
            %   represents an uplink grant and has following fields:
            %       RNTI                - Uplink grant is for this UE
            %       Type                - Whether assignment is for new transmission ('newTx'),
            %                             retransmission ('reTx')
            %       HARQID              - Selected uplink HARQ process ID
            %       FrequencyAllocation - For RAT-0, a bitmap of resource-block-groups of the PUSCH bandwidth.
            %                             Value 1 indicates RBG is assigned to the UE
            %                           - For RAT-1, a vector of two elements representing start RB and
            %                             number of RBs
            %       StartSymbol         - Start symbol of time-domain resources
            %       NumSymbols          - Number of symbols allotted in time-domain
            %       SlotOffset          - Slot-offset of PUSCH assignment
            %                             w.r.t the current slot
            %       MCS                 - Selected modulation and coding scheme index for UE with
            %                           - respect to the resource assignment done
            %       NDI                 - New data indicator flag
            %       DMRSLength          - DM-RS length
            %       MappingType         - Mapping type
            %       NumLayers           - Number of layers
            %       NumAntennaPorts     - Number of antenna ports
            %       TPMI                - Transmitted precoding matrix indicator
            %       NumCDMGroupsWithoutData  -  Number of DM-RS code division multiplexing (CDM) groups without data

            % Calculate offset of the slot to be scheduled, from the current
            % slot
            slotOffset = slotNum - obj.CurrSlot;
            if slotNum < obj.CurrSlot % Slot to be scheduled is in the next frame
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Get start UL symbol and number of UL symbols in the slot
            if obj.DuplexMode % TDD
                DLULPatternIndex = mod(obj.CurrDLULSlotIndex + slotOffset, obj.NumDLULPatternSlots);
                slotFormat = obj.DLULSlotFormat(DLULPatternIndex + 1, :);
                firstULSym = find(slotFormat == obj.ULType, 1, 'first') - 1; % Index of first UL symbol in the slot
                lastULSym = find(slotFormat == obj.ULType, 1, 'last') - 1; % Index of last UL symbol in the slot
                numULSym = lastULSym - firstULSym + 1;
            else % FDD
                % All symbols are UL symbols
                firstULSym = 0;
                numULSym = 14;
            end

            % Check if the current slot has any reserved symbol for SRS
            for i=1:size(obj.ULReservedResource, 1)
                numSlotFrames = 10*(obj.SCS/15); % Number of slots per 10ms frame
                reservedResourceInfo = obj.ULReservedResource(i, :);
                if (mod(numSlotFrames*obj.SFN + slotNum - reservedResourceInfo(3), reservedResourceInfo(2)) == 0) % SRS slot check
                    reservedSymbol = reservedResourceInfo(1);
                    if (reservedSymbol >= firstULSym) && (reservedSymbol <= firstULSym+numULSym-1)
                        numULSym = reservedSymbol - firstULSym; % Allow PUSCH to only span till the symbol before the SRS symbol
                    end
                    break; % Only 1 symbol for SRS per slot
                end
            end
            if obj.SchedulingType == 0 % Slot based scheduling
                if obj.PUSCHMappingType =='A' && (firstULSym~=0 || numULSym<4)
                    % PUSCH Mapping type A transmissions always start at symbol 0 and
                    % number of symbols must be >=4, as per TS 38.214 - Table 6.1.2.1-1
                    uplinkGrants = [];
                    return;
                end
                % Assignments to span all the symbols in the slot
                uplinkGrants = assignULResourceTTI(obj, slotNum, firstULSym, numULSym);

            else % Symbol based scheduling
                numTTIs = floor(numULSym / obj.TTIGranularity); % UL TTIs in the slot

                % UL grant array with maximum size to store grants
                uplinkGrants = cell((ceil(14/obj.TTIGranularity) * length(obj.UEs)), 1);
                numULGrants = 0;

                % Schedule all UL TTIs in the slot one-by-one
                startSym = firstULSym;
                for i = 1 : numTTIs
                    ttiULGrants = assignULResourceTTI(obj, slotNum, startSym, obj.TTIGranularity);
                    uplinkGrants(numULGrants + 1 : numULGrants + length(ttiULGrants)) = ttiULGrants(:);
                    numULGrants = numULGrants + length(ttiULGrants);
                    startSym = startSym + obj.TTIGranularity;
                end

                remULSym = mod(numULSym, obj.TTIGranularity); % Remaining unscheduled UL symbols
                % Schedule the remaining unscheduled UL symbols
                if remULSym >= 1 % Minimum PUSCH granularity is 1 symbol
                    ttiULGrants = assignULResourceTTI(obj, slotNum, startSym, remULSym);
                    uplinkGrants(numULGrants + 1 : numULGrants + length(ttiULGrants)) = ttiULGrants(:);
                    numULGrants = numULGrants + length(ttiULGrants);
                end
                uplinkGrants = uplinkGrants(1 : numULGrants);
            end
        end

        function downlinkGrants = scheduleDLResourcesSlot(obj, slotNum)
            %scheduleDLResourcesSlot Schedule DL resources of a slot
            %   DOWNLINKGRANTS = scheduleDLResourcesSlot(OBJ, SLOTNUM)
            %   assigns DL resources of the slot, SLOTNUM. Based on the DL
            %   ---------------> %%CHECK HERE: CAN WE USE THIS SLOTNUM FOR DELAY
            % 
            %   assignment done, it also updates the DL HARQ process
            %   context.
            %
            %   SLOTNUM is the slot number in the 10 ms frame whose DL
            %   resources are getting scheduled. For FDD, all the symbols
            %   can be used for DL. For TDD, the DL resources can stretch
            %   the full slot or might just be limited to few symbols in
            %   the slot.
            %   The time of current scheduler run is inferred
            %   from the value of object properties: SFN, CurrSlot and
            %   CurrSymbol.
            %
            %   DOWNLINKGRANTS is a cell array where each cell-element
            %   represents a downlink grant and has following fields:
            %
            %       RNTI               - Downlink grant is for this UE
            %       Type                 Whether assignment is for new transmission ('newTx'),
            %                            retransmission ('reTx')
            %       HARQID             - Selected downlink HARQ process ID
            %       FrequencyAllocation - For RAT-0, a bitmap of resource-block-groups of the PDSCH bandwidth.
            %                             Value 1 indicates RBG is assigned to the UE
            %                           - For RAT-1, a vector of two elements representing start RB and
            %                             number of RBs
            %       StartSymbol         - Start symbol of time-domain resources
            %       NumSymbols          - Number of symbols allotted in time-domain
            %       SlotOffset          - Slot offset of PDSCH assignment
            %                             w.r.t the current slot
            %       MCS                 - Selected modulation and coding scheme for UE with
            %                             respect to the resource assignment done
            %       NDI                 - New data indicator flag
            %       FeedbackSlotOffset  - Slot offset of PDSCH ACK/NACK from
            %                             PDSCH transmission slot (i.e. k1).
            %                             Currently, only a value >=2 is supported
            %       DMRSLength          - DM-RS length
            %       MappingType         - Mapping type
            %       NumLayers           - Number of transmission layers
            %       NumCDMGroupsWithoutData - Number of CDM groups without data (1...3)
            %
            %       PrecodingMatrix - Selected precoding matrix.
            %                         It is an array of size NumLayers-by-P-by-NPRG, where NPRG is the
            %                         number of PRGs in the carrier and P is the number of CSI-RS
            %                         ports. It defines a different precoding matrix of size
            %                         NumLayers-by-P for each PRG. The effective PRG bundle size
            %                         (precoder granularity) is Pd_BWP = ceil(NRB / NPRG).
            %                         For SISO, set it to 1
            %       BeamIndex       - Index in the beam weight table configured at PHY. If empty, no
            %                         beamforming is performed on the PDSCH transmission.

            % Calculate offset of the slot to be scheduled, from the current slot
            slotOffset = slotNum - obj.CurrSlot; %%CHECK HERE: CAN WE USE THIS OFFSET FOR DELAY
            if slotNum < obj.CurrSlot % Slot to be scheduled is in the next frame
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Get start DL symbol and number of DL symbols in the slot
            if obj.DuplexMode % TDD mode
                DLULPatternIndex = mod(obj.CurrDLULSlotIndex + slotOffset, obj.NumDLULPatternSlots);
                slotFormat = obj.DLULSlotFormat(DLULPatternIndex + 1, :);
                firstDLSym = find(slotFormat == obj.DLType, 1, 'first') - 1; % Location of first DL symbol in the slot
                lastDLSym = find(slotFormat == obj.DLType, 1, 'last') - 1; % Location of last DL symbol in the slot
                numDLSym = lastDLSym - firstDLSym + 1;
            else
                % For FDD, all symbols are DL symbols
                firstDLSym = 0;
                numDLSym = 14;
            end

            if obj.SchedulingType == 0  % Slot based scheduling
                % Assignments to span all the symbols in the slot
                downlinkGrants = assignDLResourceTTI(obj, slotNum, firstDLSym, numDLSym); %%CHECK HERE: CAN WE CHANGE FIRSTDLSYM AND NUMDLSYM TO SET OFFSET 
            else % Symbol based scheduling
                if numDLSym < 2 % PDSCH requires minimum 2 symbols with mapping type B as per TS 38.214 - Table 5.1.2.1-1
                    downlinkGrants = [];
                    return; % Not enough symbols for minimum TTI granularity
                end
                numTTIs = floor(numDLSym / obj.TTIGranularity); % DL TTIs in the slot

                % DL grant array with maximum size to store grants. Maximum
                % grants possible in a slot is the product of number of
                % TTIs in slot and number of UEs
                downlinkGrants = cell((ceil(14/obj.TTIGranularity) * length(obj.UEs)), 1);
                numDLGrants = 0;

                % Schedule all DL TTIs of length 'obj.TTIGranularity' in the slot one-by-one
                startSym = firstDLSym;
                for i = 1 : numTTIs
                    TTIDLGrants = assignDLResourceTTI(obj, slotNum, startSym,  obj.TTIGranularity);
                    downlinkGrants(numDLGrants + 1 : numDLGrants + length(TTIDLGrants)) = TTIDLGrants(:);
                    numDLGrants = numDLGrants + length(TTIDLGrants);
                    startSym = startSym + obj.TTIGranularity;
                end

                remDLSym = mod(numDLSym, obj.TTIGranularity); % Remaining unscheduled DL symbols
                % Schedule the remaining unscheduled DL symbols with
                % granularity lesser than obj.TTIGranularity
                if remDLSym >= 2 % PDSCH requires minimum 2 symbols with mapping type B as per TS 38.214 - Table 5.1.2.1-1
                    ttiGranularity =  [7 4 2];
                    smallerTTIs = ttiGranularity(ttiGranularity < obj.TTIGranularity); % TTI lengths lesser than obj.TTIGranularity
                    for i = 1:length(smallerTTIs)
                        if(smallerTTIs(i) <= remDLSym)
                            TTIDLGrants = assignDLResourceTTI(obj, slotNum, startSym, smallerTTIs(i));
                            downlinkGrants(numDLGrants + 1 : numDLGrants + length(TTIDLGrants)) = TTIDLGrants(:);
                            numDLGrants = numDLGrants + length(TTIDLGrants);
                            startSym = startSym + smallerTTIs(i);
                            remDLSym = remDLSym - smallerTTIs(i);
                        end
                    end
                end
                downlinkGrants = downlinkGrants(1 : numDLGrants);
            end
        end

        function selectedSlots = selectULSlotsToBeScheduledFDD(obj)
            %selectULSlotsToBeScheduledFDD Select the set of slots to be scheduled by UL scheduler (for FDD mode)

            selectedSlots = zeros(obj.NumSlotsFrame, 1);
            numSelectedSlots = 0;
            obj.SlotsSinceSchedulerRunUL = obj.SlotsSinceSchedulerRunUL + 1;
            if obj.SlotsSinceSchedulerRunUL == obj.SchedulerPeriodicity
                % Scheduler periodicity reached. Select the same number of
                % slots as the scheduler periodicity. Offset of slots to be
                % scheduled in this scheduler run must be such that UEs get
                % required PUSCH preparation time
                firstScheduledSlotOffset = max(1, ceil(obj.PUSCHPrepSymDur/14));
                lastScheduledSlotOffset = firstScheduledSlotOffset + obj.SchedulerPeriodicity - 1;
                for slotOffset = firstScheduledSlotOffset:lastScheduledSlotOffset
                    numSelectedSlots = numSelectedSlots+1;
                    slotNum = mod(obj.CurrSlot + slotOffset, obj.NumSlotsFrame);
                    selectedSlots(numSelectedSlots) = slotNum;
                end
                obj.SlotsSinceSchedulerRunUL = 0;
            end
            selectedSlots = selectedSlots(1:numSelectedSlots);
        end

        function selectedSlots = selectDLSlotsToBeScheduledFDD(obj)
            %selectDLSlotsToBeScheduledFDD Select the slots to be scheduled
            %by DL scheduler (for FDD mode) 

            selectedSlots = zeros(obj.NumSlotsFrame, 1);
            numSelectedSlots = 0;
            obj.SlotsSinceSchedulerRunDL = obj.SlotsSinceSchedulerRunDL + 1;
            if obj.SlotsSinceSchedulerRunDL == obj.SchedulerPeriodicity
                % Scheduler periodicity reached. Select the slots till the
                % slot when scheduler would run next
                for slotOffset = 1:obj.SchedulerPeriodicity
                    numSelectedSlots = numSelectedSlots+1;
                    slotNum = mod(obj.CurrSlot + slotOffset, obj.NumSlotsFrame);
                    selectedSlots(numSelectedSlots) = slotNum;
                end
                obj.SlotsSinceSchedulerRunDL = 0;
            end
            selectedSlots = selectedSlots(1:numSelectedSlots);
        end

        function selectedSlots = selectULSlotsToBeScheduledTDD(obj)
            %selectULSlotsToBeScheduledTDD Get the set of slots to be scheduled by UL scheduler (for TDD mode)
            % The criterion used here selects all the upcoming slots
            % (including the current one) containing unscheduled UL symbols
            % which must be scheduled now. These slots can be scheduled now
            % but cannot be scheduled in the next slot with DL symbols,
            % based on PUSCH preparation time capability of UEs (It is
            % assumed that all the UEs have same PUSCH preparation
            % capability).

            selectedSlots = zeros(obj.NumSlotsFrame, 1);
            numSlotsSelected = 0;
            % Do the scheduling in the slot starting with DL symbol
            if find(obj.DLULSlotFormat(obj.CurrDLULSlotIndex+1, 1) == obj.DLType, 1)
                % Calculate how far the next DL slot is
                nextDLSlotOffset = 1;
                while nextDLSlotOffset < obj.NumSlotsFrame % Consider only the slots within 10 ms
                    slotIndex = mod(obj.CurrDLULSlotIndex + nextDLSlotOffset, obj.NumDLULPatternSlots);
                    if find(obj.DLULSlotFormat(slotIndex + 1, :) == obj.DLType, 1)
                        break; % Found a slot with DL symbols
                    end
                    nextDLSlotOffset = nextDLSlotOffset + 1;
                end
                nextDLSymOffset = (nextDLSlotOffset * 14); % Convert to number of symbols

                % Calculate how many slots ahead is the next to-be-scheduled
                % slot
                nextULSchedSlotOffset = obj.NextULSchedulingSlot - obj.CurrSlot;
                if obj.CurrSlot > obj.NextULSchedulingSlot  % Slot is in the next frame
                    nextULSchedSlotOffset = nextULSchedSlotOffset + obj.NumSlotsFrame;
                end

                % Start evaluating candidate future slots one-by-one, to check
                % if they must be scheduled now, starting from the slot which
                % is 'nextULSchedSlotOffset' slots ahead
                while nextULSchedSlotOffset < obj.NumSlotsFrame
                    % Get slot index of candidate slot in DL-UL pattern and its
                    % format
                    slotIdxDLULPattern = mod(obj.CurrDLULSlotIndex + nextULSchedSlotOffset, obj.NumDLULPatternSlots);
                    slotFormat = obj.DLULSlotFormat(slotIdxDLULPattern + 1, :);

                    firstULSym = find(slotFormat == obj.ULType, 1, 'first'); % Check for location of first UL symbol in the candidate slot
                    if firstULSym % If slot has any UL symbol
                        nextULSymOffset = (nextULSchedSlotOffset * 14) + firstULSym - 1;
                        if (nextULSymOffset - nextDLSymOffset) < obj.PUSCHPrepSymDur
                            % The UL resources of this candidate slot cannot be
                            % scheduled in the first upcoming slot with DL
                            % symbols. Check if it can be scheduled now. If so,
                            % add it to the list of selected slots
                            if nextULSymOffset >= obj.PUSCHPrepSymDur
                                numSlotsSelected = numSlotsSelected + 1;
                                selectedSlots(numSlotsSelected) = mod(obj.CurrSlot + nextULSchedSlotOffset, obj.NumSlotsFrame);
                            end
                        else
                            % Slots which are 'nextULSchedSlotOffset' or more
                            % slots ahead can be scheduled in next slot with DL
                            % symbols as scheduling there will also be able to
                            % give enough PUSCH preparation time for UEs.
                            break;
                        end
                    end
                    nextULSchedSlotOffset = nextULSchedSlotOffset + 1; % Move to the next slot
                end
            end
            selectedSlots = selectedSlots(1 : numSlotsSelected); % Keep only the selected slots in the array
        end

        function selectedSlots = selectDLSlotsToBeScheduledTDD(obj)
            %selectDLSlotsToBeScheduledTDD Select the slots to be scheduled by DL scheduler (for TDD mode)
            % Return the slot number of next slot with DL resources
            % (symbols). In every run the DL scheduler schedules the next
            % slot with DL symbols.

            selectedSlots = [];
            % Do the scheduling in the slot starting with DL symbol
            if find(obj.DLULSlotFormat(obj.CurrDLULSlotIndex+1, 1) == obj.DLType, 1)
                % Calculate how far the next DL slot is
                nextDLSlotOffset = 1; %% CHECK HERE: CAN WE USE THIS
                while nextDLSlotOffset < obj.NumSlotsFrame % Consider only the slots within 10 ms
                    slotIndex = mod(obj.CurrDLULSlotIndex + nextDLSlotOffset, obj.NumDLULPatternSlots);
                    if find(obj.DLULSlotFormat(slotIndex + 1, :) == obj.DLType, 1)
                        % Found a slot with DL symbols, calculate the slot
                        % number
                        selectedSlots = mod(obj.CurrSlot + nextDLSlotOffset, obj.NumSlotsFrame);
                        break;
                    end
                    nextDLSlotOffset = nextDLSlotOffset + 1;
                end
            end
        end

        function selectedSlot = getToBeSchedULSlotNextRun(obj, lastSchedULSlot)
            %getToBeSchedULSlotNextRun Get the first slot to be scheduled by UL scheduler in the next run (for TDD mode)
            % Based on the last scheduled UL slot, get the slot number of
            % the next UL slot (which would be scheduled in the next
            % UL scheduler run)

            % Calculate offset of the last scheduled slot
            if lastSchedULSlot >= obj.CurrSlot
                lastSchedULSlotOffset = lastSchedULSlot - obj.CurrSlot;
            else
                lastSchedULSlotOffset = (obj.NumSlotsFrame + lastSchedULSlot) - obj.CurrSlot;
            end

            candidateSlotOffset = lastSchedULSlotOffset + 1; %%CHECK HERE: MAYBE WE CAN SET OFFSET STARTING FROM 2ND SLOT
            % Slot index in DL-UL pattern
            candidateSlotDLULIndex = mod(obj.CurrDLULSlotIndex + candidateSlotOffset, obj.NumDLULPatternSlots);
            while isempty(find(obj.DLULSlotFormat(candidateSlotDLULIndex+1,:) == obj.ULType, 1))
                % Slot does not have UL symbols. Check the next slot
                candidateSlotOffset = candidateSlotOffset + 1;
                candidateSlotDLULIndex = mod(obj.CurrDLULSlotIndex + candidateSlotOffset, obj.NumDLULPatternSlots);
            end
            selectedSlot = mod(obj.CurrSlot + candidateSlotOffset, obj.NumSlotsFrame);
        end

        function ulGrantsTTI = assignULResourceTTI(obj, slotNum, startSym, numSym)
            %assignULResourceTTI Perform the uplink scheduling of a set of contiguous UL symbols representing a TTI, of the specified slot
            % A UE getting retransmission opportunity in the TTI is not
            % eligible for getting resources for new transmission.

            if obj.ResourceAllocationType % RAT-1
                % An uplink assignment is contiguous over the PUSCH
                % bandwidth in RAT-1 scheduling scheme
                rbAllocationBitmap = zeros(1, obj.NumResourceBlocks);
                % Assignment of resources for retransmissions
                [reTxUEs, rbAllocationBitmap, reTxULGrants] = scheduleRetransmissionsULRAT1(obj, slotNum, startSym, numSym, rbAllocationBitmap);
                ulGrantsTTI = reTxULGrants;
                % Assignment of resources for new transmissions, if there
                % are RBs remaining after allocating for retransmissions. UEs which got
                % assigned resources for retransmissions as well as those with
                % no free HARQ process, are not eligible for assignment
                if any(~rbAllocationBitmap) % If any RB is free in the TTI
                    eligibleUEs = getNewTxEligibleUEs(obj, obj.ULType, reTxUEs);
                    if ~isempty(eligibleUEs) % If there are any eligible UEs
                        numUEsRetx = numel(reTxUEs);
                        [~, ~, newTxULGrants] = scheduleNewTxULRAT1(obj, slotNum, eligibleUEs, startSym, numSym, rbAllocationBitmap, numUEsRetx);
                        ulGrantsTTI = [ulGrantsTTI;newTxULGrants];
                    end
                end
            else % RAT-0
                % An uplink assignment can be non-contiguous, scattered over RBGs
                % of the PUSCH bandwidth
                rbgAllocationBitmap = zeros(1, obj.NumRBGs);
                % Assignment of resources for retransmissions
                [reTxUEs, rbgAllocationBitmap, reTxULGrants] = scheduleRetransmissionsUL(obj, slotNum, startSym, numSym, rbgAllocationBitmap);
                ulGrantsTTI = reTxULGrants;
                % Assignment of resources for new transmissions, if there
                % are RBGs remaining after retransmissions. UEs which got
                % assigned resources for retransmissions as well as those with
                % no free HARQ process, are not eligible for assignment
                if any(~rbgAllocationBitmap) % If any RBG is free in the TTI
                    eligibleUEs = getNewTxEligibleUEs(obj, obj.ULType, reTxUEs);
                    if ~isempty(eligibleUEs) % If there are any eligible UEs
                        numUEsRetx = numel(reTxUEs);
                        [~, ~, newTxULGrants] = scheduleNewTxUL(obj, slotNum, eligibleUEs, startSym, numSym, rbgAllocationBitmap, numUEsRetx);
                        ulGrantsTTI = [ulGrantsTTI;newTxULGrants];
                    end
                end
            end
        end

        function dlGrantsTTI = assignDLResourceTTI(obj, slotNum, startSym, numSym) %% CHECK HERE: TTI SHOULD BE NOT USEFUL SINCE IT IS RETRANSSMISSION
            %assignDLResourceTTI Perform the downlink scheduling of a set of contiguous DL symbols representing a TTI, of the specified slot
            % A UE getting retransmission opportunity in the TTI is not
            % eligible for getting resources for new transmission.

            if obj.ResourceAllocationType % RAT-1
                % A downlink assignment is contiguous over the PDSCH
                % bandwidth in RAT-1 scheduling scheme
                rbAllocationBitmap = zeros(1, obj.NumResourceBlocks);
                % Assignment of resources for retransmissions
                [reTxUEs, rbAllocationBitmap, reTxDLGrants] = scheduleRetransmissionsDLRAT1(obj, slotNum, startSym, numSym, rbAllocationBitmap);
                dlGrantsTTI = reTxDLGrants;
                % Assignment of resources for new transmissions, if there
                % are RBs remaining after allocating for retransmissions. UEs which got
                % assigned resources for retransmissions as well as those with
                % no free HARQ process, are not eligible for assignment
                if any(~rbAllocationBitmap)
                    eligibleUEs = getNewTxEligibleUEs(obj, obj.DLType, reTxUEs);
                    if ~isempty(eligibleUEs) % If there are any eligible UEs
                        numUEsRetx = numel(reTxUEs);
                        [~, ~, newTxDLGrants] = scheduleNewTxDLRAT1(obj, slotNum, eligibleUEs, startSym, numSym, rbAllocationBitmap, numUEsRetx);
                        dlGrantsTTI = [dlGrantsTTI;newTxDLGrants];
                    end
                end
            else % RAT-0
                % A downlink assignment can be non-contiguous, scattered over RBGs
                % of the PDSCH bandwidth
                rbgAllocationBitmap = zeros(1, obj.NumRBGs);
                % Assignment of resources for retransmissions
                [reTxUEs, rbgAllocationBitmap, reTxDLGrants] = scheduleRetransmissionsDL(obj, slotNum, startSym, numSym, rbgAllocationBitmap);
                dlGrantsTTI = reTxDLGrants;
                % Assignment of resources for new transmissions, if there
                % are RBGs remaining after retransmissions. UEs which got
                % assigned resources for retransmissions as well those with
                % no free HARQ process, are not considered
                if any(~rbgAllocationBitmap)
                    eligibleUEs = getNewTxEligibleUEs(obj, obj.DLType, reTxUEs);
                    if ~isempty(eligibleUEs) % If there are eligible UEs for new transmission
                        numUEsRetx = numel(reTxUEs);
                        [~, ~, newTxDLGrants] = scheduleNewTxDL(obj, slotNum, eligibleUEs, startSym, numSym, rbgAllocationBitmap, numUEsRetx);
                        dlGrantsTTI = [dlGrantsTTI;newTxDLGrants];
                    end
                end
            end
        end

        function [reTxUEs, updatedRBGStatus, ulGrants] = scheduleRetransmissionsUL(obj, scheduledSlot, startSym, numSym, rbgOccupancyBitmap)
            %scheduleRetransmissionsUL Assign resources of a set of contiguous UL symbols representing a TTI, of the specified slot for uplink retransmissions
            % Return the uplink assignments to the UEs which are allotted
            % retransmission opportunity and the updated
            % RBG-occupancy-status to convey what all RBGs are used. All
            % UEs are checked if they require retransmission for any of
            % their HARQ processes. If there are multiple such HARQ
            % processes for a UE then one HARQ process is selected randomly
            % among those. All UEs get maximum 1 retransmission opportunity
            % in a TTI

            % Holds updated RBG occupancy status as the RBGs keep getting
            % allotted for retransmissions
            updatedRBGStatus = rbgOccupancyBitmap;

            reTxGrantCount = 0;
            % Store UEs which get retransmission opportunity
            reTxUEs = zeros(length(obj.UEs), 1);
            % Store retransmission UL grants of this TTI
            ulGrants = cell(length(obj.UEs), 1);

            % Create a random permutation of UE RNTIs, to define the order
            % in which UEs would be considered for retransmission
            % assignments for this scheduler run
            reTxAssignmentOrder = randperm(length(obj.UEs));

            % Calculate offset of scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot;
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Consider retransmission requirement of the UEs as per
            % reTxAssignmentOrder
            for i = 1:length(reTxAssignmentOrder)
                % Stop assigning resources if the allocations are done for maximum users
                if reTxGrantCount >= obj.MaxNumUsersPerTTI
                    break;
                end
                reTxContextUE = obj.RetransmissionContextUL(obj.UEs(reTxAssignmentOrder(i)), :);
                failedRxHarqs = find(~cellfun(@isempty,reTxContextUE));
                if ~isempty(failedRxHarqs) % At least one UL HARQ process for UE requires retransmission
                    % Select one HARQ process randomly
                    selectedHarqId = failedRxHarqs(randi(length(failedRxHarqs))) - 1;
                    % Read the TBS of original grant. Retransmission grant TBS also needs to be
                    % big enough to accommodate the packet.
                    lastTBSBits = obj.TBSizeUL(obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1)*8; % TBS in bits
                    lastGrant = reTxContextUE{selectedHarqId+1};
                    % Select rank and precoding matrix for the UE
                    if ~obj.AdaptiveRetransmission % Non-adaptive retransmission
                        rank = lastGrant.NumLayers;
                        tpmi = lastGrant.TPMI;
                        numAntennaPorts = lastGrant.NumAntennaPorts;
                        % Assign resources and MCS for retransmission
                        [isAssigned, allottedRBGBitmap, mcs] = getRetxResourcesNonAdaptive(obj, obj.ULType, ...
                            updatedRBGStatus, numSym, lastGrant);
                    else % Adaptive retransmission
                        [rank, tpmi, numAntennaPorts] = selectRankAndPrecodingMatrixUL(obj, obj.CSIMeasurementUL(reTxAssignmentOrder(i)), obj.NumSRSPorts(reTxAssignmentOrder(i)));
                        % Assign resources and MCS for retransmission
                        [isAssigned, allottedRBGBitmap, mcs] = getRetxResourcesAdaptive(obj, obj.ULType, reTxAssignmentOrder(i), ...
                            lastTBSBits, updatedRBGStatus, startSym, numSym, rank, lastGrant);
                    end
                    if isAssigned
                        % Fill the retransmission uplink grant properties
                        grant = obj.ULGrantInfo;
                        grant.RNTI = reTxAssignmentOrder(i);
                        grant.Type = 'reTx';
                        grant.HARQID = selectedHarqId;
                        grant.ResourceAllocationType = 0;
                        grant.FrequencyAllocation = allottedRBGBitmap;
                        grant.StartSymbol = startSym;
                        grant.NumSymbols = numSym;
                        grant.SlotOffset = slotOffset;
                        grant.MCS = mcs;
                        grant.NDI = obj.HarqNDIUL(reTxAssignmentOrder(i), selectedHarqId+1); % Fill same NDI (for retransmission)
                        grant.DMRSLength = obj.PUSCHDMRSLength;
                        grant.MappingType = obj.PUSCHMappingType;
                        grant.NumLayers = rank;
                        if obj.AdaptiveRetransmission
                            grantRBs = convertRBGBitmapToRBs(obj, grant.FrequencyAllocation);
                            tpmiRBs = tpmi(grantRBs+1);
                            tpmi = floor(sum(tpmiRBs)/numel(tpmiRBs)); % Taking average of the measured TPMI on grant RBs
                        end
                        grant.TPMI = tpmi;
                        % Set number of CDM groups without data (1...3)
                        if numSym > 1
                            grant.NumCDMGroupsWithoutData = 2;
                        else
                            grant.NumCDMGroupsWithoutData = 1; % To ensure some REs for data
                        end
                        grant.NumAntennaPorts = numAntennaPorts;
                        % Set the RV
                        harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesUL(reTxAssignmentOrder(i), selectedHarqId+1), 1);
                        grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));

                        reTxGrantCount = reTxGrantCount+1;
                        reTxUEs(reTxGrantCount) = reTxAssignmentOrder(i);
                        ulGrants{reTxGrantCount} = grant;
                        % Mark the allotted RBGs as occupied.
                        updatedRBGStatus = updatedRBGStatus | allottedRBGBitmap;

                        % Clear the retransmission context for this HARQ
                        % process of the selected UE to make it ineligible
                        % for retransmission assignments (Retransmission
                        % context would again get set, if Rx fails again in
                        % future for this retransmission assignment)
                        obj.RetransmissionContextUL{obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1} = [];
                    end
                end
            end
            reTxUEs = reTxUEs(1 : reTxGrantCount);
            ulGrants = ulGrants(1 : reTxGrantCount); % Remove all empty elements
        end

        function [reTxUEs, updatedRBStatus, ulGrants] = scheduleRetransmissionsULRAT1(obj, scheduledSlot, startSym, numSym, rbOccupancyBitmap)
            %scheduleRetransmissionsULRAT1 Assign resources of a set of contiguous UL symbols representing a TTI, of the specified slot for uplink retransmissions
            % Return the uplink assignments to the UEs which are allotted
            % retransmission opportunity and the updated
            % RB-occupancy-status to convey what all RBs are used. All UEs
            % are checked if they require retransmission for any of their
            % HARQ processes. If there are multiple such HARQ processes for
            % a UE then one HARQ process is selected randomly among those.
            % All UEs get maximum 1 retransmission opportunity in a TTI

            % Hold updated RB occupancy status as the RBs keep getting
            % allotted for retransmissions
            updatedRBStatus = rbOccupancyBitmap;
            % Store UEs which get retransmission opportunity
            reTxUEs = zeros(length(obj.UEs), 1);
            % Store retransmission UL grants of this TTI
            ulGrants = cell(length(obj.UEs), 1);

            % Create a random permutation of UE RNTIs, to define the order
            % in which UEs would be considered for retransmission
            % assignments for this scheduler run
            reTxAssignmentOrder = randperm(length(obj.UEs));

            % Calculate offset of scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot;
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            reTxGrantCount = 0;
            isAssigned = 0;
            % Consider retransmission requirement of the UEs as per
            % reTxAssignmentOrder
            for i = 1:length(reTxAssignmentOrder)
                % Stop assigning resources if the allocations are done for maximum users
                if reTxGrantCount >= obj.MaxNumUsersPerTTI
                    break;
                end
                reTxContextUE = obj.RetransmissionContextUL(obj.UEs(reTxAssignmentOrder(i)), :);
                failedRxHarqs = find(~cellfun(@isempty,reTxContextUE));
                if ~isempty(failedRxHarqs) % At least one UL HARQ process for UE requires retransmission
                    % Select one HARQ process randomly
                    selectedHarqId = failedRxHarqs(randi(length(failedRxHarqs))) - 1;

                    lastGrant = reTxContextUE{selectedHarqId+1};
                    if ~obj.AdaptiveRetransmission % Non-adaptive retransmissions
                        lastGrantNumSym = lastGrant.NumSymbols;
                        lastGrantNumRBs = lastGrant.FrequencyAllocation(2);
                        % Ensure that total REs are at least equal to REs in original grant
                        numResourceBlocks = ceil(lastGrantNumSym*lastGrantNumRBs/numSym);
                        startRBIndex = find(updatedRBStatus == 0, 1)-1;

                        if numResourceBlocks <= (obj.NumResourceBlocks-startRBIndex)
                            % Retransmission TBS requirement have met
                            isAssigned = 1;
                            frequencyAllocation = [startRBIndex numResourceBlocks];
                            mcs = lastGrant.MCS;
                            rank = lastGrant.NumLayers;
                            tpmi = lastGrant.TPMI;
                            numAntennaPorts = lastGrant.NumAntennaPorts;
                        end
                    else % Adaptive retransmissions
                        % Select rank and precoding matrix for the UE
                        [rank, tpmi, numAntennaPorts] = selectRankAndPrecodingMatrixUL(obj, obj.CSIMeasurementUL(reTxAssignmentOrder(i)), obj.NumSRSPorts(reTxAssignmentOrder(i)));
                        % Read the TBS of original grant. Retransmission grant TBS also needs to be
                        % big enough to accommodate the packet.
                        lastTBSBits = obj.TBSizeUL(obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1)*8; % TBS in bits
                        % Assign frequency resources and MCS for retransmission
                        [isAssigned, frequencyAllocation, mcs] = getRetxResourcesAdaptiveRAT1(obj, obj.ULType, reTxAssignmentOrder(i), ...
                            lastTBSBits, updatedRBStatus, scheduledSlot, startSym, numSym, rank, lastGrant);
                        grantRBs = frequencyAllocation(1):frequencyAllocation(1)+frequencyAllocation(2)-1;
                        tpmiRBs = tpmi(grantRBs+1);
                        tpmi = floor(mean(tpmiRBs)); % Taking average of the measured TPMI on grant RBs
                    end
                    if isAssigned
                        % Fill the retransmission RAT-1 uplink grant properties
                        grant = obj.ULGrantInfo;
                        grant.RNTI = reTxAssignmentOrder(i);
                        grant.Type = 'reTx';
                        grant.HARQID = selectedHarqId;
                        grant.ResourceAllocationType = 1;
                        grant.FrequencyAllocation = frequencyAllocation;
                        grant.StartSymbol = startSym;
                        grant.NumSymbols = numSym;
                        grant.SlotOffset = slotOffset;
                        grant.MCS = mcs;
                        grant.NDI = obj.HarqNDIUL(reTxAssignmentOrder(i), selectedHarqId+1); % Fill same NDI (for retransmission)
                        grant.DMRSLength = obj.PUSCHDMRSLength;
                        grant.MappingType = obj.PUSCHMappingType;
                        grant.NumLayers = rank;
                        % Set number of CDM groups without data (1...3)
                        if numSym > 1
                            grant.NumCDMGroupsWithoutData = 2;
                        else
                            grant.NumCDMGroupsWithoutData = 1; % To ensure some REs for data
                        end
                        grant.NumAntennaPorts = numAntennaPorts;
                        grant.TPMI = tpmi;
                        % Set the RV
                        harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesUL(reTxAssignmentOrder(i), selectedHarqId+1), 1);
                        grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));

                        reTxGrantCount = reTxGrantCount+1;
                        reTxUEs(reTxGrantCount) = reTxAssignmentOrder(i);
                        ulGrants{reTxGrantCount} = grant;

                        % Mark the allotted contiguous RBs as occupied.
                        updatedRBStatus(frequencyAllocation(1)+1:frequencyAllocation(1)+frequencyAllocation(2)) = 1;
                        
                        % Clear the retransmission context for this HARQ
                        % process of the selected UE to make it ineligible
                        % for retransmission assignments (retransmission
                        % context would again get set, if Rx fails again in
                        % future for this retransmission assignment)
                        obj.RetransmissionContextUL{obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1} = [];
                        isAssigned = 0;
                    end
                end
            end
            reTxUEs = reTxUEs(1 : reTxGrantCount);
            ulGrants = ulGrants(1:reTxGrantCount); % Remove all empty elements
        end

        function [reTxUEs, updatedRBGStatus, dlGrants] = scheduleRetransmissionsDL(obj, scheduledSlot, startSym, numSym, rbgOccupancyBitmap)
            %scheduleRetransmissionsDL Assign resources of a set of contiguous DL symbols representing a TTI, of the specified slot for downlink retransmissions
            % Return the downlink assignments to the UEs which are
            % allotted retransmission opportunity and the updated
            % RBG-occupancy-status to convey what all RBGs are used. All
            % UEs are checked if they require retransmission for any of
            % their HARQ processes. If there are multiple such HARQ
            % processes for a UE then one HARQ process is selected randomly
            % among those. All UEs get maximum 1 retransmission opportunity
            % in a TTI

            % Holds updated RBG occupancy status as the RBGs keep getting
            % allotted for retransmissions
            updatedRBGStatus = rbgOccupancyBitmap;

            reTxGrantCount = 0;
            % Store UEs which get retransmission opportunity
            reTxUEs = zeros(length(obj.UEs), 1);
            % Store retransmission DL grants of this TTI
            dlGrants = cell(length(obj.UEs), 1);

            % Create a random permutation of UE RNTIs, to define the order
            % in which retransmission assignments would be done for this
            % TTI
            reTxAssignmentOrder = randperm(length(obj.UEs));

            % Calculate offset of currently scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot;
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame; % Scheduled slot is in next frame
            end

            % Consider retransmission requirement of the UEs as per
            % reTxAssignmentOrder
            for i = 1:length(reTxAssignmentOrder) % For each UE
                % Stop assigning resources if the allocations are done for maximum users
                if reTxGrantCount >= obj.MaxNumUsersPerTTI
                    break;
                end
                reTxContextUE = obj.RetransmissionContextDL(obj.UEs(reTxAssignmentOrder(i)), :);
                failedRxHarqs = find(~cellfun(@isempty,reTxContextUE));
                if ~isempty(failedRxHarqs)
                    % Select one HARQ process randomly
                    selectedHarqId = failedRxHarqs(randi(length(failedRxHarqs))) - 1;
                    % Read TBS. Retransmission grant TBS also needs to be
                    % big enough to accommodate the packet
                    lastTBSBits = obj.TBSizeDL(obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1)*8;
                    lastGrant = reTxContextUE{selectedHarqId+1};
                    if ~obj.AdaptiveRetransmission % Non-adaptive retransmissions
                        % Select rank and precoding matrix as per the
                        % last transmission
                        rank = lastGrant.NumLayers;
                        W = lastGrant.PrecodingMatrix;
                        % Assign resources and MCS for retransmission
                        [isAssigned, allottedRBGBitmap, mcs] = getRetxResourcesNonAdaptive(obj, obj.DLType, ...
                            updatedRBGStatus, numSym, lastGrant);
                    else
                        % Select rank and precoding matrix as per the
                        % channel quality
                        [rank, W] = selectRankAndPrecodingMatrixDL(obj, obj.CSIMeasurementDL(reTxAssignmentOrder(i)), obj.NumCSIRSPorts(reTxAssignmentOrder(i)));
                        % Assign resources and MCS for retransmission
                        [isAssigned, allottedRBGBitmap, mcs] = getRetxResourcesAdaptive(obj, obj.DLType, reTxAssignmentOrder(i),  ...
                            lastTBSBits, updatedRBGStatus, startSym, numSym, rank, lastGrant);
                    end

                    if isAssigned
                        % Fill the retransmission downlink grant properties
                        grant = obj.DLGrantInfo;
                        grant.RNTI = reTxAssignmentOrder(i);
                        grant.Type = 'reTx';
                        grant.HARQID = selectedHarqId;
                        grant.ResourceAllocationType = 0;
                        grant.FrequencyAllocation = allottedRBGBitmap;
                        grant.StartSymbol = startSym;
                        grant.NumSymbols = numSym;
                        grant.SlotOffset = slotOffset;
                        grant.MCS = mcs;
                        grant.NDI = obj.HarqNDIDL(reTxAssignmentOrder(i), selectedHarqId+1); % Fill same NDI (for retransmission)
                        grant.FeedbackSlotOffset = getPDSCHFeedbackSlotOffset(obj, slotOffset);
                        grant.DMRSLength = obj.PDSCHDMRSLength;
                        grant.MappingType = obj.PDSCHMappingType;
                        grant.NumLayers = rank;
                        grant.PrecodingMatrix = W;
                        grant.NumCDMGroupsWithoutData = 2; % Number of CDM groups without data (1...3)
                        csiResourceIndicator = obj.CSIMeasurementDL(reTxAssignmentOrder(i)).CSIResourceIndicator;
                        if isempty(csiResourceIndicator)
                            grant.BeamIndex = [];
                        else
                            grant.BeamIndex = (obj.SSBIdx(reTxAssignmentOrder(i))-1)*obj.NumCSIRSBeams + csiResourceIndicator;
                        end

                        % Set the RV
                        harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesDL(reTxAssignmentOrder(i), selectedHarqId+1), 1);
                        grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));

                        reTxGrantCount = reTxGrantCount+1;
                        reTxUEs(reTxGrantCount) = reTxAssignmentOrder(i);
                        dlGrants{reTxGrantCount} = grant;
                        % Mark the allotted RBGs as occupied.
                        updatedRBGStatus = updatedRBGStatus | allottedRBGBitmap;
                        % Clear the retransmission context for this HARQ
                        % process of the selected UE to make it ineligible
                        % for retransmission assignments (Retransmission
                        % context would again get set, if Rx fails again in
                        % future for this retransmission assignment)
                        obj.RetransmissionContextDL{obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1} = [];
                    end
                end
            end
            reTxUEs = reTxUEs(1 : reTxGrantCount);
            dlGrants = dlGrants(1 : reTxGrantCount); % Remove all empty elements
        end

        function [reTxUEs, updatedRBStatus, dlGrants] = scheduleRetransmissionsDLRAT1(obj, scheduledSlot, startSym, numSym, rbOccupancyBitmap)
            %scheduleRetransmissionsDLRAT1 Assign resources of a set of contiguous DL symbols representing a TTI, of the specified slot for downlink retransmissions
            % Return the downlink assignments to the UEs which are allotted
            % retransmission opportunity and the updated
            % RB-occupancy-status to convey what all RBs are used. All UEs
            % are checked if they require retransmission for any of their
            % HARQ processes. If there are multiple such HARQ processes for
            % a UE then one HARQ process is selected randomly among those.
            % All UEs get maximum 1 retransmission opportunity in a TTI

            % Holds updated RB occupancy status as the RBs keep getting
            % allotted for retransmissions
            updatedRBStatus = rbOccupancyBitmap;

            reTxGrantCount = 0;
            isAssigned=0;
            % Store UEs which get retransmission opportunity
            reTxUEs = zeros(length(obj.UEs), 1);
            % Store retransmission DL grants of this TTI
            dlGrants = cell(length(obj.UEs), 1);

            % Create a random permutation of UE RNTIs, to define the order
            % in which UEs would be considered for retransmission
            % assignments for this scheduler run
            reTxAssignmentOrder = randperm(length(obj.UEs));

            % Calculate offset of scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot;
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Consider retransmission requirement of the UEs as per
            % reTxAssignmentOrder
            for i = 1:length(reTxAssignmentOrder)
                % Stop assigning resources if the allocations are done for maximum users
                if reTxGrantCount >= obj.MaxNumUsersPerTTI
                    break;
                end
                reTxContextUE = obj.RetransmissionContextDL(obj.UEs(reTxAssignmentOrder(i)), :);
                failedRxHarqs = find(~cellfun(@isempty,reTxContextUE));
                if ~isempty(failedRxHarqs) % At least one DL HARQ process for UE requires retransmission
                    % Select one HARQ process randomly
                    selectedHarqId = failedRxHarqs(randi(length(failedRxHarqs))) - 1;
                    lastGrant = reTxContextUE{selectedHarqId+1};

                    if ~obj.AdaptiveRetransmission % Non-adaptive retransmissions
                        lastGrantNumSym = lastGrant.NumSymbols;
                        lastGrantNumRBs = lastGrant.FrequencyAllocation(2);
                        % Ensure that total REs are at least equal to REs in original grant
                        numResourceBlocks = ceil(lastGrantNumSym*lastGrantNumRBs/numSym);
                        startRBIndex = find(updatedRBStatus == 0, 1)-1;
                        if numResourceBlocks <= (obj.NumResourceBlocks-startRBIndex)
                            % Retransmission TBS requirement have met
                            isAssigned = 1;
                            frequencyAllocation = [startRBIndex numResourceBlocks];
                            mcs = lastGrant.MCS;
                            rank = lastGrant.NumLayers;
                            W = lastGrant.PrecodingMatrix;
                        end
                    else % Adaptive retransmissions
                        % Select rank and precoding matrix for the UE
                        [rank, W] = selectRankAndPrecodingMatrixDL(obj, obj.CSIMeasurementDL(reTxAssignmentOrder(i)), obj.NumCSIRSPorts(reTxAssignmentOrder(i)));
                        % Read the TBS of original grant. Retransmission grant TBS also needs to be
                        % big enough to accommodate the packet.
                        lastTBSBits = obj.TBSizeDL(obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1)*8; % TBS in bits
                        % Assign frequency resources and MCS for retransmission
                        [isAssigned, frequencyAllocation, mcs] = getRetxResourcesAdaptiveRAT1(obj, obj.DLType, reTxAssignmentOrder(i), ...
                            lastTBSBits, updatedRBStatus, scheduledSlot, startSym, numSym, rank, lastGrant);
                    end
                    if isAssigned
                        % Fill the retransmission RAT-1 uplink grant properties
                        grant = obj.DLGrantInfo;
                        grant.RNTI = reTxAssignmentOrder(i);
                        grant.Type = 'reTx';
                        grant.HARQID = selectedHarqId;
                        grant.ResourceAllocationType = 1;
                        grant.FrequencyAllocation = frequencyAllocation;
                        grant.StartSymbol = startSym;
                        grant.NumSymbols = numSym;
                        grant.SlotOffset = slotOffset;
                        grant.MCS = mcs;
                        grant.NDI = obj.HarqNDIDL(reTxAssignmentOrder(i), selectedHarqId+1); % Fill same NDI (for retransmission)
                        grant.FeedbackSlotOffset = getPDSCHFeedbackSlotOffset(obj, slotOffset);
                        grant.DMRSLength = obj.PDSCHDMRSLength;
                        grant.MappingType = obj.PDSCHMappingType;
                        grant.NumLayers = rank;
                        grant.PrecodingMatrix = W;
                        grant.NumCDMGroupsWithoutData = 2; % Number of CDM groups without data (1...3)
                        csiResourceIndicator = obj.CSIMeasurementDL(reTxAssignmentOrder(i)).CSIResourceIndicator;
                        if isempty(csiResourceIndicator)
                            grant.BeamIndex = [];
                        else
                            grant.BeamIndex = (obj.SSBIdx(reTxAssignmentOrder(i))-1)*obj.NumCSIRSBeams + csiResourceIndicator;
                        end

                        % Set the RV
                        harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesDL(reTxAssignmentOrder(i), selectedHarqId+1), 1);
                        grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));

                        reTxGrantCount = reTxGrantCount+1;
                        reTxUEs(reTxGrantCount) = reTxAssignmentOrder(i);
                        dlGrants{reTxGrantCount} = grant;

                        % Mark the allotted contiguous RBs as occupied.
                        updatedRBStatus(frequencyAllocation(1)+1:frequencyAllocation(1)+frequencyAllocation(2)) = 1;

                        % Clear the retransmission context for this HARQ
                        % process of the selected UE to make it ineligible
                        % for retransmission assignments (retransmission
                        % context would again get set, if Rx fails again in
                        % future for this retransmission assignment)
                        obj.RetransmissionContextDL{obj.UEs(reTxAssignmentOrder(i)), selectedHarqId+1} = [];
                        isAssigned = 0;
                    end
                end
            end
            reTxUEs = reTxUEs(1 : reTxGrantCount);
            dlGrants = dlGrants(1:reTxGrantCount); % Remove all empty elements
        end

        function [newTxUEs, updatedRBGStatus, ulGrants] = scheduleNewTxUL(obj, scheduledSlot, eligibleUEs, startSym, numSym, rbgOccupancyBitmap, numUEsRetx)
            %scheduleNewTxUL Assign resources of a set of contiguous UL symbols representing a TTI, of the specified slot for new uplink transmissions
            % Return the uplink assignments, the UEs which are allotted
            % new transmission opportunity and the RBG-occupancy-status to
            % convey what all RBGs are used. Eligible set of UEs are passed
            % as input along with the bitmap of occupancy status of RBGs
            % for the slot getting scheduled. Only RBGs marked as 0 are
            % available for assignment to UEs

            numEligibleUEs = min(length(eligibleUEs), obj.MaxNumUsersPerTTI - numUEsRetx);
            % Select index of the first UE for scheduling. After the last selected UE,
            % go in sequence and find index of the first eligible UE
            scheduledUEIndex = find(eligibleUEs>obj.LastSelectedUEUL, 1);
            if isempty(scheduledUEIndex)
                scheduledUEIndex = 1;
            end

            % Shift eligibleUEs set such that first eligible UE (as per
            % round-robin assignment) is at first index
            eligibilityOrder = circshift(eligibleUEs,  [0 -(scheduledUEIndex-1)]);
            eligibleUEs = eligibilityOrder(1:numEligibleUEs);

            % Stores UEs which get new transmission opportunity
            newTxUEs = zeros(length(eligibleUEs), 1);

            % Stores UL grants of this TTI
            ulGrants = cell(length(eligibleUEs), 1);

            % To store the MCS of all the RBGs allocated to UEs. As PUSCH
            % assignment to a UE must have a single MCS even if multiple
            % RBGs are allotted, average of all the values is taken.
            rbgMCS = -1*ones(length(eligibleUEs), obj.NumRBGs);

            % To store allotted RB count to UE in the slot
            allottedRBCount = zeros(length(eligibleUEs), 1);

            % Holds updated RBG occupancy status as the RBGs keep getting
            % allotted for new transmissions
            updatedRBGStatus = rbgOccupancyBitmap;

            % Calculate offset of scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot;
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Select rank and precoding matrix for the eligible UEs
            numEligibleUEs = length(eligibleUEs);
            tpmi = zeros(numEligibleUEs, obj.NumResourceBlocks); % To store selected precoding matrices for the UEs
            rank = zeros(numEligibleUEs, 1); % To store selected rank for the UEs
            numAntennaPorts = zeros(numEligibleUEs, 1); % To store selected antenna port count for PUSCH
            rbRequirement =  zeros(numEligibleUEs, 1); % To store RB requirement for UEs
            for i=1:numEligibleUEs
                [rank(i), tpmi(i, :), numAntennaPorts(i)] = selectRankAndPrecodingMatrixUL(obj, obj.CSIMeasurementUL(eligibleUEs(i)), obj.NumSRSPorts(eligibleUEs(i)));
                rbRequirement(i) = calculateRBRequirement(obj, eligibleUEs(i), 1, startSym, numSym, rank(i));
            end

            % For each available RBG, based on the scheduling strategy
            % select the most appropriate UE. Also ensure that the number of
            % RBs allotted to a UE in the slot does not exceed the limit as
            % defined by the class property 'RBAllocationLimit'
            RBGEligibleUEs = eligibleUEs; % To keep track of UEs currently eligible for RBG allocations in this slot
            rankRBGEligibleUEs = rank;
            newTxGrantCount = 0;
            numFreeRBG = length(find(rbgOccupancyBitmap==0));
            assignedNumRBG = 0;
            perUEMinShare = floor(numFreeRBG/numEligibleUEs);
            lastGrantedUE = obj.LastSelectedUEUL;
            for i = 1:length(rbgOccupancyBitmap)
                % Resource block group is free
                if ~rbgOccupancyBitmap(i)
                    RBGIndex = i-1;
                    schedulerInput = createSchedulerInput(obj, obj.ULType, scheduledSlot, RBGEligibleUEs, rankRBGEligibleUEs, RBGIndex, startSym, numSym);
                    % Run the scheduling strategy to select a UE for the RBG and appropriate MCS
                    [selectedUE, mcs] = runSchedulingStrategy(obj, schedulerInput);
                    if selectedUE ~= -1 % If RBG is assigned to any UE
                        assignedNumRBG = assignedNumRBG + 1;
                        obj.LastSelectedUEUL = selectedUE;
                        updatedRBGStatus(i) = 1; % Mark as assigned
                        selectedUEIdx = find(eligibleUEs == selectedUE, 1, 'first'); % Find UE index in eligible UEs set
                        rbgMCS(selectedUEIdx, i) = mcs;
                        if isempty(find(newTxUEs == selectedUE,1))
                            % Selected UE is allotted first RBG in this TTI
                            grant = obj.ULGrantInfo;
                            grant.RNTI = selectedUE;
                            grant.Type = 'newTx';
                            grant.ResourceAllocationType = 0;
                            grant.FrequencyAllocation = zeros(1, length(rbgOccupancyBitmap));
                            grant.FrequencyAllocation(RBGIndex+1) = 1;
                            grant.StartSymbol = startSym;
                            grant.NumSymbols = numSym;
                            grant.SlotOffset = slotOffset;
                            grant.MappingType = obj.PUSCHMappingType;
                            grant.DMRSLength = obj.PUSCHDMRSLength;
                            grant.NumLayers = rank(selectedUEIdx);
                            % Set number of CDM groups without data (1...3)
                            if numSym > 1
                                grant.NumCDMGroupsWithoutData = 2;
                            else
                                grant.NumCDMGroupsWithoutData = 1; % To ensure some REs for data
                            end
                            grant.NumAntennaPorts = numAntennaPorts(selectedUEIdx);

                            newTxGrantCount = newTxGrantCount + 1;
                            newTxUEs(newTxGrantCount) = selectedUE;
                            ulGrants{selectedUEIdx} = grant;
                            lastGrantedUE = selectedUE; % Update UE with last UL grant in the TTI
                        else
                            % Add RBG to the UE's grant
                            grant = ulGrants{selectedUEIdx};
                            grant.FrequencyAllocation(RBGIndex+1) = 1;
                            ulGrants{selectedUEIdx} = grant;
                        end
                        
                        if isempty(find(newTxUEs==0, 1)) && assignedNumRBG >= (perUEMinShare*numEligibleUEs)
                            % Assign extra RBGs randomly
                            obj.LastSelectedUEUL = RBGEligibleUEs(randi(length(RBGEligibleUEs)));
                        end

                        if RBGIndex < obj.NumRBGs-1
                            allottedRBCount(selectedUEIdx) = allottedRBCount(selectedUEIdx) + obj.RBGSize;
                            % Check if the UE which got this RBG remains
                            % eligible for further RBGs in this TTI, as per
                            % set 'RBAllocationLimitUL'.
                            nextRBGSize = obj.RBGSize;
                            if RBGIndex == obj.NumRBGs-2 % If next RBG index is the last one in the BWP
                                nextRBGSize = obj.NumResourceBlocks - ((RBGIndex+1) * obj.RBGSize);
                            end
                            if allottedRBCount(selectedUEIdx) > (obj.RBAllocationLimitUL - nextRBGSize) || ...
                                    allottedRBCount(selectedUEIdx) >= rbRequirement(selectedUEIdx)
                                % Not eligible for next RBG as either either max RB allocation limit would
                                % get breached, or RB requirement is satisfied for the UE
                                [RBGEligibleUEs, indices] = setdiff(RBGEligibleUEs, selectedUE, 'stable');
                                rankRBGEligibleUEs = rankRBGEligibleUEs(indices);
                            end
                        end
                    end
                end
            end

            % Calculate a single MCS and TPMI value for the PUSCH assignment to UEs
            % from the MCS values of all the RBGs allotted. Also select a
            % free HARQ process to be used for uplink over the selected
            % RBGs. It was already ensured that UEs in eligibleUEs set have
            % at least one free HARQ process before deeming them eligible
            % for getting resources for new transmission
            for i = 1:length(eligibleUEs)
                % If any resources were assigned to this UE
                if ~isempty(ulGrants{i})
                    grant = ulGrants{i};
                    grant.MCS = obj.MCSForRBGBitmap(rbgMCS(i, :)); % Get a single MCS for all allotted RBGs
                    grantRBs = convertRBGBitmapToRBs(obj, grant.FrequencyAllocation);
                    tpmiRBs = tpmi(i, grantRBs+1);
                    grant.TPMI = floor(sum(tpmiRBs)/numel(tpmiRBs)); % Taking average of the measured TPMI on grant RBs
                    % Select one HARQ process, update its context to reflect
                    % grant
                    selectedHarqId = findFreeUEHarqProcess(obj, obj.ULType, eligibleUEs(i));
                    harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesUL(eligibleUEs(i), selectedHarqId+1), 1);
                    grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));

                    grant.HARQID = selectedHarqId; % Fill HARQ id in grant
                    % Toggle the NDI for new transmission
                    if obj.HarqNDIUL(grant.RNTI, selectedHarqId + 1)
                        grant.NDI = 0;
                    else
                        grant.NDI = 1;
                    end
                    obj.HarqNDIUL(grant.RNTI, selectedHarqId+1) = grant.NDI; % Update the NDI context for the HARQ process
                    obj.HarqStatusUL{eligibleUEs(i), selectedHarqId+1} = grant; % Mark HARQ process as busy
                    ulGrants{i} = grant;
                end
            end
            newTxUEs = newTxUEs(1 : newTxGrantCount);
            ulGrants = ulGrants(~cellfun('isempty',ulGrants)); % Remove all empty elements
            obj.LastSelectedUEUL = lastGrantedUE;
        end

        function [newTxUEs, updatedRBStatus, ulGrants] = scheduleNewTxULRAT1(obj, scheduledSlot, eligibleUEs, startSym, numSym, rbOccupancyBitmap, numUEsRetx)
            %scheduleNewTxULRAT1 Assign resources of a set of contiguous UL symbols representing a TTI, of the specified slot for new uplink transmissions
            % Return the uplink assignments, the UEs which are allotted new
            % transmission opportunity and the RB-occupancy-status to
            % convey what all RBs are used. Eligible set of UEs are passed
            % as input along with the bitmap of occupancy status of RBs for
            % the slot getting scheduled. Only RBs marked as 0 are
            % available for assignment to UEs

            % Stores UEs which get new transmission opportunity
            newTxUEs = zeros(length(eligibleUEs), 1);

            % Stores UL grants of this TTI
            ulGrants = cell(length(eligibleUEs), 1);

            % Holds updated RB occupancy status as the RBs keep getting
            % allotted for new transmissions
            updatedRBStatus = rbOccupancyBitmap;

            % Calculate offset of scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot;
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Create the input structure for scheduling strategy
            schedulerInput = struct();
            schedulerInput.eligibleUEs = eligibleUEs;
            schedulerInput.bufferStatus = sum(obj.BufferStatusUL(eligibleUEs, :), 2);
            schedulerInput.rbOccupancyBitmap = rbOccupancyBitmap;
            schedulerInput.rbAllocationLimit = obj.RBAllocationLimitUL;
            schedulerInput.numUEsRetx = numUEsRetx;
            for i = 1:length(eligibleUEs)
                schedulerInput.channelQuality(eligibleUEs(i), :) = obj.CSIMeasurementUL(eligibleUEs(i)).CQI;
                schedulerInput.rbRequirement(eligibleUEs(i)) = obj.calculateRBRequirement(eligibleUEs(i), 1, ...
                    startSym, numSym, obj.CSIMeasurementUL(eligibleUEs(i)).RankIndicator);
            end
            schedulerInput.lastSelectedUE = obj.LastSelectedUEUL;
            schedulerInput.linkDir = 1; % Uplink

            % Implement round robin scheduling strategy
            [allottedUEs, freqAllocation, mcsIndex] = runSchedulingStrategyRAT1(obj, schedulerInput);

            numAllottedUEs = length(allottedUEs);
            % Select rank and precoding matrix for the eligible UEs
            tpmi = zeros(length(allottedUEs), obj.NumResourceBlocks); % To store selected precoding matrices for the UE
            newTxGrantCount = 0;

            for index = 1:numAllottedUEs
                selectedUE = allottedUEs(index);
                % Allot RBs to the selected UE in this TTI
                [rank, tpmi(allottedUEs(index), :), numAntennaPorts] = selectRankAndPrecodingMatrixUL(obj, obj.CSIMeasurementUL(selectedUE), obj.NumSRSPorts(selectedUE));
                updatedRBStatus(freqAllocation(index, 1)+1 : freqAllocation(index, 1)+freqAllocation(index, 2)) = 1; % Mark as assigned

                % Fill the new transmission RAT-1 uplink grant properties
                grant = obj.ULGrantInfo;
                grant.RNTI = selectedUE;
                grant.Type = 'newTx';
                grant.ResourceAllocationType = 1;
                grant.FrequencyAllocation = freqAllocation(index, :);
                grant.StartSymbol = startSym;
                grant.NumSymbols = numSym;
                grant.SlotOffset = slotOffset; %%CHECK HERE: CAN WE USE THIS OFFSET FOR DELAY
                grant.MCS = mcsIndex(index);
                grant.MappingType = obj.PUSCHMappingType;
                grant.DMRSLength = obj.PUSCHDMRSLength;
                grant.NumLayers = rank;
                % Set number of CDM groups without data (1...3)
                if numSym > 1
                    grant.NumCDMGroupsWithoutData = 2;
                else
                    grant.NumCDMGroupsWithoutData = 1; % To ensure some REs for data
                end
                grant.NumAntennaPorts = numAntennaPorts;

                newTxGrantCount = newTxGrantCount + 1;
                newTxUEs(newTxGrantCount) = selectedUE;
                ulGrants{selectedUE} = grant;
            end
            % Assign the RNTI of UE which was assigned the last uplink resource
            if allottedUEs % Only update when there is resource assignment
                obj.LastSelectedUEUL =  allottedUEs(index);
            end

            % Calculate a single TPMI value for the PUSCH assignment to UEs
            % from the TPMI values of all the RBs allotted. Also select a
            % free HARQ process to be used for uplink over the selected RBs.
            % It was already ensured that UEs in allottedUEs set have at least
            % one free HARQ process before deeming them eligible for
            % getting resources for new transmission
            for i = 1:length(allottedUEs)
                selectedUE = allottedUEs(i);
                grant = ulGrants{selectedUE};
                grantRBs = grant.FrequencyAllocation(1):grant.FrequencyAllocation(1) + ...
                    grant.FrequencyAllocation(2) - 1;
                tpmiRBs = tpmi(selectedUE, grantRBs+1);
                grant.TPMI = floor(mean(tpmiRBs)); % Taking average of the measured TPMI on grant RBs
                % Select one HARQ process, update its context to reflect grant
                selectedHarqId = findFreeUEHarqProcess(obj, obj.ULType, selectedUE);
                harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesUL(selectedUE, selectedHarqId+1), 1);
                grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));

                grant.HARQID = selectedHarqId; % Fill HARQ id in grant
                % Toggle the NDI for new transmission
                if obj.HarqNDIUL(grant.RNTI, selectedHarqId + 1)
                    grant.NDI = 0;
                else
                    grant.NDI = 1;
                end
                obj.HarqNDIUL(grant.RNTI, selectedHarqId+1) = grant.NDI; % Update the NDI context for the HARQ process
                obj.HarqStatusUL{selectedUE, selectedHarqId+1} = grant; % Mark HARQ process as busy
                ulGrants{selectedUE} = grant;
            end
            newTxUEs = newTxUEs(1 : newTxGrantCount);
            ulGrants = ulGrants(~cellfun('isempty',ulGrants)); % Remove all empty elements
        end

        function [newTxUEs, updatedRBGStatus, dlGrants] = scheduleNewTxDL(obj, scheduledSlot, eligibleUEs, startSym, numSym, rbgOccupancyBitmap, numUEsRetx)
            %scheduleNewTxDL Assign resources of a set of contiguous DL symbols representing a TTI, of the specified slot for new downlink transmissions
            % Return the downlink assignments for the UEs which are allotted
            % new transmission opportunity and the RBG-occupancy-status to
            % convey what all RBGs are used. Eligible set of UEs are passed
            % as input along with the bitmap of occupancy status of RBGs
            % of the slot getting scheduled. Only RBGs marked as 0 are
            % available for assignment to UEs

            numEligibleUEs = min(length(eligibleUEs), obj.MaxNumUsersPerTTI - numUEsRetx);
            % Select index of the first UE for scheduling. After the last selected UE,
            % go in sequence and find index of the first eligible UE
            scheduledUEIndex = find(eligibleUEs>obj.LastSelectedUEDL, 1);
            if isempty(scheduledUEIndex)
                scheduledUEIndex = 1;
            end

            % Shift eligibleUEs set such that first eligible UE (as per
            % round-robin assignment) is at first index
            eligibilityOrder = circshift(eligibleUEs,  [0 -(scheduledUEIndex-1)]);
            eligibleUEs = eligibilityOrder(1:numEligibleUEs);

            % Stores UEs which get new transmission opportunity
            newTxUEs = zeros(length(eligibleUEs), 1);

            % Stores DL grants of the TTI
            dlGrants = cell(length(eligibleUEs), 1);

            % To store the MCS of all the RBGs allocated to UEs. As PDSCH
            % assignment to a UE must have a single MCS even if multiple
            % RBGs are allotted, average of all the values is taken
            rbgMCS = -1*ones(length(eligibleUEs), obj.NumRBGs);

            % To store allotted RB count to UE in the slot
            allottedRBCount = zeros(length(eligibleUEs), 1);

            % Holds updated RBG occupancy status as the RBGs keep getting
            % allotted for new transmissions
            updatedRBGStatus = rbgOccupancyBitmap;

            % Calculate offset of scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot; %%CHECK HERE: SHOULD WE ALSO CHANGE THIS FUNCTION?
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Select rank and precoding matrix for the eligible UEs
            numEligibleUEs = length(eligibleUEs);
            W = cell(numEligibleUEs, 1); % To store selected precoding matrices for the UEs
            rank = zeros(numEligibleUEs, 1); % To store selected rank for the UEs
            rbRequirement = zeros(numEligibleUEs, 1); % To store RB requirement for UEs
            for i=1:numEligibleUEs
                [rank(i), W{i}] = selectRankAndPrecodingMatrixDL(obj, obj.CSIMeasurementDL(eligibleUEs(i)), ...
                    obj.NumCSIRSPorts(eligibleUEs(i)));
                rbRequirement(i) = calculateRBRequirement(obj, eligibleUEs(i), 0, startSym, numSym, rank(i));
            end

            % For each available RBG, based on the scheduling strategy
            % select the most appropriate UE. Also ensure that the number of
            % RBs allotted for a UE in the slot does not exceed the limit as
            % defined by the class property 'RBAllocationLimitDL'
            RBGEligibleUEs = eligibleUEs; % To keep track of UEs currently eligible for RBG allocations in this slot
            newTxGrantCount = 0;
            numFreeRBG = length(find(rbgOccupancyBitmap==0));
            assignedNumRBG = 0;
            perUEMinShare = floor(numFreeRBG/numEligibleUEs);
            lastGrantedUE = obj.LastSelectedUEDL;
            for i = 1:length(rbgOccupancyBitmap)
                % Resource block group is free
                if ~rbgOccupancyBitmap(i)
                    RBGIndex = i-1;
                    schedulerInput = createSchedulerInput(obj, obj.DLType, scheduledSlot, RBGEligibleUEs, rank, RBGIndex, startSym, numSym);
                    % Run the scheduling strategy to select a UE for the RBG and appropriate MCS
                    [selectedUEs, mcsIndices] = runSchedulingStrategy(obj, schedulerInput);
                    if selectedUEs(1) ~= -1 % If RBG is assigned to any UE
                        assignedNumRBG = assignedNumRBG+1;
                        updatedRBGStatus(i) = 1; % Mark as assigned
                        obj.LastSelectedUEDL = selectedUEs(1);
                        for idx = 1:length(selectedUEs)
                            selectedUE = selectedUEs(idx);
                            mcs = mcsIndices(idx);
                            selectedUEIdx = find(eligibleUEs == selectedUE, 1, 'first'); % Find UE index in eligible UEs set
                            rbgMCS(selectedUEIdx, i) = mcs;
                            if isempty(find(newTxUEs == selectedUE,1))
                                % Selected UE is allotted first RBG in this TTI
                                grant = obj.DLGrantInfo;
                                grant.RNTI = selectedUE;
                                grant.Type = 'newTx';
                                grant.ResourceAllocationType = 0;
                                grant.FrequencyAllocation = zeros(1, length(rbgOccupancyBitmap));
                                grant.FrequencyAllocation(RBGIndex+1) = 1;
                                grant.StartSymbol = startSym;
                                grant.NumSymbols = numSym;
                                grant.SlotOffset = slotOffset; %% CHECK HERE
                                grant.FeedbackSlotOffset = getPDSCHFeedbackSlotOffset(obj, slotOffset);
                                grant.MappingType = obj.PDSCHMappingType;
                                grant.DMRSLength = obj.PDSCHDMRSLength;
                                grant.NumLayers = rank(selectedUEIdx);
                                grant.PrecodingMatrix = W{selectedUEIdx};
                                if (idx > 1)
                                    grant.MUMIMO = 1; % Mark this grant as paired UE
                                end
                                grant.NumCDMGroupsWithoutData = 2; % Number of CDM groups without data (1...3)
                                csiResourceIndicator = obj.CSIMeasurementDL(selectedUE).CSIResourceIndicator;
                                if isempty(csiResourceIndicator)
                                    grant.BeamIndex = [];
                                else
                                    grant.BeamIndex = (obj.SSBIdx(selectedUE)-1)*obj.NumCSIRSBeams + csiResourceIndicator;
                                end

                                newTxGrantCount = newTxGrantCount + 1;
                                newTxUEs(newTxGrantCount) = selectedUE;
                                dlGrants{selectedUEIdx} = grant;
                                lastGrantedUE = selectedUE; % Update UE with last DL grant in the TTI
                            else
                                % Add RBG to the UE's grant
                                grant = dlGrants{selectedUEIdx};
                                grant.FrequencyAllocation(RBGIndex+1) = 1;
                                dlGrants{selectedUEIdx} = grant;
                            end

                            if isempty(find(newTxUEs==0, 1)) && assignedNumRBG >= (perUEMinShare*numEligibleUEs)
                                % Assign extra RBGs randomly
                                obj.LastSelectedUEDL = RBGEligibleUEs(randi(length(RBGEligibleUEs)));
                            end

                            if RBGIndex < obj.NumRBGs-1
                                allottedRBCount(selectedUEIdx) = allottedRBCount(selectedUEIdx) + obj.RBGSize;
                                % Check if the UE which got this RBG remains
                                % eligible for further RBGs in this TTI, as per
                                % set 'RBAllocationLimitDL'.
                                nextRBGSize = obj.RBGSize;
                                if RBGIndex == obj.NumRBGs-2 % If next RBG index is the last one in BWP
                                    nextRBGSize = obj.NumResourceBlocks - ((RBGIndex+1) * obj.RBGSize);
                                end
                                if allottedRBCount(selectedUEIdx) > (obj.RBAllocationLimitDL - nextRBGSize) || ...
                                        allottedRBCount(selectedUEIdx) >= rbRequirement(selectedUEIdx)
                                    % Not eligible for next RBG as either either max RB allocation limit would
                                    % get breached, or RB requirement is satisfied for the UE
                                    RBGEligibleUEs = setdiff(RBGEligibleUEs, selectedUE, 'stable');
                                end
                            end
                        end
                    end
                end
            end

            % Calculate a single MCS value for the PDSCH assignment to UEs
            % from the MCS values of all the RBGs allotted. Also select a
            % free HARQ process to be used for downlink over the selected
            % RBGs. It was already ensured that UEs in eligibleUEs set have
            % at least one free HARQ process before deeming them eligible
            % for getting resources for new transmission
            for i = 1:length(eligibleUEs)
                % If any resources were assigned to this UE
                if ~isempty(dlGrants{i})
                    grant = dlGrants{i};
                    grant.MCS = obj.MCSForRBGBitmap(rbgMCS(i, :)); % Get a single MCS for all allotted RBGs
                    % Select one HARQ process, update its context to reflect
                    % grant
                    selectedHarqId = findFreeUEHarqProcess(obj, obj.DLType, eligibleUEs(i));
                    harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesDL(eligibleUEs(i), selectedHarqId+1), 1);
                    grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));
                    grant.HARQID = selectedHarqId; % Fill HARQ ID
                    % Toggle the NDI for new transmission
                    if obj.HarqNDIDL(grant.RNTI, selectedHarqId+1)
                        grant.NDI = 0;
                    else
                        grant.NDI = 1;
                    end
                    obj.HarqStatusDL{eligibleUEs(i), selectedHarqId+1} = grant; % Mark HARQ process as busy
                    dlGrants{i} = grant;
                end
            end
            newTxUEs = newTxUEs(1 : newTxGrantCount);
            dlGrants = dlGrants(~cellfun('isempty',dlGrants)); % Remove all empty elements
            obj.LastSelectedUEDL = lastGrantedUE;
        end

        function [newTxUEs, updatedRBStatus, dlGrants] = scheduleNewTxDLRAT1(obj, scheduledSlot, eligibleUEs, startSym, numSym, rbOccupancyBitmap, numUEsRetx) %% CHECK HERE: NOT SURE HOW RAT1 IS DIFFERENT
            %scheduleNewTxDLRAT1 Assign resources of a set of contiguous DL symbols representing a TTI, of the specified slot for new downlink transmissions
            % Return the downlink assignments, the UEs which are allotted
            % new transmission opportunity and the RB-occupancy-status to
            % convey what all RBs are used. Eligible set of UEs are passed
            % as input along with the bitmap of occupancy status of RBs for
            % the slot getting scheduled. Only RBs marked as 0 are
            % available for assignment to UEs

            % Stores UEs which get new transmission opportunity
            newTxUEs = zeros(length(eligibleUEs), 1);

            % Stores DL grants of this TTI
            dlGrants = cell(length(eligibleUEs), 1);

            % Holds updated RB occupancy status as the RBs keep getting
            % allotted for new transmissions
            updatedRBStatus = rbOccupancyBitmap;

            % Calculate offset of scheduled slot from the current slot
            slotOffset = scheduledSlot - obj.CurrSlot;
            if scheduledSlot < obj.CurrSlot
                slotOffset = slotOffset + obj.NumSlotsFrame;
            end

            % Create the input structure for scheduling strategy
            schedulerInput = struct();
            schedulerInput.eligibleUEs = eligibleUEs;
            schedulerInput.bufferStatus = sum(obj.BufferStatusDL(eligibleUEs, :), 2);
            schedulerInput.rbOccupancyBitmap = rbOccupancyBitmap;
            schedulerInput.rbAllocationLimit = obj.RBAllocationLimitDL;
            schedulerInput.numUEsRetx = numUEsRetx;
            schedulerInput.linkDir = 0; % Downlink

            W = cell(length(eligibleUEs), 1); % To store selected precoding matrices for the UEs
            rank = zeros(length(eligibleUEs), 1); % To store selected rank for the UE
            for i = 1:length(eligibleUEs)
                schedulerInput.channelQuality(eligibleUEs(i), :) = obj.CSIMeasurementDL(eligibleUEs(i)).CQI;
                [rank(i), W{i}] = selectRankAndPrecodingMatrixDL(obj, obj.CSIMeasurementDL(eligibleUEs(i)), ...
                    obj.NumCSIRSPorts(eligibleUEs(i)));
                schedulerInput.rbRequirement(eligibleUEs(i)) = obj.calculateRBRequirement(eligibleUEs(i), 0, ...
                    startSym, numSym, rank(i));
            end

            % For MU-MIMO configuration
            schedulerInput.mcsRBG = zeros(numel(eligibleUEs), 2);
            schedulerInput.cqiRBG = schedulerInput.channelQuality;
            schedulerInput.numSym = numSym;
            schedulerInput.selectedRank = rank;
            schedulerInput.lastSelectedUE = obj.LastSelectedUEDL;
            cqiSetRBG = floor(sum(schedulerInput.cqiRBG, 2)/size(schedulerInput.cqiRBG, 2));

            for i = 1:numel(eligibleUEs)
                mcsRBG = getMCSIndex(obj, cqiSetRBG(i),schedulerInput.linkDir);
                schedulerInput.mcsRBG(i, 1) = mcsRBG; % MCS value
            end

            % Implement round robin scheduling strategy
            [allottedUEs, freqAllocation, mcsIndex, pairedStatus] = runSchedulingStrategyRAT1(obj, schedulerInput);

            numAllottedUEs = length(allottedUEs);
            % Select rank and precoding matrix for the eligible UEs
            newTxGrantCount = 0;

            for index = 1:numAllottedUEs
                selectedUE = allottedUEs(index);
                % Allot RBs to the selected UE in this TTI
                selectedUEIdx = find(eligibleUEs == selectedUE, 1, 'first'); % Find UE index in eligible UEs set
                updatedRBStatus(freqAllocation(index, 1)+1 : freqAllocation(index, 1)+freqAllocation(index, 2)) = 1; % Mark as assigned

                % Fill the new transmission RAT-1 downlink grant properties
                grant = obj.DLGrantInfo;
                grant.RNTI = selectedUE;
                grant.Type = 'newTx';
                grant.ResourceAllocationType = 1;
                grant.FrequencyAllocation = freqAllocation(index, :);
                grant.StartSymbol = startSym;
                grant.NumSymbols = numSym;
                grant.SlotOffset = slotOffset;
                grant.MCS = mcsIndex(index);
                grant.FeedbackSlotOffset = getPDSCHFeedbackSlotOffset(obj, slotOffset);
                grant.MappingType = obj.PDSCHMappingType;
                grant.DMRSLength = obj.PDSCHDMRSLength;
                grant.NumLayers = rank(selectedUEIdx);
                grant.PrecodingMatrix = W{selectedUEIdx};
                grant.MUMIMO = pairedStatus(index); % Mark this grant as paired UE
                grant.NumCDMGroupsWithoutData = 2; % Number of CDM groups without data (1...3)
                csiResourceIndicator = obj.CSIMeasurementDL(selectedUE).CSIResourceIndicator;
                if isempty(csiResourceIndicator)
                    grant.BeamIndex = [];
                else
                    grant.BeamIndex = (obj.SSBIdx(selectedUE)-1)*obj.NumCSIRSBeams + csiResourceIndicator;
                end

                newTxGrantCount = newTxGrantCount + 1;
                newTxUEs(newTxGrantCount) = selectedUE;
                dlGrants{selectedUE} = grant;
            end
            % Assign the RNTI of UE which was assigned the last downlink resource
            if allottedUEs % Only update when there is resource assignment
                obj.LastSelectedUEDL =  allottedUEs(index);
            end

            % Select a free HARQ process to be used for downlink over the
            % selected RBs. It was already ensured that UEs in allottedUEs
            % set have at least one free HARQ process before deeming them
            % eligible for getting resources for new transmission
            for i = 1:length(allottedUEs)
                selectedUE = allottedUEs(i);
                grant = dlGrants{selectedUE};
                % Select one HARQ process, update its context to reflect
                % grant
                selectedHarqId = findFreeUEHarqProcess(obj, obj.DLType, selectedUE);
                harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesDL(selectedUE, selectedHarqId+1), 1);
                grant.RV = harqProcess.RVSequence(harqProcess.RVIdx(1));

                grant.HARQID = selectedHarqId; % Fill HARQ id in grant
                % Toggle the NDI for new transmission
                if obj.HarqNDIDL(grant.RNTI, selectedHarqId + 1)
                    grant.NDI = 0;
                else
                    grant.NDI = 1;
                end
                obj.HarqNDIDL(grant.RNTI, selectedHarqId+1) = grant.NDI; % Update the NDI context for the HARQ process
                obj.HarqStatusDL{selectedUE, selectedHarqId+1} = grant; % Mark HARQ process as busy
                dlGrants{selectedUE} = grant;
            end
            newTxUEs = newTxUEs(1 : newTxGrantCount);
            dlGrants = dlGrants(~cellfun('isempty',dlGrants)); % Remove all empty elements
        end

        function k1 = getPDSCHFeedbackSlotOffset(obj, PDSCHSlotOffset) %% CHECK HERE: k1 indicates the number of time slot between  PDSCH and HARQ Ack/Nack transmission, so should be not usefull
            %getPDSCHFeedbackSlotOffset Calculate k1 i.e. slot offset of feedback (ACK/NACK) transmission from the PDSCH transmission slot

            % PDSCH feedback is currently supported to be sent with
            % at least 1 slot gap after Tx slot i.e k1=2 is the earliest
            % possible value, subjected to the UL time availability. For
            % FDD, k1 is set as 2 as every slot is a UL slot. For TDD, k1
            % is set to slot offset of first upcoming slot with UL symbols.
            % Input 'PDSCHSlotOffset' is the slot offset of PDSCH
            % transmission slot from the current slot
            if ~obj.DuplexMode % FDD
                k1 = 2;
            else % TDD
                % Calculate offset of first slot containing UL symbols, from PDSCH transmission slot
                k1 = 2;
                while(k1 < obj.NumSlotsFrame)
                    slotIndex = mod(obj.CurrDLULSlotIndex + PDSCHSlotOffset + k1, obj.NumDLULPatternSlots);
                    if find(obj.DLULSlotFormat(slotIndex + 1, :) == obj.ULType, 1)
                        break; % Found a slot with UL symbols
                    end
                    k1 = k1 + 1;
                end
            end
        end

        function schedulerInput = createSchedulerInput(obj, linkDir, slotNum, eligibleUEs, selectedRank, rbgIndex, startSym, numSym) %% CHECK HERE: ARENT THE SCHEDULING DONE IN THE FUNCTION ABOVE?
            %createSchedulerInput Create the input structure for scheduling strategy
            %
            % linkDir       - Link direction for scheduler (0 means DL and 1
            %                   means UL)
            % slotNum       - Slot whose TTI is currently getting scheduled
            % eligibleUEs   - RNTI of the eligible UEs contending for the RBG
            % selectedRank  - Selected rank for UEs. It is an array of size eligibleUEs
            % rbgIndex      - Index of the RBG (which is getting scheduled) in the bandwidth
            % startSym      - Start symbol of the TTI getting scheduled
            % numSym        - Number of symbols in the TTI getting scheduled
            %
            % schedulerInput structure contains the following fields which
            % scheduler uses (not necessarily all the information) for
            % selecting the UE, which RBG would be assigned to:
            %   eligibleUEs  - RNTI of the eligible UEs contending for the RBG
            %   selectedRank - Selected rank for UEs. It is an array of size eligibleUEs
            %   RBGIndex     - RBG index in the slot which is getting scheduled
            %   slotNum      - Slot whose TTI is currently getting scheduled
            %   startSym     - Start symbol of TTI
            %   numSym       - Number of symbols in TTI
            %   RBGSize      - RBG Size in terms of number of RBs
            %   cqiRBG       - Channel quality on RBG for UEs. N-by-P matrix with CQI
            %                  values for UEs on different RBs of RBG. 'N' is number of
            %                  eligible UEs and 'P' is RBG size in RBs
            %   mcsRBG       - MCS for eligible UEs based on the CQI values
            %                  on the RBs of RBG. N-by-2 matrix where 'N'
            %                  is number of eligible UEs. For each eligible
            %                  UE, it has MCS index (first column) and
            %                  efficiency (bits/symbol considering both
            %                  Modulation and coding scheme)
            %   bufferStatus - Buffer status of UEs. Vector of N elements
            %                  where 'N' is number of eligible UEs,
            %                  containing pending buffer status for UEs
            %   ttiDur       - TTI duration in ms
            %   UEs          - RNTI of all the UEs (even the non-eligible ones for this RBG)
            %   lastSelectedUE - The RNTI of UE which was assigned the last scheduled RBG

            schedulerInput = obj.SchedulerInput;
            if linkDir % Uplink
                numResourceBlocks = obj.NumResourceBlocks;
                rbgSize = obj.RBGSize;
                ueBufferStatus = obj.BufferStatusULPerUE;
                channelQuality = zeros(length(obj.UEs), obj.NumResourceBlocks);
                for i = 1:length(eligibleUEs)
                    channelQuality(eligibleUEs(i), :) = obj.CSIMeasurementUL(eligibleUEs(i)).CQI;
                end
                mcsTable = obj.MCSTableUL;
                schedulerInput.lastSelectedUE = obj.LastSelectedUEUL;
            else % Downlink
                numResourceBlocks = obj.NumResourceBlocks;
                rbgSize = obj.RBGSize;
                ueBufferStatus = obj.BufferStatusDLPerUE;
                channelQuality = zeros(length(obj.UEs), obj.NumResourceBlocks);
                for i = 1:length(eligibleUEs)
                    channelQuality(eligibleUEs(i), :) = obj.CSIMeasurementDL(eligibleUEs(i)).CQI;
                end
                mcsTable = obj.MCSTableDL;
                schedulerInput.lastSelectedUE = obj.LastSelectedUEDL;
            end
            schedulerInput.linkDir = linkDir;
            startRBIndex = rbgSize * rbgIndex;
            % Last RBG can have lesser RBs as number of RBs might not
            % be completely divisible by RBG size
            lastRBIndex = min(startRBIndex + rbgSize - 1, numResourceBlocks - 1);
            schedulerInput.eligibleUEs = eligibleUEs;
            schedulerInput.slotNum = slotNum;
            schedulerInput.startSym = startSym;
            schedulerInput.numSym = numSym;
            schedulerInput.RBGIndex = rbgIndex;
            schedulerInput.RBGSize = lastRBIndex - startRBIndex + 1; % Number of RBs in this RBG
            schedulerInput.bufferStatus = sum(ueBufferStatus(eligibleUEs, :), 2);
            schedulerInput.cqiRBG = channelQuality(eligibleUEs, startRBIndex+1 : lastRBIndex+1);
            cqiSetRBG = floor(sum(schedulerInput.cqiRBG, 2)/size(schedulerInput.cqiRBG, 2));
            schedulerInput.mcsRBG = zeros(numel(eligibleUEs), 2);
            for i = 1:numel(eligibleUEs)
                mcsRBG = getMCSIndex(obj, cqiSetRBG(i), linkDir);

                schedulerInput.mcsRBG(i, 1) = mcsRBG; % MCS value
                schedulerInput.mcsRBG(i, 2) = mcsTable(mcsRBG + 1, 3); % Spectral efficiency
            end
            schedulerInput.ttiDur = (numSym * obj.SlotDuration)/14; % In ms
            schedulerInput.UEs = obj.UEs;
            schedulerInput.selectedRank = selectedRank;
        end

        function harqId = findFreeUEHarqProcess(obj, linkDir, rnti)
            %findFreeUEHarqProcess Returns index of a free uplink or downlink HARQ process of UE, based on the link direction (UL/DL)

            harqId = -1;
            numHarq = obj.NumHARQ;
            if linkDir % Uplink
                harqProcessInfo = obj.HarqStatusUL(rnti, :);
            else % Downlink
                harqProcessInfo = obj.HarqStatusDL(rnti, :);
            end
            for i = 1:numHarq
                harqStatus = harqProcessInfo{i};
                if isempty(harqStatus) % Free process
                    harqId = i-1;
                    return;
                end
            end
        end

        function eligibleUEsList = getNewTxEligibleUEs(obj, linkDir, reTxUEs)
            %getNewTxEligibleUEs Return the UEs eligible for getting resources for new transmission
            % Eligible UEs must meet the criteria:
            % (i) UE did not get retransmission opportunity in the current TTI
            % (ii) UE must have requirement of resources
            % (iii) UE must have at least one free HARQ process

            noReTxUEs = setdiff(obj.UEs, reTxUEs, 'stable'); % UEs which did not get any re-Tx opportunity
            numNoReTxUEs = length(noReTxUEs);
            eligibleUEs = zeros(1,numNoReTxUEs);
            numEligibleUEs = 0;
            % Eliminate further the UEs which do not have free HARQ process
            for i = 1:numNoReTxUEs
                freeHarqId = findFreeUEHarqProcess(obj, linkDir, noReTxUEs(i));
                if freeHarqId == -1
                    % No HARQ process free on this UE, so not eligible
                    continue;
                end
                if linkDir==0 % DL
                    bufferAmount = obj.BufferStatusDLPerUE(noReTxUEs(i));
                else % UL
                    bufferAmount = obj.BufferStatusULPerUE(noReTxUEs(i));
                end
                if bufferAmount == 0
                    % UE does not require any resources
                    continue;
                end
                numEligibleUEs = numEligibleUEs + 1;
                eligibleUEs(numEligibleUEs) = noReTxUEs(i);
            end
            eligibleUEsList = eligibleUEs(1:numEligibleUEs);
        end

        function rbRequirement = calculateRBRequirement(obj, rnti, linkDir, startSym, numSym, rank)
            %calculateRBRequirement Calculate the number of RBs required based on the
            %currently queued data
            
            % Calculate RB requirement for the UE
            if linkDir==0 % DL
                mcsIndex =  obj.getMCSIndex(obj.CSIMeasurementDL(rnti).CQI(1), linkDir); % Assuming wideband CQI
                mcsTable = obj.MCSTableDL;
                mappingType = obj.PDSCHMappingType;
                bufferedBits = obj.BufferStatusDLPerUE(rnti)*8;
            else % UL
                mcsIndex =  obj.getMCSIndex(obj.CSIMeasurementUL(rnti).CQI(1), linkDir); % Assuming wideband CQI
                mcsTable = obj.MCSTableUL;
                mappingType = obj.PUSCHMappingType;
                bufferedBits = obj.BufferStatusULPerUE(rnti)*8;
            end
            numCDMGroups = 2;
            mcsInfo = mcsTable(mcsIndex+1, :);
            modScheme = modSchemeStr(obj, mcsInfo(1));
            codeRate = mcsInfo(2)/1024;
            bitsPerRB = tbsCapability(obj, linkDir, rank, mappingType, startSym, numSym, 0, ...
                modScheme, codeRate, numCDMGroups);
            rbRequirement = ceil(bufferedBits/bitsPerRB);
        end

        function [isAssigned, allottedBitmap, mcs] = getRetxResourcesNonAdaptive(obj, linkDir, ...
                rbgOccupancyBitmap, numSym, lastGrant)
            %getRetxResourcesNonAdaptive Assign the retransmission resources in a
            %non-adaptive manner

            isAssigned = 0;
            mcs = 0;
            numRBGs = obj.NumRBGs;
            allottedBitmap = zeros(1, numRBGs);

            % Assume the rank and MCS to be similar as original transmission. Ensure
            % that total REs are at least equal to REs in original grant
            rbgBitmapLastGrant = lastGrant.FrequencyAllocation;
            rbLastGrant = convertRBGBitmapToRBs(obj, rbgBitmapLastGrant);
            requiredNumRB = ceil((length(rbLastGrant)*lastGrant.NumSymbols)/numSym);
            requiredNumRBG = ceil(requiredNumRB/obj.RBGSize);

            % RBG set used in last grant
            rbgLastGrant = find(rbgBitmapLastGrant == 1);
            % Assign the RBGs of last grant (whichever are free)
            freeRBGs = rbgLastGrant(rbgOccupancyBitmap(rbgLastGrant) == 0);
            assignedRBGs = freeRBGs(1:min(requiredNumRBG, length(freeRBGs)));
            rbgOccupancyBitmap(assignedRBGs) = 1;
            allottedBitmap(assignedRBGs) = 1;
            assignedNumRB = length(convertRBGBitmapToRBs(obj, allottedBitmap));
            % Calculate the number of RBGs required (if any) after above assignment
            requiredNumRBG = ceil((requiredNumRB - assignedNumRB)/obj.RBGSize);
            if requiredNumRBG > 0
                % If one or more RBGs cannot be repeated as per the last
                % grant then assign equivalent number of RBGs somewhere
                % else in the bandwidth. Start assigning first free RBG
                % onwards

                % Do not consider last RBG if the last RBG has lesser
                % number of RB since it can result in lower tbs
                % capability of grant
                if mod(obj.NumResourceBlocks, obj.RBGSize)
                    rbgOccupancyBitmap = rbgOccupancyBitmap(1:end-1);
                end
                freeRBGs = find(rbgOccupancyBitmap==0);
                if length(freeRBGs) >= requiredNumRBG
                    isAssigned = 1;
                    assignedRBGs = [assignedRBGs freeRBGs(1:requiredNumRBG)];
                    allottedBitmap(assignedRBGs) = 1;
                    mcs = lastGrant.MCS;
                end
            else
                isAssigned = 1;
                mcs = lastGrant.MCS;
            end
        end

        function [isAssigned, allottedBitmap, mcs] = getRetxResourcesAdaptive(obj, linkDir, rnti, ...
                tbs, rbgOccupancyBitmap, startSym, numSym, rank, lastGrant)
            %getRetxResourcesAdaptive Assign the retransmission resources with rate
            %adaptation

            % A set of RBGs are chosen for retransmission grant along with
            % the corresponding MCS. The approach used is to find the set
            % of RBGs (which are free) with best channel quality w.r.t UE,
            % to increase the successful reception probability

            cdmGroupsWithoutData = 2;
            rbgSize = obj.RBGSize;
            cqiRBGs = zeros(obj.NumRBGs, 1);
            numRBGs = obj.NumRBGs;
            allottedBitmap = zeros(1, numRBGs);
            numResourceBlocks = obj.NumResourceBlocks;
            if linkDir % Uplink
                cqiRBs = obj.CSIMeasurementUL(rnti).CQI;
                mcsTable = obj.MCSTableUL;
                mappingType = obj.PUSCHMappingType;
                if numSym == 1
                    cdmGroupsWithoutData = 1;
                end
            else % Downlink
                cqiRBs = obj.CSIMeasurementDL(rnti).CQI;
                mcsTable = obj.MCSTableDL;
                mappingType = obj.PDSCHMappingType;
            end

            isAssigned = 0;
            mcs = 0;
            % Calculate average CQI for each RBG
            for i = 1:numRBGs
                if ~rbgOccupancyBitmap(i)
                    startRBIndex = (i-1)*rbgSize + 1;
                    lastRBIndex = min(i*rbgSize, numResourceBlocks);
                    cqiForRBs = cqiRBs(startRBIndex : lastRBIndex);
                    cqiRBGs(i) = floor(sum(cqiForRBs)/numel(cqiForRBs));
                end
            end

            % Get the indices of RBGs in decreasing order of their CQI
            % values. Then start assigning the RBGs in this order, if the
            % RBG is free to use. Continue assigning the RBGs till the tbs
            % requirement is satisfied.
            [~, sortedIndices] = sort(cqiRBGs, 'descend');
            requiredBits = tbs;
            mcsRBGs = -1*ones(numRBGs, 1);
            % Get number of PDSCH/PUSCH REs per PRB
            [~, nREPerPRB] = tbsCapability(obj, linkDir, rank, mappingType, startSym, ...
                numSym, 1, 'QPSK', mcsTable(1,2)/1024, cdmGroupsWithoutData);
            for i = 1:numRBGs
                if ~rbgOccupancyBitmap(sortedIndices(i)) % Free RBG
                    % Calculate transport block bits capability of RBG
                    cqiRBG = cqiRBGs(sortedIndices(i));
                    mcsIndex = getMCSIndex(obj, cqiRBG, linkDir);
                    mcsInfo = mcsTable(mcsIndex + 1, :);
                    numRBsRBG = rbgSize;
                    if sortedIndices(i) == numRBGs && mod(numResourceBlocks, rbgSize) ~= 0
                        % Last RBG might have lesser number of RBs
                        numRBsRBG = mod(numResourceBlocks, rbgSize);
                    end
                    servedBits = rank*nREPerPRB*numRBsRBG*mcsInfo(3); % Approximate TBS bits served by current RBG
                    requiredBits = max(0, requiredBits - servedBits);
                    allottedBitmap(sortedIndices(i)) = 1; % Selected RBG
                    mcsRBGs(sortedIndices(i)) = mcsIndex; % MCS for RBG
                    if ~requiredBits
                        % Retransmission TBS requirement have met
                        isAssigned = 1;
                        rbgMCS = mcsRBGs(mcsRBGs>=0);
                        mcs = floor(sum(rbgMCS)/numel(rbgMCS)); % Average MCS
                        break;
                    end
                end
            end

            % Although TBS requirement is fulfilled by RBG set with
            % corresponding MCS values calculated above but as the
            % retransmission grant needs to have a single MCS, so average
            % MCS of selected RBGs might bring down the tbs capability of
            % grant below the required tbs. If that happens, select the
            % biggest of the MCS values to satisfy the TBS requirement
            if isAssigned
                grantRBs = convertRBGBitmapToRBs(obj, allottedBitmap);
                mcsInfo = mcsTable(mcs + 1, :);
                modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme
                modScheme = modSchemeStr(obj, modSchemeBits);
                codeRate = mcsInfo(2)/1024;
                % Calculate tbs capability of grant
                actualServedBits = tbsCapability(obj, linkDir, rank, mappingType, startSym, ...
                    numSym, grantRBs, modScheme, codeRate, cdmGroupsWithoutData);
                if actualServedBits < tbs
                    % Average MCS is not sufficing, so taking the maximum MCS
                    % value
                    mcs = max(mcsRBGs);
                end
            else
                if all(allottedBitmap)
                    % Even if giving all the RBGs for retransmission grant
                    % is not sufficing then force the retransmission by
                    % sending the reTx with same MCS as last Tx
                    isAssigned = 1;
                    mcs = lastGrant.MCS;
                    if rank >= lastGrant.NumLayers % If rank of reTx is same then assign same set of RBGs
                        allottedBitmap = lastGrant.FrequencyAllocation;
                    else % To compensate for lesser rank, use all the RBGs
                        allottedBitmap = ones(1, length(rbgOccupancyBitmap));
                    end
                end
            end
        end

        function [isAssigned, frequencyAllocation, mcs] = getRetxResourcesAdaptiveRAT1(obj, linkDir, rnti, ...
                tbs, rbOccupancyBitmap, ~, startSym, numSym, rank, lastGrant)
            %getRetxResourcesAdaptiveRAT1 Based on the tbs, get the retransmission resources
            % A set of contiguous RBs are chosen for retransmission grant
            % along with the corresponding MCS.

            cdmGroupsWithoutData = 2;
            if linkDir % Uplink
                cqiRBs = obj.CSIMeasurementUL(rnti).CQI;
                totalRBs = obj.NumResourceBlocks;
                mcsTable = obj.MCSTableUL;
                mappingType = obj.PUSCHMappingType;
                if numSym == 1
                    cdmGroupsWithoutData = 1;
                end
            else % Downlink
                cqiRBs = obj.CSIMeasurementDL(rnti).CQI;
                totalRBs = obj.NumResourceBlocks;
                mcsTable = obj.MCSTableDL;
                mappingType = obj.PDSCHMappingType;
            end

            isAssigned = 0;
            frequencyAllocation = zeros(1,2);
            mcs=0;
            startRBIndex = find(~rbOccupancyBitmap, 1)-1;

            if startRBIndex >= 0
                % Calculate average CQI for the entire available bandwidth
                cqiForRB = cqiRBs(startRBIndex+1:end);
                avgCQI = floor(mean(cqiForRB));
                % Calculate average MCS value corresponding to avgCQI
                mcs = getMCSIndex(obj, avgCQI, linkDir);
                avgMCSInfo = mcsTable(mcs+1, :);

                modSchemeBits = modSchemeStr(obj, avgMCSInfo(1));
                codeRate = avgMCSInfo(2)/1024;
                % Get number of PDSCH/PUSCH REs per PRB
                [~, nREPerPRB] = tbsCapability(obj, linkDir, rank, mappingType, startSym, ...
                    numSym, 1, modSchemeBits, codeRate, cdmGroupsWithoutData);
                % Calculate transport block bits capability of RB
                servedBitsperRB = rank*nREPerPRB*avgMCSInfo(3); % Approximate TBS bits served by an RB having avgMCS
                % Calculate the number of RBs required with avgMCS
                requiredRB= ceil(tbs/servedBitsperRB);

                if requiredRB < (totalRBs-startRBIndex)
                    % Retransmission TBS requirement have met
                    isAssigned = 1;
                    frequencyAllocation = [startRBIndex requiredRB];
                else
                    if ~isAssigned && startRBIndex == 0
                        % Even if giving all the RBs for retransmission grant
                        % is not sufficing then force the retransmission by
                        % sending the reTx with same MCS as last Tx
                        isAssigned = 1;
                        mcs = lastGrant.MCS;
                        if rank >= lastGrant.NumLayers % If rank of reTx is same then assign same set of RBs
                            frequencyAllocation = lastGrant.FrequencyAllocation;
                        else % To compensate for lesser rank, use all the RBs
                            frequencyAllocation = [0 totalRBs];
                        end
                    end
                end
            end
        end

        function mcs = MCSForRBGBitmap(~, mcsValues)
            %MCSForRBGBitmap Calculates and returns single MCS value for the PUSCH assignment to a UE from the MCS values of all the RBGs allotted

            % Taking average of all the MCS values to reach the final MCS
            % value. This is just one way of doing it, it can be deduced
            % in any other way too
            validMCSValues = mcsValues(mcsValues>=0);
            mcs = floor(sum(validMCSValues)/numel(validMCSValues));
        end

        function [rank, W] = selectRankAndPrecodingMatrixDL(obj, csiReport, numCSIRSPorts)
            %selectRankAndPrecodingMatrixDL Select rank and precoding matrix based on the CSI report from the UE
            %   [RANK, W] = selectRankAndPrecodingMatrixDL(OBJ, RNTI,
            %   CSIREPORT, NUMCSIRSPORTS) selects the rank and precoding
            %   matrix for a UE.
            %
            %   CSIREPORT is the channel state information report. It is a
            %   structure with the fields: RankIndicator, PMISet, CQI
            %
            %   RANK is the selected rank i.e. the number of transmission
            %   layers
            %
            %   NUMCSIRSPORTS is number of CSI-RS ports for the UE
            %
            %   W is an array of size RANK-by-P-by-NPRG, where NPRG is the
            %   number of PRGs in the carrier and P is the number of CSI-RS
            %   ports. W defines a different precoding matrix of size
            %   RANK-by-P for each PRG. The effective PRG bundle size
            %   (precoder granularity) is Pd_BWP = ceil(NRB / NPRG). Valid
            %   PRG bundle sizes are given in TS 38.214 Section 5.1.2.3, and
            %   the corresponding values of NPRG, are as follows:
            %   Pd_BWP = 2 (NPRG = ceil(NRB / 2))
            %   Pd_BWP = 4 (NPRG = ceil(NRB / 4))
            %   Pd_BWP = 'wideband' (NPRG = 1)
            %
            % Rank selection procedure followed: Select the advised rank in the CSI report
            % Precoder selection procedure followed: Form the combined precoding matrix for
            % all the PRGs in accordance with the CSI report.
            %
            % The function can be modified to return rank and precoding
            % matrix of choice.

            rank = csiReport.RankIndicator;
            if numCSIRSPorts == 1 || isempty(csiReport.W)
                % Single antenna port or no PMI report received
                W = 1;
            else
                numPRGs =  ceil(obj.NumResourceBlocks/obj.PrecodingGranularity);
                W = complex(zeros(rank, numCSIRSPorts, numPRGs,1));
                for i=1:numPRGs
                    W(:,:,i) = csiReport.W.';
                end
            end
        end

        function [rank, tpmi, numAntennaPorts] = selectRankAndPrecodingMatrixUL(obj, csiReport, numSRSPorts)
            %selectRankAndPrecodingMatrixUL Select rank and precoding matrix based on the UL CSI measurement for the UE
            %   [RANK, TPMI, NumAntennaPorts] = selectRankAndPrecodingMatrixUL(OBJ, CSIREPORT, NUMSRSPORTS)
            %   selects the rank and precoding matrix for a UE.
            %
            %   CSIREPORT is the SRS-based channel state information measurement for the UE. It is a
            %   structure with the fields: RankIndicator, TPMI, CQI
            %
            %   NUMSRSPORTS Number of SRS ports used for CSI measurement
            %
            %   RANK is the selected rank i.e. the number of transmission
            %   layers
            %
            %   TPMI is transmitted precoding matrix indicator over the
            %   RBs of the bandwidth.
            %
            %   NUMANTENNAPORTS Number of antenna ports selected for the UE
            %
            % Rank selection procedure followed: Select the advised rank as
            % per the CSI measurement
            % Precoder selection procedure followed: Select the advised TPMI as
            % per the CSI measurement
            %
            % The function can be modified to return rank and precoding
            % matrix of choice.

            rank = csiReport.RankIndicator;
            % Fill the TPMI for each RB by keeping same value of TPMI for all
            % the RBs in the CSI subband
            tpmi = zeros(1, obj.NumResourceBlocks);
            numSubbands = length(csiReport.TPMI);
            subbandSize = ceil(obj.NumResourceBlocks/numSubbands);
            for i = 1:numSubbands-1
                tpmi((i-1)*subbandSize+1 : i*subbandSize) = csiReport.TPMI(i);
            end
            tpmi((numSubbands-1)*subbandSize+1:end) = csiReport.TPMI(end);
            numAntennaPorts = numSRSPorts;
        end

        function mcsRowIndex = getMCSIndex(obj, cqiIndex, linkDir)
            %getMCSIndex Returns the MCS row index.
            %   If fixed-MCS is configured, return the configured MCS index
            %   value, otherwise return based on cqi value

            if linkDir  % Uplink
                fixedMCS = obj.FixedMCSIndexUL;
                cqiTable = obj.CQITableUL;
                mcsTable = obj.MCSTableUL;
            else % Downlink
                fixedMCS = obj.FixedMCSIndexDL;
                cqiTable = obj.CQITableDL;
                mcsTable = obj.MCSTableDL;
            end

            if isempty(fixedMCS) % Channel-dependent MCS
                modulation = cqiTable(cqiIndex + 1, 1);
                codeRate = cqiTable(cqiIndex + 1, 2);

                for mcsRowIndex = 1:28 % MCS indices
                    if modulation ~= mcsTable(mcsRowIndex, 1)
                        continue;
                    end
                    if codeRate <= mcsTable(mcsRowIndex, 2)
                        break;
                    end
                end
                mcsRowIndex = mcsRowIndex - 1;
            else % Fixed MCS
                mcsRowIndex = fixedMCS;
            end
        end

        function rbSet = convertRBGBitmapToRBs(obj, rbgBitmap)
            %convertRBGBitmapToRBs Convert RBGBitmap to corresponding RB indices

            rbgSize = obj.RBGSize;
            numResourceBlocks = obj.NumResourceBlocks;

            rbSet = -1*ones(numResourceBlocks, 1); % To store RB indices of last UL grant
            for rbgIndex = 0:length(rbgBitmap)-1
                if rbgBitmap(rbgIndex+1)
                    % If the last RBG of BWP is assigned, then it
                    % might not have the same number of RBs as other RBG.
                    if rbgIndex == (length(rbgBitmap)-1)
                        rbSet((rbgSize*rbgIndex + 1) : end) = ...
                            rbgSize*rbgIndex : numResourceBlocks-1 ;
                    else
                        rbSet((rbgSize*rbgIndex + 1) : (rbgSize*rbgIndex + rbgSize)) = ...
                            (rbgSize*rbgIndex) : (rbgSize*rbgIndex + rbgSize -1);
                    end
                end
            end
            rbSet = rbSet(rbSet >= 0);
        end

        function modScheme = modSchemeStr(~, modSchemeBits)
            %modSchemeStr Return the modulation scheme string based on modulation scheme bits

            % Modulation scheme and corresponding bits/symbol
            fullmodlist = ["pi/2-BPSK", "BPSK", "QPSK", "16QAM", "64QAM", "256QAM"]';
            qm = [1 1 2 4 6 8];
            modScheme = fullmodlist((modSchemeBits == qm)); % Get modulation scheme string
        end

        function [servedBits, nREPerPRB] = tbsCapability(obj, linkDir, nLayers, mappingType,  ...
                startSym, numSym, prbSet, modScheme, codeRate, numCDMGroups)
            %tbsCapability Calculate the served bits and number of PDSCH/PUSCH REs per PRB

            if linkDir % Uplink
                % PUSCH configuration object
                pusch = obj.PUSCHConfig;
                pusch.SymbolAllocation = [startSym numSym];
                pusch.MappingType = mappingType;
                if mappingType == 'A'
                    dmrsAdditonalPos = obj.PUSCHDMRSAdditionalPosTypeA;
                else
                    dmrsAdditonalPos = obj.PUSCHDMRSAdditionalPosTypeB;
                end
                pusch.DMRS.DMRSAdditionalPosition = dmrsAdditonalPos;
                pusch.DMRS.NumCDMGroupsWithoutData = numCDMGroups;
                pusch.PRBSet = prbSet;
                pusch.Modulation = modScheme;
                [~, pxschIndicesInfo] = nrPUSCHIndices(obj.CarrierConfigUL, pusch);
                % Overheads in PUSCH transmission
                xOh = 0;
            else % Downlink
                % PDSCH configuration object
                pdsch = obj.PDSCHConfig;
                pdsch.SymbolAllocation = [startSym numSym];
                pdsch.MappingType = mappingType;
                if mappingType == 'A'
                    dmrsAdditonalPos = obj.PDSCHDMRSAdditionalPosTypeA;
                else
                    dmrsAdditonalPos = obj.PDSCHDMRSAdditionalPosTypeB;
                end
                pdsch.DMRS.DMRSAdditionalPosition = dmrsAdditonalPos;
                pdsch.DMRS.NumCDMGroupsWithoutData = numCDMGroups;
                pdsch.PRBSet = prbSet;
                pdsch.Modulation = modScheme;
                [~, pxschIndicesInfo] = nrPDSCHIndices(obj.CarrierConfigDL, pdsch);
                xOh = obj.XOverheadPDSCH;
            end

            servedBits = nrTBS(modScheme, nLayers, length(prbSet), ...
                pxschIndicesInfo.NREPerPRB, codeRate, xOh);
            nREPerPRB = pxschIndicesInfo.NREPerPRB;
        end

        function updateHARQContextDL(obj, grants)
            %updateHARQContextDL Update DL HARQ context based on the grants

            for grantIndex = 1:length(grants) % Update HARQ context
                grant = grants{grantIndex};
                harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesDL(grant.RNTI, grant.HARQID+1), 1);
                obj.HarqProcessesDL(grant.RNTI, grant.HARQID+1) = harqProcess;
                obj.HarqStatusDL{grant.RNTI, grant.HARQID+1} = grant; % Mark HARQ process as busy
                obj.HarqNDIDL(grant.RNTI, grant.HARQID+1) = grant.NDI;

                if strcmp(grant.Type, 'reTx')
                    % Clear the retransmission context for this HARQ
                    % process of the selected UE to make it ineligible
                    % for retransmission assignments
                    obj.RetransmissionContextDL{grant.RNTI, grant.HARQID+1} = [];
                end
            end
        end

        function updateHARQContextUL(obj, grants)
            %updateHARQContextUL Update UL HARQ context based on the grants

            for grantIndex = 1:length(grants) % Update HARQ context
                grant = grants{grantIndex};
                harqProcess = nr5g.internal.nrUpdateHARQProcess(obj.HarqProcessesUL(grant.RNTI, grant.HARQID+1), 1);
                obj.HarqProcessesUL(grant.RNTI, grant.HARQID+1) = harqProcess;
                obj.HarqStatusUL{grant.RNTI, grant.HARQID+1} = grant; % Mark HARQ process as busy
                obj.HarqNDIUL(grant.RNTI, grant.HARQID+1) = grant.NDI;

                if strcmp(grant.Type, 'reTx')
                    % Clear the retransmission context for this HARQ
                    % process of the selected UE to make it ineligible
                    % for retransmission assignments
                    obj.RetransmissionContextUL{grant.RNTI, grant.HARQID+1} = [];
                end
            end
        end

        function updateBufferStatusForGrants(obj, linkType, grants)
            %updateBufferStatusForGrants Update the buffer status by
            % reducing the UEs pending buffer amount based on the scheduled grants

            if linkType % Uplink
                mcsTable = obj.MCSTableUL;
                pusch = obj.PUSCHConfig;
                % UL carrier configuration object
                ulCarrierConfig = obj.CarrierConfigUL;
            else % Downlink
                mcsTable = obj.MCSTableDL;
                pdsch = obj.PDSCHConfig;
                % DL carrier configuration object
                dlCarrierConfig = obj.CarrierConfigDL;
            end

            for grantIdx = 1:length(grants)
                resourceAssignment = grants{grantIdx};
                if ~strcmp(resourceAssignment.Type, 'newTx') % Only consider newTx grants
                    continue;
                end
                rnti = resourceAssignment.RNTI;
                mcsInfo = mcsTable(resourceAssignment.MCS + 1, :);
                modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme
                codeRate = mcsInfo(2)/1024;
                % Modulation scheme and corresponding bits/symbol
                fullmodlist = ["pi/2-BPSK", "BPSK", "QPSK", "16QAM", "64QAM", "256QAM"]';
                qm = [1 1 2 4 6 8];
                modScheme = fullmodlist((modSchemeBits == qm)); % Get modulation scheme string

                if linkType % Uplink
                    pusch.SymbolAllocation = [resourceAssignment.StartSymbol resourceAssignment.NumSymbols];
                    pusch.MappingType = resourceAssignment.MappingType;
                    if pusch.MappingType == 'A'
                        dmrsAdditonalPos = obj.PUSCHDMRSAdditionalPosTypeA;
                    else
                        dmrsAdditonalPos = obj.PUSCHDMRSAdditionalPosTypeB;
                    end
                    pusch.DMRS.DMRSLength = resourceAssignment.DMRSLength;
                    pusch.DMRS.DMRSAdditionalPosition = dmrsAdditonalPos;
                    if obj.ResourceAllocationType % RAT-1
                        pusch.PRBSet = resourceAssignment.FrequencyAllocation(1):resourceAssignment.FrequencyAllocation(1) + ...
                            resourceAssignment.FrequencyAllocation(2) - 1;
                    else % RAT-0
                        pusch.PRBSet = convertRBGBitmapToRBs(obj, resourceAssignment.FrequencyAllocation);
                    end
                    pusch.Modulation = modScheme(1);
                    [~, puschIndicesInfo] = nrPUSCHIndices(ulCarrierConfig, pusch);
                    nLayers = 1;
                    achievedTxBits = nrTBS(modScheme(1), nLayers, length(pusch.PRBSet), ...
                        puschIndicesInfo.NREPerPRB, codeRate);
                    obj.BufferStatusULPerUE(rnti) = max(0, obj.BufferStatusULPerUE(rnti) - floor(achievedTxBits/8));
                else % Downlink
                    pdsch.SymbolAllocation = [resourceAssignment.StartSymbol resourceAssignment.NumSymbols];
                    pdsch.MappingType = resourceAssignment.MappingType;
                    if pdsch.MappingType == 'A'
                        dmrsAdditonalPos = obj.PDSCHDMRSAdditionalPosTypeA;
                    else
                        dmrsAdditonalPos = obj.PDSCHDMRSAdditionalPosTypeB;
                    end
                    pdsch.DMRS.DMRSLength = resourceAssignment.DMRSLength;
                    pdsch.DMRS.DMRSAdditionalPosition = dmrsAdditonalPos;
                    if obj.ResourceAllocationType % RAT-1
                        pdsch.PRBSet = resourceAssignment.FrequencyAllocation(1):resourceAssignment.FrequencyAllocation(1) + ...
                            resourceAssignment.FrequencyAllocation(2) - 1;
                    else % RAT-0
                        pdsch.PRBSet = convertRBGBitmapToRBs(obj, resourceAssignment.FrequencyAllocation);
                    end
                    pdsch.Modulation = modScheme(1);
                    [~, pdschIndicesInfo] = nrPDSCHIndices(dlCarrierConfig, pdsch);
                    nLayers = resourceAssignment.NumLayers;
                    achievedTxBits = nrTBS(modScheme(1), nLayers, length(pdsch.PRBSet), ...
                        pdschIndicesInfo.NREPerPRB, codeRate, obj.XOverheadPDSCH);
                    obj.BufferStatusDLPerUE(rnti) = max(0, obj.BufferStatusDLPerUE(rnti) - floor(achievedTxBits/8));
                end
            end
        end

        function updateUserPairingMatrix(obj)
            %updateUserPairingMatrix Updates orthogonality matrix for all UEs based on
            %the DL CSI Type II feedback
            % Check if all UEs has reported Type II feedback atleast once
            if ~isreal(obj.CSIMeasurementDL(end).W)
                W = [obj.CSIMeasurementDL.W];
                pOrth = abs(W'*W);
                pOrth = pOrth/max(pOrth,[],'all');
                obj.UserPairingMatrix = pOrth <= 1-obj.MUMIMOConfigDL.SemiOrthogonalityFactor;
                usersRank = [obj.CSIMeasurementDL.RankIndicator];
                usersRNTI = obj.UEs;
                rankIndices = zeros(1, sum(usersRank));
                count = 1;
                for i = 1:numel(usersRank)
                    rankIndices(count:count+usersRank(i)-1) = usersRNTI(i);
                    count = count+usersRank(i);
                end
                obj.UserPairingMatrix = [rankIndices' obj.UserPairingMatrix.*repmat(rankIndices,length(rankIndices),1)];
            end
        end

        function mumimoUEs = extractMUMIMOUserlist(obj,schedulerInput)
            %extractMUMIMOUserlist Returns users whose buffer is non-zero and
            %filtered for MU-MIMO requirements such as MinRB and MinCQI.
            %
            %   MUMIMOUES = EXTRACTMUMIMOUSERLIST(OBJ,SCHEDULERINPUT)
            %   return a logical array indicating MU-MIMO capable UEs
            %
            %   SCHEDULERINPUT structure contains the fields which scheduler
            %   needs for selecting the UE for resource allocation.
            %
            %   MUMIMOUES is a logical array and determines if the UE is
            %   eligible for MU-MIMO pairing, where a logical 'true' represents
            %   UE is MU-MIMO capable. Currently only MinNumRBs and MinCQI requirements
            %   are considered for filtering.

            mumimoUEs = zeros(1,length(schedulerInput.eligibleUEs));
            cqi = schedulerInput.cqiRBG(:, 1)';
            mcs = schedulerInput.mcsRBG(:, 1)';
            nPRB = obj.MUMIMOConfigDL.MinNumRBs;
            nREPerPRB = 12*schedulerInput.numSym;

            % Find MU-MIMO capable UEs
            for index = 1:length(schedulerInput.eligibleUEs)
                % Calculate served bits for number of RBs equal to MinNumRBs
                nlayers = schedulerInput.selectedRank(index);
                mcsInfo = obj.MCSTableDL(mcs(index)+1, :);
                modSchemeBits = mcsInfo(1); % Bits per symbol for modulation scheme
                modScheme = modSchemeStr(obj, modSchemeBits);
                codeRate = mcsInfo(2)/1024;
                servedBits = nrTBS(modScheme,nlayers,nPRB,nREPerPRB,codeRate);

                % Apply MCS and CQI requirement for MU-MIMO candidacy
                if(schedulerInput.bufferStatus(index) > servedBits)
                    %Apply filtering rule
                    if (cqi(index) >= obj.MUMIMOConfigDL.MinCQI)
                        % logical Array
                        mumimoUEs(index) = 1;
                    end
                end
            end
        end

        function [allottedUEs, allottedRBs, pairedStatus] = userPairingRAT1(obj, schedulerInput, allottedRBCount, availableRBs, activeUEs)
            %userPairingRAT1 Implements user pairing algorthm for resource
            %allocation type 1
            %
            %   [ALLOTTEDUES, ALLOTTEDRBS, PAIREDSTATUS] =
            %   USERPAIRINGRAT1(OBJ, SCHEDULERINPUT, ALLOTTEDRBCOUNT,
            %   AVAILABLERBS, ACTIVEUES) returns allocated UEs, RBs and
            %   pairing status to the base scheduler
            %
            %   SCHEDULERINPUT structure contains the fields which scheduler
            %   needs for selecting the UE for resource allocation.
            %
            %   ALLOTTEDRBCOUNT is an array which list number of RBs
            %   allocated by SU-MIMO scheduling of the UEs.
            %
            %   AVAILABLERBS is total number of RBs available for the
            %   transmission
            %
            %   ACTIVEUES is an array of UEs RNTI which are scheduled by the
            %   base scheduler.
            %
            %   ALLOCATEDUES is array of UEs RNTI which are scheduled by the
            %   user pairing algorithm
            %
            %   ALLOTTEDRBS is an array which list number of RBs
            %   allocated by the user pairing
            %
            %   PAIREDSTATUS stores which primary UE has been paired.

            activeUEsInfo = activeUEs;
            numActiveUEs = length(activeUEsInfo);
            allottedUEs = zeros(numActiveUEs, 1);
            allottedRBs = zeros(numActiveUEs, 1);
            pairedStatus = zeros(numActiveUEs, 1);
            totalRBsAllocated = 0;
            numAllottedUEs = 1;

            % Get MU-MIMO capable UEs
            mumimoUEs = extractMUMIMOUserlist(obj, schedulerInput);

            % Loop until all active UEs are scheduled as SU-MIMO or MU-MIMO
            % candidates
            while (numAllottedUEs <= numActiveUEs)
                selectedUE = activeUEsInfo(1); % Primary User
                index = find(selectedUE == schedulerInput.eligibleUEs);
                selectedUERank = schedulerInput.selectedRank(index);
                pairedUEs = selectedUE;
                rbUEs = allottedRBCount(activeUEs==selectedUE);

                % If selected UE is MU-MIMO capable UE
                if mumimoUEs(index)
                    mumimoUEs(index) = 0;
                    mumimoUEsIndex = schedulerInput.eligibleUEs(mumimoUEs == 1);
                    mumimoUEsIndex = intersect(mumimoUEsIndex,activeUEsInfo(activeUEsInfo ~= selectedUE));
                    selectedUEMcs = schedulerInput.mcsRBG(index, 1);
                    % check for UEs that can be paired with selected UE
                    [pairedUEs, ~] = selectPairedUEs(obj, schedulerInput, selectedUE, selectedUEMcs, selectedUERank, mumimoUEsIndex);
                    pairedUEs = pairedUEs(pairedUEs ~= 0);
                    [~,indices] = intersect(activeUEs, pairedUEs);
                    % Calculate total RBs associated with this pairing
                    rbPairedUEs = sum(allottedRBCount(indices));
                    % Check the UE which has the maximum RB requirement of all
                    % paired UE.
                    maxRBs = max(schedulerInput.rbRequirement(pairedUEs));
                    % Determine if MU-MIMO increases the RB allocation otherwise go with SU-MIMO
                    if rbPairedUEs <= maxRBs && rbPairedUEs >= obj.MUMIMOConfigDL.MinNumRBs
                        rbUEs = rbPairedUEs;
                    else
                        % SU-MIMO
                        pairedUEs = selectedUE;
                    end
                end

                totalRBsAllocated = totalRBsAllocated+rbUEs;
                numPairedUEs = length(pairedUEs);
                % For paired users update information on allocated RBs,
                % allocated UEs and paired status.
                for idx = 1:numPairedUEs
                    % update status if we have paired UEs
                    if numPairedUEs > idx
                        pairedStatus(numAllottedUEs) = 1;
                    end
                    allottedRBs(numAllottedUEs) = min(schedulerInput.rbRequirement(pairedUEs(idx)),rbUEs);
                    allottedUEs(numAllottedUEs) = pairedUEs(idx);
                    activeUEsInfo = activeUEsInfo(activeUEsInfo ~= pairedUEs(idx));
                    mumimoUEs(pairedUEs(idx)) = 0;
                    numAllottedUEs = numAllottedUEs+1;
                end
                if (availableRBs <= totalRBsAllocated)
                    return;
                end
            end
        end

        function [pairedUEs, pairedUEsMcs] = selectPairedUEs(obj, schedulerInput, selectedUE, selectedUEMcs, selectedUERank, mumimoUEs)
            %selectPairedUEs Selects users who can be paired with the
            %primary user.
            %   [PAIREDUES, PAIREDUESMCS] = SELECTPAIREDUES(OBJ,
            %   SCHEDULERINPUT, SELECTEDUE, SELECTEDUEMCS, SELECTEDUERANK,
            %   MUMIMOUES) returns list of users and corresponding MCS
            %   values.
            %
            %   SCHEDULERINPUT structure contains the fields which scheduler
            %   needs for selecting the UE for resource allocation.
            %
            %   SELECTEDUE is primary UE for which the method selects
            %   corresponding paired UEs
            %
            %   SELECTEDUEMCS is the primary UEs rank i.e. the number of transmission
            %   layers
            %
            %   SELECTEDUERANK is the primary UEs rank i.e. the number of transmission
            %   layers
            %
            %   MUMIMOUES is the list of UEs which are elible for MU-MIMO
            %   pairing
            %
            %   PAIREDUES is the list of UEs that are orthogonal. It also
            %   contains the primary UE.
            %
            %   PAIREDUESMCS is the list of UEs MCS that are orthogonal. It
            %   also contains primary UEs MCS.

            % User configurable MaxNumUsersPaired is used to limit the number
            % of paired UEs.
            maxNumUsersPaired = obj.MUMIMOConfigDL.MaxNumUsersPaired;

            pairedUEs = zeros(1,maxNumUsersPaired);
            pairedUEsMcs = zeros(1,maxNumUsersPaired);

            % Assign primary user ID and MCS to the paired UE information
            pairedUEsMcs(1) = selectedUEMcs;
            pairedUEs(1) = selectedUE;

            % Seperate orthogonal matrix and the first column which contains UE indices
            userPairingMatrixIndices = obj.UserPairingMatrix(:,1);
            userPairingMatrix = obj.UserPairingMatrix(:,2:end);

            if ~isempty(userPairingMatrix)
                ueIndices = selectedUE == userPairingMatrixIndices;
                % Get corresponding orthogonality information for the
                % selected UE indices.
                pairingInfo = unique(userPairingMatrix(ueIndices,:));
                pairingInfo =  pairingInfo(pairingInfo ~= 0);
                % Filter UEs based on the RB and CQI restrictions i.e. MU-MIMO UEs
                eligiblePairedUEs =  intersect(pairingInfo, mumimoUEs);
                counter = 1;
                % Recursive search for paired UEs
                for ueIdx = 1:numel(eligiblePairedUEs)
                    ueIndex = eligiblePairedUEs(ueIdx) == userPairingMatrixIndices;
                    pairingSuccess = 1;
                    % Recursive search for orthogonality with all UE already paired
                    for idx = 1:nnz(pairedUEs)
                        orthogonalRows = userPairingMatrix(ueIndex,:) == pairedUEs(idx);
                        rowSize = size(orthogonalRows,1);
                        numLayersOrthogonal = nnz(orthogonalRows)/rowSize;
                        orthogonalBeams = all(obj.CSIMeasurementDL(pairedUEs(idx)).PMISet.i1(1:2) == obj.CSIMeasurementDL(eligiblePairedUEs(ueIdx)).PMISet.i1(1:2));
                        if (numLayersOrthogonal ~= selectedUERank) || (orthogonalBeams == 0)
                            pairingSuccess = 0;
                        end
                    end
                    % Pairing is successful
                    if pairingSuccess == 1
                        counter = counter+1;
                        pairedUEs(counter) = eligiblePairedUEs(ueIdx);
                        index = find(schedulerInput.eligibleUEs == pairedUEs(counter), 1);
                        pairedUEsMcs(counter) = schedulerInput.mcsRBG(index, 1);
                    end
                    if nnz(pairedUEs) == maxNumUsersPaired
                        return;
                    end
                end
            end
        end
    end
end
