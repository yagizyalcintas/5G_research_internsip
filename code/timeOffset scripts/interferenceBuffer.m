classdef interferenceBuffer < comm.internal.ConfigBase & handle
    %interferenceBuffer Create an object to model interference in the PHY receiver
    %
    %   Note: This is an internal undocumented class and its API and/or
    %   functionality may change in subsequent releases.
    %
    %   OBJ = interferenceBuffer creates a default object to model
    %   interference in the PHY receiver.
    %
    %   OBJ = interferenceBuffer(Name=Value) creates an object to model
    %   interference in the PHY receiver, OBJ, with the specified property Name
    %   set to the specified Value. You can specify additional name-value
    %   arguments in any order as (Name1=Value1, ..., NameN=ValueN).
    %
    %   interferenceBuffer methods:
    %
    %   addPacket           - Add packet to the buffer
    %   resultantWaveform   - Return the resultant waveform after combining
    %                         all the packets. This method is applicable
    %                         only for full PHY
    %   packetList          - Return the list of packets overlapping
    %                         in time domain and frequency domain (based on
    %                         InterferenceFidelity value)
    %   receivedPacketPower - Total power of the packets on the channel
    %   bufferChangeTime    - Return the time at which there is a change
    %                         in the state of the buffer
    %   retrievePacket      - Return the packet stored in the specified buffer index
    %   removePacket        - Remove the packet stored in the specified buffer index
    %
    %   interferenceBuffer properties (configurable):
    %
    %   CenterFrequency      - Receiver center frequency in Hz
    %   Bandwidth            - Receiver bandwidth in Hz
    %   SampleRate           - Receiver sampling rate, in samples per second
    %   InterferenceFidelity - Fidelity level of modeling the interference
    %
    % Limitation: For abstracted PHY, the power calculation method
    % 'receivedPacketPower' assumes that all the packets in the buffer have
    % same center frequency and bandwidth.

    %   Copyright 2021-2022 The MathWorks, Inc.

    properties(GetAccess = public, SetAccess = private)
        %CenterFrequency Center frequency of the receiver
        %   Specify the center frequency as a nonnegative scalar. The
        %   default is 5.18e9 Hz.
        CenterFrequency (1,1) {mustBeNumeric, mustBeReal, mustBeNonnegative, mustBeFinite} = 5.18e9

        %Bandwidth Bandwidth of the receiver
        %   Specify the bandwidth as a positive scalar. The default
        %   is 20e6 Hz.
        Bandwidth (1,1) {mustBeNumeric, mustBeReal, mustBePositive, mustBeFinite} = 20e6

        %SampleRate Sampling rate
        %   Specify the sample rate of the receiver, in samples per second.
        %   It is a positive scalar integer. The default value is 40e6 Hz.
        %   If the SampleRate is too low during signal combining,
        %   suitable sample rate is calculated automatically to avoid
        %   signal folding.
        SampleRate (1,1) {mustBeNumeric, mustBeInteger, mustBePositive, mustBeFinite} = 40e6

        %InterferenceFidelity Fidelity level to model the interference
        %    To control the fidelity of modeling the interference. It
        %    takes the value of either 0 or 1.
        %    InterferenceFidelity = 0, indicates that the packets overlapping in
        %    both time and frequency are considered as interference.
        %    InterferenceFidelity = 1, indicates that the packets
        %    overlapping in time are considered as interference,
        %    irrespective of frequency. The default value is 0.
        InterferenceFidelity (1, 1) {mustBeInteger, mustBeInRange(InterferenceFidelity, 0, 1)} = 0
    end

    properties (Access = private)
        %BufferSize Maximum number of packets that can be stored in the packet
        % buffer. The default value is 20.
        BufferSize = 20

        %PacketBuffer Array containing the details of all the packets being received
        PacketBuffer

        %IsActive Array of flags that maps to elements in 'PacketBuffer' and represent
        % whether packet entries in 'PacketBuffer' are active or inactive (expired)
        IsActive = []

        %PacketEndTimes Array indicating the end time of each packet
        % in the PacketBuffer
        PacketEndTimes = []

        %ACPRObject Adjacent channel power ratio (ACPR) calculation object
        ACPRObject

        %MinTimeOverlap A packet must overlap atleast this value to consider it as interference
        % Specify this property as a positive scalar. The default value is 1e-9 seconds.
        MinTimeOverlap {mustBeNumeric, mustBeReal, mustBePositive, mustBeFinite} = 1e-9

        %MinTimeOverlapThreshold A packet must overlap morethan this value
        %to consider it as interference. This value depends on the
        %MinTimeOverlap property
        MinTimeOverlapThreshold
    end

    properties(Hidden)
        %DisableValidation Disable the validation for input arguments of each method
        %   Specify this property as a scalar logical. When true,
        %   validation is not performed on the input arguments.
        DisableValidation (1, 1) logical = false

        %BufferCleanupTime Minimum time a packet has to be buffered after its EndTime
        %   Specify this property as a non negative scalar. The default value
        %   is 0 seconds.
        BufferCleanupTime {mustBeNonempty, mustBeGreaterThanOrEqual(BufferCleanupTime, 0)} = 0
    end

    methods
        function obj =  interferenceBuffer(varargin)
            %interferenceBuffer Construct an object of this class

            % Name-value pair check
            coder.internal.errorIf(mod(nargin, 2) == 1, ...
                'MATLAB:system:invalidPVPairs');

            % Set name-value pairs
            for idx = 1:2:nargin
                obj.(varargin{idx}) = varargin{idx+1};
            end

            % Allocate buffer
            obj.PacketBuffer = repmat(wirelessnetwork.internal.wirelessPacket, obj.BufferSize, 1);

            % Set the minimum overlap threshold value
            obj.MinTimeOverlapThreshold = obj.MinTimeOverlap - eps;

            % Initialize the properties
            obj.IsActive = false(obj.BufferSize, 1);
            obj.PacketEndTimes = -1 * ones(obj.BufferSize, 1);

            obj.ACPRObject = comm.ACPR('MainChannelPowerOutputPort', true,...
                'AdjacentChannelPowerOutputPort', false, 'SampleRate', obj.SampleRate);
        end

        function bufferIdx = addPacket(obj, packet)
            %addPacket Add packet to the buffer and return the buffer element index
            %
            %   BUFFERIDX = addPacket(OBJ, PACKET) adds a packet to the
            %   buffer. It assumes that all the packets added to the buffer
            %   are from same PHY abstraction type.
            %
            %   BUFFERIDX - Index of the buffer element in which packet is stored
            %
            %   OBJ is an instance of class interferenceBuffer.
            %
            %   PACKET is a structure created using
            %   <a href="matlab:help('wirelessnetwork.internal.wirelessPacket')">wirelessPacket</a>.

            if ~obj.DisableValidation

                % Validate start time
                validateattributes(packet.StartTime, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', 'finite'}, mfilename, 'StartTime');

                % Validate duration
                validateattributes(packet.Duration, {'numeric'}, ...
                    {'scalar', 'real', 'positive', 'finite'}, mfilename, 'Duration');

                % Validate center frequency
                validateattributes(packet.CenterFrequency, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', 'finite'}, mfilename, 'CenterFrequency');

                % Validate bandwidth
                validateattributes(packet.Bandwidth, {'numeric'}, ...
                    {'scalar', 'real', 'positive', 'finite'}, mfilename, 'Bandwidth');

                % Validate abstraction type
                validateattributes(packet.Abstraction, {'logical', 'numeric'}, ...
                    {'scalar'}, mfilename, 'Abstraction');

                if packet.Abstraction % Abstracted PHY
                    % Validate power
                    validateattributes(packet.Power, {'numeric'}, ...
                        {'scalar', 'real', 'finite'}, mfilename, 'Power');
                else % Full PHY
                    % Validate sample rate
                    validateattributes(packet.SampleRate, {'numeric'}, ...
                        {'scalar', 'integer', 'positive', 'finite'}, mfilename, 'SampleRate');
                    % Validate data
                    validateattributes(packet.Data, {'double', 'single'}, {'nonempty'}, mfilename, 'Data');
                end
            end

            % Store the received packet
            bufferIdx = find(~obj.IsActive, 1); % Find an inactive buffer index
            if isempty(bufferIdx)
                bufferIdx = autoResizePacketBuffer(obj, packet.StartTime);
            end
            obj.IsActive(bufferIdx) = true;
            obj.PacketEndTimes(bufferIdx) = packet.StartTime + packet.Duration; % End time of the packet
            obj.PacketBuffer(bufferIdx) = packet;
        end

        function [rxWaveform, numPackets, sampleRate] = resultantWaveform(obj, startTime, endTime, varargin)
            %resultantWaveform Return the resultant waveform for the reception duration
            %
            %   [RXWAVEFORM, NUMPACKETS] = resultantWaveform(OBJ,
            %   STARTTIME, ENDTIME) returns the resultant waveform for the
            %   given start and end times.
            %
            %   RXWAVEFORM Resultant of all the waveforms. It is a T-by-R
            %   matrix of complex values. Here T represents number of
            %   time-domain samples and N represents the number of receive
            %   antennas.
            %
            %   NUMPACKETS Number of overlapping packets in time domain and
            %   frequency domain (based on InterferenceFidelity value).
            %
            %   SAMPLERATE Sample rate of the resultant waveform.
            %
            %   STARTTIME is the start time of reception in seconds.
            %   It is a nonnegative scalar.
            %
            %   ENDTIME is the end time of reception in seconds. It
            %   is a positive scalar. It must be greater than STARTTIME.
            %
            %   [RXWAVEFORM, NUMPACKETS] = resultantWaveform(OBJ,
            %   STARTTIME, ENDTIME, Name=Value) specifies additional
            %   name-value arguments described below. When a name-value
            %   argument is not specified, the object function uses the
            %   default value of the object.
            %
            %   'CenterFrequency' is the center frequency of the receiver
            %    in Hz. It is a nonnegative scalar.
            %
            %   'Bandwidth' is the bandwidth of the receiver in Hz. It is a
            %   positive scalar.

            % Check whether the validation is enabled
            if ~obj.DisableValidation
                narginchk(3, 7);

                % Name-value pair check
                coder.internal.errorIf(mod(numel(varargin), 2) == 1, ...
                    'MATLAB:system:invalidPVPairs');

                % Validate start time
                validateattributes(startTime, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', 'finite'}, mfilename, 'startTime');

                % Validate end time
                validateattributes(endTime, {'numeric'}, ...
                    {'scalar', 'real', 'positive', '>', startTime, 'finite'}, mfilename, 'endTime');
            end

            [centerFrequency, bandwidth] = validateInputs(obj, varargin);

            % Get indices of the overlapping packets
            [packetIndices, numPackets] = getOverlappingPackets(obj, startTime, endTime, centerFrequency, bandwidth);
            % Return the combined waveform
            rxWaveform = [];
            sampleRate = [];
            if numPackets > 0
                sampleRate = calculateSampleRate(obj, centerFrequency, packetIndices, obj.SampleRate);
                rxWaveform = combineWaveforms(obj, startTime, endTime, centerFrequency, packetIndices, sampleRate);
            end
        end

        function packets = packetList(obj, startTime, endTime, varargin)
            %packetList Return the list of packets which are overlapping in time/frequency
            %
            %   PACKETS = packetList(OBJ, STARTTIME, ENDTIME)
            %   returns a structure array containing packets within the
            %   buffer. If InterferenceFidelity = 0, it returns the packets
            %   overlapping in both time and frequency. If
            %   InterferenceFidelity = 1, it returns the packets
            %   overlapping in time, irrespective of frequency. If there is
            %   no matching packet, it returns empty <a href="matlab:help('wirelessnetwork.internal.wirelessPacket')">wirelessPacket</a>.
            %
            %   STARTTIME is the start time of reception in seconds.
            %   It is a nonnegative scalar.
            %
            %   ENDTIME is the end time of reception in seconds. It is a
            %   nonnegative scalar. It must be greater than or equal to STARTTIME.
            %
            %   PACKETS = packetList(OBJ, STARTTIME, ENDTIME, Name=Value) specifies
            %   additional name-value arguments described below. When a
            %   name-value argument is not specified, the object function
            %   uses the default value of the object.
            %
            %   'CenterFrequency' is the center frequency of the receiver
            %    in Hz. It is a nonnegative numeric scalar.
            %
            %   'Bandwidth' is the bandwidth of the receiver in Hz. It is a
            %   positive numeric scalar.

            % Check whether the validation is enabled
            if ~obj.DisableValidation
                narginchk(3, 7);

                % Name-value pair check
                coder.internal.errorIf(mod(numel(varargin), 2) == 1, ...
                    'MATLAB:system:invalidPVPairs');

                % Validate start time
                validateattributes(startTime, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', 'finite'}, mfilename, 'startTime');

                % Validate end time
                validateattributes(endTime, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', '>=', startTime, 'finite'}, mfilename, 'endTime');
            end

            [centerFrequency, bandwidth] = validateInputs(obj, varargin);
            % To query the packets at a time instant
            if startTime == endTime
                % Set the end time as more than min overlap time
                endTime = endTime+obj.MinTimeOverlap;
            end

            packetIndices = getOverlappingPackets(obj, startTime, endTime, centerFrequency, bandwidth);
            packets = obj.PacketBuffer(packetIndices);
        end

        function currentPower = receivedPacketPower(obj, currentTime, varargin)
            %receivedPacketPower Return the current power in the channel
            %
            %   CURRENTPOWER = receivedPacketPower(OBJ, CURRENTTIME)
            %   returns the total power of the packets on the channel.
            %
            %   CURRENTPOWER - Total power of the packets on the channel in
            %   dBm. If there is no power in the channel it returns -Inf.
            %
            %   CURRENTTIME is the current time at the receiver in
            %   seconds. It is a nonnegative scalar.
            %
            %   CURRENTPOWER = receivedPacketPower(OBJ, CURRENTTIME,
            %   Name=Value) specifies additional name-value arguments
            %   described below. When a name-value argument is not
            %   specified, the object function uses the default value of
            %   the object.
            %
            %   'CenterFrequency' is the center frequency of the receiver
            %    in Hz. It is a nonnegative scalar.
            %
            %   'Bandwidth' is the bandwidth of the receiver in Hz. It is a
            %    positive scalar.

            % Check whether the validation is enabled
            if ~obj.DisableValidation
                narginchk(2, 6);

                % Name-value pair check
                coder.internal.errorIf(mod(numel(varargin), 2) == 1, ...
                    'MATLAB:system:invalidPVPairs');

                % Validate start time
                validateattributes(currentTime, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', 'finite'}, mfilename, 'currentTime');
            end

            [centerFrequency, bandwidth] = validateInputs(obj, varargin);

            activeSignalIdx = obj.IsActive & ((obj.PacketEndTimes - currentTime) > obj.MinTimeOverlapThreshold);
            currentPower = -Inf;
            minEndTime = min(obj.PacketEndTimes(activeSignalIdx));

            [activePacketIdxs, numPackets, acprRequiredFlag] = getOverlappingPackets(obj, currentTime, minEndTime, centerFrequency, bandwidth);
            if numPackets == 0
                return;
            end
            % Determine the packet type
            phyAbstractionType = obj.PacketBuffer(activePacketIdxs(1)).Abstraction;

            if phyAbstractionType % Abstracted PHY
                signalList = obj.PacketBuffer(activePacketIdxs);
                signalPowset = [signalList.Power];
                currentPower = sum(10.0 .^ (signalPowset/ 10.0)); % Power in milliwatts
            else % Full PHY
                % Passing bandwidth as minimum required sample rate when
                % calculating the desired samplerate
                sampleRate = calculateSampleRate(obj, centerFrequency, activeSignalIdx, bandwidth);

                % Overlap duration is not more than 1 sample duration or no partial frequency overlap
                % Using the eps threshold to work consistently during
                % floating point comparisons
                if ((minEndTime-currentTime) - (1/sampleRate)) < eps || ~acprRequiredFlag
                    signalList = obj.PacketBuffer(activePacketIdxs);
                    signalPowset = [signalList.Power];
                    currentPower = sum(10.0 .^ (signalPowset/ 10.0)); % Power in milliwatts
                else
                    % Calculate the power when there is partial frequency overlap
                    rxWaveform = combineWaveforms(obj, currentTime, minEndTime, centerFrequency, activePacketIdxs, sampleRate);
                    if size(rxWaveform, 1) <= 1 % ACPR accepts column vector as input
                        signalList = obj.PacketBuffer(activePacketIdxs);
                        signalPowset = [signalList.Power];
                        currentPower = sum(10.0 .^ (signalPowset/ 10.0)); % Power in milliwatts
                    else
                        release(obj.ACPRObject);
                        currentPower = 0;
                        if obj.ACPRObject.MainMeasurementBandwidth ~= bandwidth
                            obj.ACPRObject.MainMeasurementBandwidth = bandwidth;
                        end
                        if obj.ACPRObject.SampleRate ~= sampleRate
                            obj.ACPRObject.SampleRate = sampleRate;
                        end
                        numRxAnts = size(rxWaveform, 2);
                        for idx=1:numRxAnts
                            [~, totalPowerdBm] = obj.ACPRObject(rxWaveform(:, idx));
                            % Sum of powers at each antenna
                            currentPower = currentPower + (10.0 ^ (totalPowerdBm/ 10.0)); % Power in milliwatts
                        end
                    end
                end
            end
            currentPower = 10 * log10(currentPower); % Power in dBm
        end
    
        function t = bufferChangeTime(obj, currentTime)
            %bufferChangeTime Returns the time after which the state of the buffer is expected to change
            %
            %   T = bufferChangeTime(OBJ, CURRENTTIME) returns the time
            %   after which the state of the buffer is expected to change
            %
            %   T - Returns the time duration in seconds after which the
            %   state of the buffer is expected to change. If there is no
            %   change in the state of the buffer it returns Inf.
            %
            %   CURRENTTIME is the current time at the receiver in
            %   seconds. It is a nonnegative scalar.

            % Check whether the validation is enabled
            if ~obj.DisableValidation
                narginchk(2, 2);
                % Validate current time
                validateattributes(currentTime, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', 'finite'}, mfilename, 'currentTime');
            end

            activeSignalIdx = obj.IsActive & ((obj.PacketEndTimes - currentTime) > obj.MinTimeOverlapThreshold);
            t =  min(obj.PacketEndTimes(activeSignalIdx)) - currentTime;
            if isempty(t)
                t = inf;
            end
        end
    
        function packets = retrievePacket(obj, bufferIdx)
            %retrievePacket Return the packet stored in the specified buffer index
            %
            %   PACKET = retrievePacket(OBJ, BUFFERIDX) returns the packets
            %   stored in the specified buffer element indices, BUFFERIDX.
            %   If there is no stored packet, it returns empty
            %   <a href="matlab:help('wirelessnetwork.internal.wirelessPacket')">wirelessPacket</a> type
            %
            %   BUFFERIDX - Indices of the buffer elements at which the
            %   packets are stored. It is a positive integer vector.
            %
            %   OBJ is an instance of class interferenceBuffer.
            %
            %   PACKET is a structure created using
            %   <a href="matlab:help('wirelessnetwork.internal.wirelessPacket')">wirelessPacket</a>.

            % Check whether the validation is enabled
            if ~obj.DisableValidation
                narginchk(2, 2);
                % Validate buffer index
                validateattributes(bufferIdx, {'numeric'}, ...
                    {'vector', 'integer', 'positive', '<=', numel(obj.IsActive)}, mfilename, 'bufferIdx');
            end
            packets = obj.PacketBuffer(bufferIdx(obj.IsActive(bufferIdx)));
        end

        function removePacket(obj, bufferIdx)
            %removePacket Remove the packet stored in the specified buffer index
            %
            %   removePacket(OBJ, BUFFERIDX) removes the packets from the
            %   specified buffer element indices, BUFFERIDX, if it exists.
            %
            %   BUFFERIDX - Indices of the buffer elements at which the
            %   packets are stored. It is a positive integer vector.
            %
            %   OBJ is an instance of class interferenceBuffer.

            % Check whether the validation is enabled
            if ~obj.DisableValidation
                narginchk(2, 2);
                % Validate buffer index
                validateattributes(bufferIdx, {'numeric'}, ...
                    {'vector', 'integer', 'positive', '<=', numel(obj.IsActive)}, mfilename, 'bufferIdx');
            end
            obj.IsActive(bufferIdx) = false;
            obj.PacketEndTimes(bufferIdx) = -1;
        end

    end

    methods(Access = private)
        function rxWaveform = combineWaveforms(obj, startTime, endTime, centerFrequency, packetIndices, sampleRate)
            %combineWaveforms Return the combined waveform

            numPackets = numel(packetIndices);
            % Initialize the waveform
            receivedPackets = obj.PacketBuffer(packetIndices);
            duration = endTime - startTime;
            nRxAnts = size(receivedPackets(1).Data, 2);
            waveformLength = round(duration * sampleRate);
            rxWaveform = complex(zeros(waveformLength, nRxAnts));

            for idx = 1:numPackets
                packet = receivedPackets(idx);

                if ~obj.DisableValidation
                    % Verify all the packets are from full phy (Abstraction = false)
                    coder.internal.assert(~packet.Abstraction, 'wirelessnetwork:interferenceBuffer:MethodNotApplicable')

                    % Verify that the number of columns in packet.Data
                    % field must be same for all the packets
                    coder.internal.assert(nRxAnts == size(packet.Data, 2), 'wirelessnetwork:interferenceBuffer:InvalidWaveformSize')
                end

                % Calculate the number of overlapping samples
                overlapStartTime = max(startTime, packet.StartTime);
                overlapEndTime = min(endTime, packet.StartTime + packet.Duration);
                % Using ceil/floor results one extra/less sample. So, using
                % the round helps to consider an extra sample only if it
                % overlaps with signal of interest for more than half of the
                % sample period.
                numSOIOverlapSamples = round((overlapEndTime - overlapStartTime) * sampleRate);
                numInterfererOverlapSamples = round((overlapEndTime - overlapStartTime) * packet.SampleRate);
                if numInterfererOverlapSamples == 0 || numSOIOverlapSamples == 0
                    continue;
                end
                
                % Calculate the overlapping start and end index of
                % the resultant waveform time-domain samples
                soiStartIdx = round((overlapStartTime - startTime) * sampleRate) + 1;
                soiEndIdx = soiStartIdx + numSOIOverlapSamples - 1;
                % Overlapping end index should not exceed the resultant waveform length
                if soiEndIdx > waveformLength
                    numSOIOverlapSamples = numSOIOverlapSamples - (soiEndIdx - waveformLength);
                    soiEndIdx = waveformLength;
                end

                % Calculate the overlapping start and end index of
                % the interferer waveform time-domain samples
                iStartIdx = round((overlapStartTime - packet.StartTime) * packet.SampleRate) + 1;
                iEndIdx = iStartIdx + numInterfererOverlapSamples - 1;
                interfererWaveform = zeros(numSOIOverlapSamples, nRxAnts);

                waveform = packet.Data;
                numPadding = 0;
                packetWaveformLength = size(waveform, 1);
                % Overlapping end index should not exceed the interfering waveform length
                if iEndIdx > packetWaveformLength
                    numPadding = iEndIdx - packetWaveformLength;
                    iEndIdx = packetWaveformLength;
                end
                if numSOIOverlapSamples ~= numInterfererOverlapSamples
                    [L, M] = rat(sampleRate/packet.SampleRate);
                    resampledWaveform = resample(waveform(iStartIdx:iEndIdx, :), L, M);
                    % When number of rows in the input is 1, resample function returns row vector .
                    if numInterfererOverlapSamples == 1
                        numRows = min(size(resampledWaveform, 2)/nRxAnts, numSOIOverlapSamples);
                        resampledWaveform = reshape(resampledWaveform, [numRows nRxAnts]);
                    end
                    if size(resampledWaveform, 1) < numSOIOverlapSamples
                        numSOIOverlapSamples = size(resampledWaveform, 1);
                    end
                    interfererWaveform(1:numSOIOverlapSamples, :) = resampledWaveform(1:numSOIOverlapSamples, :);
                else
                    interfererWaveform = [waveform(iStartIdx:iEndIdx,:); zeros(numPadding, nRxAnts)];
                end

                % Shift the interfering waveform in frequency if the
                % center frequency does not match with required center
                % frequency
                frequencyOffset = (-centerFrequency + packet.CenterFrequency);
                if frequencyOffset ~= 0
                    t = ((0:size(interfererWaveform,1)-1) / sampleRate)';
                    interfererWaveform = interfererWaveform .* exp(1i*2*pi*frequencyOffset*t);
                end

                % Combine the time-domain samples
                rxWaveform(soiStartIdx:soiEndIdx, 1:nRxAnts) = ...
                    rxWaveform(soiStartIdx:soiEndIdx, 1:nRxAnts) + ...
                    interfererWaveform(:,1:nRxAnts);
            end
        end

        function [packetIdxList, numPackets, acprRequiredFlag] = getOverlappingPackets(obj, startTime, endTime, centerFrequency, bandwidth)
            %getOverlappingPackets Return indices, the count of overlapping
            %packets, and a flag which indicates all the overlapping
            %packets are of same center frequency and bandwidth or not

            % Find the active packets
            minTimeOverlapThreshold = obj.MinTimeOverlapThreshold;
            packetIndices = find(obj.IsActive & ((obj.PacketEndTimes - startTime) > minTimeOverlapThreshold));
            numActivePackets = numel(packetIndices);
            packetIdxList = zeros(numActivePackets, 1);
            numPackets = 0;
            channelCollisionFlag = false;
            acprRequiredFlag = false;

            % Filter the overlapping packets based on InterferenceFidelity value
            soiStartFrequency = centerFrequency - bandwidth/2;
            soiEndFrequency = centerFrequency + bandwidth/2;
            for idx = 1:numActivePackets

                % Get the packet
                packet = obj.PacketBuffer(packetIndices(idx));

                % Find the active packets between the given time period
                if (min(endTime, packet.StartTime+packet.Duration) - max(startTime, packet.StartTime) > minTimeOverlapThreshold)
                    if obj.InterferenceFidelity == 0 % Overlap in frequency and time
                        % Check the packet overlap in frequency
                        if min(soiEndFrequency, packet.CenterFrequency + packet.Bandwidth/2)- max(soiStartFrequency, packet.CenterFrequency - packet.Bandwidth/2) > 0
                            channelCollisionFlag = true;
                        end
                    end
                   % If there is partial overlap in frequency or if the interference fidelity level is high
                    if channelCollisionFlag || obj.InterferenceFidelity == 1
                        numPackets = numPackets + 1;
                        packetIdxList(numPackets) = packetIndices(idx);
                        channelCollisionFlag = false;
                    end
                    % Check whether all the packets are of different center frequency or
                    % bandwidth
                    if packet.CenterFrequency ~= centerFrequency || packet.Bandwidth ~= bandwidth
                        acprRequiredFlag = true;
                    end
                end
            end
            packetIdxList = packetIdxList(1:numPackets);
        end

        function removeObsoletePackets(obj, endTime)
            %removeObsoletePackets Remove the packets from the buffer which
            %have ended on or before the specified time

            expiredSignalIdx = obj.IsActive & (obj.PacketEndTimes <= endTime);
            if any(expiredSignalIdx)
                obj.IsActive(expiredSignalIdx) = false;
                obj.PacketEndTimes(expiredSignalIdx) = -1;
            end
        end

        function bufferIdx = autoResizePacketBuffer(obj, currentTime)
            %autoResizePacketBuffer Return the next inactive buffer index after resizing the packet buffer

            % Remove the obsolete packets
            maxDuration = max([obj.PacketBuffer.Duration obj.BufferCleanupTime]);
            removeObsoletePackets(obj, currentTime-maxDuration);

             bufferIdx = find(~obj.IsActive, 1);
             if isempty(bufferIdx) % Increase the buffer size
                 prevSize = obj.BufferSize;
                 % Double the buffer size
                 obj.BufferSize = obj.BufferSize * 2;
                 obj.IsActive = [obj.IsActive; false(prevSize, 1)];
                 obj.PacketEndTimes = [obj.PacketEndTimes; zeros(prevSize, 1)-1];
                 obj.PacketBuffer = [obj.PacketBuffer; repmat(wirelessnetwork.internal.wirelessPacket,prevSize,1)];
                 bufferIdx = prevSize + 1;
             end
        end

        function [centerFrequency, bandwidth] = validateInputs(obj, inputParam)
            %validateInputs Parse and validate the inputs

            centerFrequency = obj.CenterFrequency;
            bandwidth = obj.Bandwidth;

            for idx = 1:2:numel(inputParam)
                switch inputParam{idx}
                    case 'CenterFrequency'
                        centerFrequency = inputParam{idx+1};
                    case 'Bandwidth'
                        bandwidth = inputParam{idx+1};
                    otherwise
                        coder.internal.errorIf(true,'wirelessnetwork:interferenceBuffer:UnrecognizedStringChoice', inputParam{idx});
                end
            end

            if ~obj.DisableValidation
                % Validate center frequency
                validateattributes(centerFrequency, {'numeric'}, ...
                    {'scalar', 'real', 'nonnegative', 'finite'}, mfilename, 'CenterFrequency');

                % Validate bandwidth
                validateattributes(bandwidth, {'numeric'}, ...
                    {'scalar', 'real', 'positive', 'finite'}, mfilename, 'Bandwidth');
            end
        end

        function sampleRate = calculateSampleRate(obj, centerFrequency, packetIndices, actSampleRate)
            %calculateSampleRate Return the desired sample rate for combining waveforms

            receivedPackets = obj.PacketBuffer(packetIndices);
            inputSampleRates = [receivedPackets.SampleRate];
            frequencyOffsets = (-centerFrequency + [receivedPackets.CenterFrequency]);
            bandEdge = inputSampleRates./2 + abs(frequencyOffsets); % Edge of each frequency shifted band
            sampleRate = 2 * max(bandEdge); % output sample rate
            % Determine the maximum sample rate
            if sampleRate < actSampleRate
                sampleRate = actSampleRate;
            end
        end
    end
end