wirelessnetworkSupportPackageCheck;

rng("default") % Reset the random number generator
numFrameSimulation = 6; % Simulation time in terms of number of 10 ms frames
networkSimulator = wirelessNetworkSimulator.init;

gNBPositions = [1700 600 0; 2600 600 0]; %%2500 2000 0
gNBOfInterestIdx = 1; % Specify a value between 1 and number of gNBs

% main thing is here
phyAbstractionType = "none";

gNBs = nrGNB(Position=gNBPositions,DuplexMode="TDD",CarrierFrequency=2.5e9,ChannelBandwidth=40e6,SubcarrierSpacing=30e3,PHYAbstractionMethod=phyAbstractionType,TransmitPower=22,ReceiveGain=11);


for gNBIdx = 1:length(gNBs)
    % Resource allocation type value 0 indicate noncontiguous allocation of
    % frequency-domain resources in terms of RBGs
    configureScheduler(gNBs(gNBIdx),ResourceAllocationType=0)
end

numCells = length(gNBs);
cellRadius = 600; % Radius of each cell (in meters)
numUEsPerCell = 4;
uePositions = generateUEPositions(cellRadius,gNBPositions,numUEsPerCell);

UEs = cell(numCells,1);
for cellIdx = 1:numCells
    ueNames = "UE-" + (1:size(uePositions{cellIdx},1));
    UEs{cellIdx} = nrUE(Name=ueNames,Position=uePositions{cellIdx},ReceiveGain=11,TransmitPower=23,PHYAbstractionMethod=phyAbstractionType);
    connectUE(gNBs(cellIdx),UEs{cellIdx},FullBufferTraffic="on")
end

% 
addNodes(networkSimulator,gNBs);
for cellIdx = 1:numCells
    addNodes(networkSimulator,UEs{cellIdx});
end


channelConfig = struct("DelayProfile","CDL-C","DelaySpread",300e-9);


%for cellIdx = 1:numCells
channels = createCDLChannels(channelConfig,gNBs,UEs,numUEsPerCell);
%end


customChannelModel = hNRCustomChannelModel(channels,struct(PHYAbstractionMethod=phyAbstractionType));
addChannelModel(networkSimulator,@customChannelModel.applyChannelModel);

enableTraces = true;

if enableTraces
    % Create an object for scheduler traces logging
    simSchedulingLogger = helperNRSchedulingLogger(numFrameSimulation,gNBs(gNBOfInterestIdx),UEs{gNBOfInterestIdx});
    % Create an object for PHY traces logging
    simPhyLogger = helperNRPhyLogger(numFrameSimulation,gNBs(gNBOfInterestIdx),UEs{gNBOfInterestIdx});
end

numMetricsSteps = 10;

metricsVisualizer = helperNRMetricsVisualizer(gNBs(gNBOfInterestIdx),UEs{gNBOfInterestIdx},NumMetricsSteps=numMetricsSteps,...
    PlotSchedulerMetrics=true,PlotPhyMetrics=true);

simulationLogFile = "simulationLogs"; % For logging the simulation traces

cellOfInterest = gNBs(gNBOfInterestIdx).ID;
plotNetwork(cellOfInterest,cellRadius,gNBs,UEs); 

% Calculate the simulation duration (in seconds)
simulationTime = numFrameSimulation * 1e-2;
% Run the simulation
run(networkSimulator,simulationTime);

%gNBStats = statistics(gNB(gNBOfInterestIdx));
%ueStats = statistics(UEs{gNBOfInterestIdx});

displayPerformanceIndicators(metricsVisualizer);


function plotNetwork(cellOfInterest,cellRadius,gNBs,UEs)
%plotNetwork Create the network figure

figure(Name="Network Topology Visualization",units="normalized", ...
    outerposition=[0 0 1 1],Visible="on");
title("Network Topology Visualization");
hold on

numCells = numel(gNBs);
for cellIdx = 1:numCells

    gNBPosition = gNBs(cellIdx).Position;
    % Plot the circle
    th = 0:pi/60:2*pi;
    xunit = cellRadius * cos(th) + gNBPosition(1);
    yunit = cellRadius * sin(th) + gNBPosition(2);
    if cellOfInterest == cellIdx
        h1 =  plot(xunit,yunit,Color="green"); % Cell of interest
    else
        h2 =  plot(xunit,yunit,Color="red");
    end
    xlabel("X-Position (meters)")
    ylabel("Y-Position (meters)")
    % Add tool tip data for gNBs
    s1 = scatter(gNBPosition(1),gNBPosition(2),"^", ...
        MarkerEdgeColor="magenta");
    cellIdRow = dataTipTextRow("Cell - ",{num2str(cellIdx)});
    s1.DataTipTemplate.DataTipRows(1) = cellIdRow;
    posRow = dataTipTextRow('Position[X, Y]: ',{['[' num2str(gNBPosition) ']']});
    s1.DataTipTemplate.DataTipRows(2) = posRow;
    
    % Add tool tip data for UEs
    uesPerCell = UEs{cellIdx};
    for ueIdx = 1:numel(uesPerCell)
        uePosition = uesPerCell(ueIdx).Position;
        s2 = scatter(uePosition(1),uePosition(2),".",MarkerEdgeColor="blue");
        s2.DataTipTemplate.DataTipRows(1) = uesPerCell(ueIdx).Name;
        posRow = dataTipTextRow('Position[X, Y]: ',{['[' num2str(uePosition) ']']});
        s2.DataTipTemplate.DataTipRows(2) = posRow;
    end
end
% Create the legend
if numCells > 1
    legend([h1 h2 s1 s2],"Cell of interest","Interfering cells","gNodeB", ...
        "UE","Location", "northeastoutside")
else
    legend([h1 s1 s2],"Cell of interest","gNodeB","UE","Location","northeastoutside")
end
axis auto
hold off
daspect([1000,1000,1]); % Set data aspect ratio
end

function uePositions = generateUEPositions(cellRadius,gNBPositions,numUEsPerCell)
%generateUEPositions Return the position of UEs in each cell

numCells = size(gNBPositions,1);
uePositions = cell(numCells,1);
for cellIdx=1:numCells
    gnbXCo = gNBPositions(cellIdx,1); % gNB X-coordinate
    gnbYCo = gNBPositions(cellIdx,2); % gNB Y-coordinate
    gnbZCo = gNBPositions(cellIdx,3); % gNB Z-coordinate
    theta = rand(numUEsPerCell,1)*(2*pi);
    % Expression to calculate position of UEs with in the cell. By default,
    % it will place the UEs randomly with in the cell
    r = sqrt(rand(numUEsPerCell,1))*cellRadius;
    if cellIdx == 1
        %x = round(gnbXCo + UExPos(4) + r.*cos(theta));
        x = [2000;2000;2000;2000];
    else
        x = round(gnbXCo + r.*cos(theta));
    end
    
    %%disp(sqrt(round(gnbXCo - 50 + r.*cos(theta))^2 + round(gnbYCo + 200+ r.*sin(theta))^2))
    %%disp(sqrt(round( r.*sin(theta)+gnbXCo)^2 + round( r.*sin(theta) + gnbXCo)^2 ) )
    if sqrt(round(gnbXCo - 50 + r.*cos(theta)).^2 + round(gnbYCo + 200+ r.*sin(theta)).^2) >= sqrt(round( r.*sin(theta)+gnbXCo).^2 + round( r.*sin(theta) + gnbXCo).^2 ) 
      y = round(gnbYCo + 200 + r.*sin(theta));
    else
      y = round(gnbYCo + r.*sin(theta));   
    end
    z = ones(numUEsPerCell,1) * gnbZCo;
    uePositions{cellIdx} = [x y z];
end
end

function channels = createCDLChannels(channelConfig,gNBs,UEs,numUEsPerCell)
%createCDLChannels Create channels between gNB node and UE nodes in a cell
%   CHANNELS = createCDLChannels(CHANNELCONFIG,GNB,UES) creates channels
%   between GNB and UES in a cell.
%
%   CHANNELS is a N-by-N array where N is the number of nodes in the cell.
%
%   CHANNLECONFIG is a struct with these fields - DelayProfile and
%   DelaySpread.
%
%   GNB is an nrGNB node.
%
%   UES is an array of nrUE nodes.

numUEs = 0;
for i = 1:length(UEs)
    numUEs = numUEs + length(UEs{i});
end

numgNBs = length(gNBs);
numNodes = numgNBs + numUEs;
% Create channel matrix to hold the channel objects
channels = cell(numNodes,numNodes);

% Get the sample rate of waveform
waveformInfo = nrOFDMInfo(gNBs(1).NumResourceBlocks,gNBs(1).SubcarrierSpacing/1e3); %use one of gNB in our code not the array
sampleRate = waveformInfo.SampleRate;
channelFiltering = strcmp(gNBs(1).PHYAbstractionMethod,'none');
for gnbIDx = 1:numgNBs
    for ueIdx = 1:numUEsPerCell
        for Cellx = 1:numgNBs
            % Configure the UL channel model between gNB and UE
            channel = nrCDLChannel;
            channel.DelayProfile = channelConfig.DelayProfile;
            channel.DelaySpread = channelConfig.DelaySpread;
            channel.Seed = 73 + (ueIdx - 1);
            channel.CarrierFrequency = gNBs(gnbIDx).CarrierFrequency;
            disp(gNBs(Cellx));
            ue = UEs{Cellx}(ueIdx);
            disp(ue);
            
            channel = hArrayGeometry(channel,ue.NumTransmitAntennas,gNBs(gnbIDx).NumReceiveAntennas,...
                'uplink');
            channel.SampleRate = sampleRate;
            channel.ChannelFiltering = channelFiltering;
            channels{ue.ID, gNBs(gnbIDx).ID} = channel;
    
            % Configure the DL channel model between gNB and UE
            channel = nrCDLChannel;
            channel.DelayProfile = channelConfig.DelayProfile;
            channel.DelaySpread = channelConfig.DelaySpread;
            channel.Seed = 73 + (ueIdx - 1);
            channel.CarrierFrequency = gNBs(gnbIDx).CarrierFrequency;
            channel = hArrayGeometry(channel,gNBs(gnbIDx).NumTransmitAntennas,ue.NumReceiveAntennas,...
                'downlink');
            channel.SampleRate = sampleRate;
            channel.ChannelFiltering = channelFiltering;
            channels{gNBs(gnbIDx).ID, ue.ID} = channel;
        end
    end
end    
end
