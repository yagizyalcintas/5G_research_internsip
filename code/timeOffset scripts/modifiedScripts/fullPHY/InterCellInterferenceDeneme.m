rng("default") % Reset the random number generator
numFrameSimulation = 10; % Simulation time in terms of number of 10 ms frames
networkSimulator = wirelessNetworkSimulator.init; %% CHECK HERE

gNBPositions = [1700 600 0; 2300 600 0;]; %%2500 2000 0
gNBOfInterestIdx = 1; % Specify a value between 1 and number of gNBs

gNBs = nrGNB(Position=gNBPositions,CarrierFrequency=2.5e9,DuplexMode="TDD",ChannelBandwidth=10e6,SubcarrierSpacing=30e3,TransmitPower=32,ReceiveGain=11);

for gNBIdx = 1:length(gNBs)
    % Resource allocation type value 0 indicate noncontiguous allocation of
    % frequency-domain resources in terms of RBGs
    configureScheduler(gNBs(gNBIdx),ResourceAllocationType=0)
end

numCells = length(gNBs);
cellRadius = 500; % Radius of each cell (in meters)
numUEsPerCell = 1;
uePositions = generateUEPositions(cellRadius,gNBPositions,numUEsPerCell);
disp(uePositions);

UEs = cell(numCells,1);
for cellIdx = 1:numCells
    ueNames = "UE-" + (1:size(uePositions{cellIdx},1));
    UEs{cellIdx} = nrUE(Name=ueNames,Position=uePositions{cellIdx},ReceiveGain=11);
    connectUE(gNBs(cellIdx),UEs{cellIdx},FullBufferTraffic="DL")
end

addNodes(networkSimulator,gNBs);
for cellIdx = 1:numCells
    addNodes(networkSimulator,UEs{cellIdx})
end

cellOfInterest = gNBs(gNBOfInterestIdx).ID;
%%disp(cellOfInterest);
%%disp(gNBOfInterestIdx);

enableTraces = true;

linkDir = 0; % Indicates DL
if enableTraces
    simSchedulingLogger = cell(numCells,1);
    simPhyLogger = cell(numCells,1);

    for cellIdx = 1:numCells
        % Create an object for MAC DL scheduling traces logging
        simSchedulingLogger{cellIdx} = helperNRSchedulingLogger(numFrameSimulation,gNBs(cellOfInterest),UEs{cellOfInterest},linkDir);

         % Create an object for PHY layer traces logging
        simPhyLogger{cellIdx} = helperNRPhyLogger(numFrameSimulation,gNBs(cellOfInterest),UEs{cellOfInterest});
    end
end

numMetricsSteps = numFrameSimulation;

metricsVisualizer = helperNRMetricsVisualizer(gNBs(cellOfInterest),UEs{cellOfInterest},CellOfInterest=cellOfInterest,NumMetricsSteps=numMetricsSteps,PlotSchedulerMetrics=true,PlotPhyMetrics=true,LinkDirection=linkDir);

simulationLogFile = "simulationLogs"; % For logging the simulation traces

plotNetwork(cellOfInterest,cellRadius,gNBs,UEs); 

% Calculate the simulation duration (in seconds)
simulationTime = numFrameSimulation*1e-2;
% Run the simulation
run(networkSimulator,simulationTime);

gNBStats = statistics(gNBs);
ueStats = cell(numCells, 1);
for cellIdx = 1:numCells
    ueStats{cellIdx} = statistics(UEs{cellIdx});
end

displayPerformanceIndicators(metricsVisualizer)



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
UExPos = [-500, -300, -100, 100, 250, 300, 500 ];
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
        x = 2000;
    else
        x = round(gnbXCo + r.*cos(theta));
    end
    
    %%disp(sqrt(round(gnbXCo - 50 + r.*cos(theta))^2 + round(gnbYCo + 200+ r.*sin(theta))^2))
    %%disp(sqrt(round( r.*sin(theta)+gnbXCo)^2 + round( r.*sin(theta) + gnbXCo)^2 ) )
    if sqrt(round(gnbXCo - 50 + r.*cos(theta))^2 + round(gnbYCo + 200+ r.*sin(theta))^2) >= sqrt(round( r.*sin(theta)+gnbXCo)^2 + round( r.*sin(theta) + gnbXCo)^2 ) 
      y = round(gnbYCo + 400 + r.*sin(theta));
    else
      y = round(gnbYCo + r.*sin(theta));   
    end
    z = ones(numUEsPerCell,1) * gnbZCo;
    uePositions{cellIdx} = [x y z];
    disp(uePositions(cellIdx));
end
end