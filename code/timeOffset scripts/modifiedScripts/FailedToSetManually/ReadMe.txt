The NextInvokeTime of NRGNB1 got stuck at 0.001 and got into an inf. loop. MACNextInvokeTime was the reason. controlRxStartTime was the bottleneck so I changed its time (on bottom). Then SchedulerNextInvokeTime got stuck, I tride to manually update it as well but did not work.

WirelessNetworkSim.m changes


INSIDE RUN:


if obj.NodeNextInvokeTimes(nodeIdx) - obj.CurrentTime < 1e-8  %%IF WE CHANGE NODENEXTINVOKETIME IN AddNodes() IT SHOULD RUN LATER
                        disp("obj.Nodes{nodeIdx}");
                        disp(obj.Nodes{nodeIdx});
                        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                        disp("obj.nodenextinvoketimes1:");
                        disp(obj.NodeNextInvokeTimes);
                        disp("obj.currenttime1:");
                        disp(obj.CurrentTime);

                        if obj.CurrentTime > 0.0005
                            if nodeIdx == 1
                                if mod(obj.NodeNextInvokeTimes(nodeIdx), 0.0005) == 0
                                    obj.NodeNextInvokeTimes(nodeIdx) = obj.NodeNextInvokeTimes(nodeIdx) + 0.0002;

                                end
                                if  (mod(obj.CurrentTime,0.0005)>= 0.0002) && (mod(obj.CurrentTime,0.001)< 0.0003)
                                     obj.NodeNextInvokeTimes(nodeIdx) = run(obj.Nodes{nodeIdx}, obj.CurrentTime);
                                     recentlyRunNodesFlag(nodeIdx) = true;

                                end
                            else
                                obj.NodeNextInvokeTimes(nodeIdx) = run(obj.Nodes{nodeIdx}, obj.CurrentTime);
                                recentlyRunNodesFlag(nodeIdx) = true;
                            end
                        else
                            obj.NodeNextInvokeTimes(nodeIdx) = run(obj.Nodes{nodeIdx}, obj.CurrentTime);
                            recentlyRunNodesFlag(nodeIdx) = true;
                        end

                        disp("obj.nodenextinvoketimes2:");
                        disp(obj.NodeNextInvokeTimes);
                        disp("obj.currenttime2:");
                        disp(obj.CurrentTime);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

INSIDE DISTPKT():

% For immediate reception, set the next invoke time as current time for receiver nodes
if rxIdx == 1
    if  mod(obj.CurrentTime,0.0005)== 0
    %obj.NodeNextInvokeTimes(rxIdx) = obj.CurrentTime;
    end
else
    obj.NodeNextInvokeTimes(rxIdx) = obj.CurrentTime;
end                  


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


nrGNB.MAC.m

Inside run():


if (currentTime >= 1000000) && (mod(currentTime,500000)==0) && (obj.NCellID == 1)

    obj.SchedulerNextInvokeTime = currentTime + 200000;

else
    obj.SchedulerNextInvokeTime = currentTime + obj.SlotDurationInNS;
end
            
%obj.SchedulerNextInvokeTime = obj.SchedulerNextInvokeTime + obj.SlotDurationInNS; 


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% Avoid running MAC operations more than once in the same symbol
symNumFrame = obj.CurrSlot * obj.NumSymbols + obj.CurrSymbol;
if obj.PreviousSymbol == symNumFrame && elapsedTime < obj.SlotDurationInNS/obj.NumSymbols
	if obj.NCellID == 1
        	obj.SchedulerNextInvokeTime = obj.SchedulerNextInvokeTime + 200000; 
        end
	nextInvokeTime = getNextInvokeTime(obj, currentTime);
	return;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

inside function nextInvokeTime = getNextInvokeTime(obj, currentTime)

controlRxStartTime = min(obj.CSIRSTxInfo(:, 2)); %% made the rx time and tx time same    