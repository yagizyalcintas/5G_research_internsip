downlink_Uplink_Position = "downlink with"

downlink2 = "0.75-0.13"
downlink5= "0.81-0.42-0.09-0.12-0.07"
downlink12= "0.02-0.16-0.08-0.21-0.05-0.1-0.02-0.3-0.39-0.36-0.02-0.44"
downlink15= "0.22-0.15-0.02-0.06-0.02-0.12-0.21-0.28-0.27-0.33-0.03-0.41-0.38-0.26-0.09"
downlink20= "0.02-0.2-0.02-0.03-0.05-0.04-0.01-0.24-0.18-0.23-0.01-0.24-0.36-0.15-0.19-0.01-0.1-0.19-0.01-0.3"

Uplink2= "0-0.69"
Uplink5="0.51-0.39-0.44-0.12-0.02"
Uplink12="0.05-0.38-0.22-0.26-0.02-0.3-0-0.36-0.12-0.24-0.05-0.45"
Uplink15="0.17-0.26-0.12-0.1-0.05-0.23-0.19-0.35-0.09-0.23-0-0.4-0.42-0.33-0.09"
Uplink20="0.02-0.19-0.14-0.12-0.02-0.05-0-0.33-0-0.18-0-0.23-0.28-0.21-0.05-0.02-0.02-0.1-0.02-0.26"

Pos1800="0.32-0.2-0.05-0.32-0.16-0.35-0.16-0.35-0.3-0.32"
Pos1900="0.19-0.11-0.03-0.17-0.05-0.28-0.02-0.12-0.21-0.25"
Pos2150="0-0-0.01-0.01-0-0-0.01-0-0-0"
Pos2200="0-0-0-0-0-0-0-0-0-0.00001"



downlinkList =[downlink2,downlink5,downlink12,downlink15,downlink20]
UplinkList=[Uplink2,Uplink5,Uplink12,Uplink15,Uplink20]
PositionList=[Pos1800,Pos1900,Pos2150,Pos2200]



def jains_fairness_index(throughputs):
    N = len(throughputs)
    if N == 0:
        return 0  # Avoid division by zero for empty lists
    num_users = len(throughputs)
    
    # Calculate the numerator (sum of throughputs)^2
    numerator = sum(throughputs)**2
    
    # Calculate the denominator (N * sum of squares of throughputs)
    denominator = num_users * sum(x**2 for x in throughputs)
    
    # Calculate the fairness index
    fairness_index = numerator / denominator if denominator != 0 else 0
    
    return fairness_index

Lists=[downlinkList,UplinkList,PositionList]
for list in Lists:
    
    if Lists.index(list)==1:
        downlink_Uplink_Position = "Uplink with"
    elif Lists.index(list)==2:
        downlink_Uplink_Position = "position"
    
    for x in list:
        Sum = 0
        SumofSquares = 0
        SquareofSums = 0
        number_strings = x.split('-')

    # Convert the list of strings to a list of floats (numbers)
        numbersArray = [float(num) for num in number_strings]
        #for number in numbersArray:
        #    SumofSquares = SumofSquares + number**2
        #    Sum = Sum + number
        #JainFairnessIndex = (SumofSquares)/(Sum**2)
        JainFairnessIndex=jains_fairness_index(numbersArray)
        if downlink_Uplink_Position == "position":
            if list.index(x)==0:
                print(f'{downlink_Uplink_Position} 1800: {"{:.3f}".format(JainFairnessIndex)}')
            elif list.index(x)==1:
                print(f'{downlink_Uplink_Position} 1900: {"{:.3f}".format(JainFairnessIndex)}')
            elif list.index(x)==2:
                print(f'{downlink_Uplink_Position} 2150: {"{:.3f}".format(JainFairnessIndex)}')
            elif list.index(x)==3:
                print(f'{downlink_Uplink_Position} 2200: {"{:.3f}".format(JainFairnessIndex)}')        
        else:
    # Now, 'numbers' contains the separated numbers as floating-point values
            print(f'{downlink_Uplink_Position} {len(number_strings)} UE: {"{:.3f}".format(JainFairnessIndex)}')
    




