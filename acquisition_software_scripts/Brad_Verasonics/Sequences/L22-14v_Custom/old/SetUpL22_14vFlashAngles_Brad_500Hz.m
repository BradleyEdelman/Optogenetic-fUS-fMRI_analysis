% Notice:
%   This file is provided by Verasonics to end users as a programming
%   example for the Verasonics Vantage Research Ultrasound System.
%   Verasonics makes no claims as to the functionality or intended
%   application of this program and the user assumes all responsibility
%   for its use
%
% File name: SetUpL22_14vFlashAngles.m - Example of plane wave imaging with multiple steered angle transmits
%
% Description:
%   Sequence programming file for L22-14v Linear array, using a plane wave
%   transmits with multiple steering angles. All 128 transmit and receive
%   channels are active for each acquisition. This script uses 4X sampling
%   with A/D sample rate of 62.5 MHz for a 15.625 MHz processing center
%   frequency.  Transmit is at 17.8 MHz and receive bandpass filter has
%   been shifted to 18 MHz center frequency, 13.9MHz -3 dB bandwidth to
%   support the 12 MHz bandwidth of the L22-14v (18MHz center frequency,
%   67% bandwidth). Processing is asynchronous with respect to acquisition.
%
% Last update:
% 12/07/2015 - modified for SW 3.0

clear all

% % % P.path = 'C:/Users/verasonics/Documents/Ultrasound Data/';
% % % P.filePrefix = 'SaveIQData';
% % % 
% % % P.time = clock;
% % % P.dateStr = strcat('_',num2str(P.time(2)), '-', num2str(P.time(3)), '-',...
% % %     num2str(P.time(1)));
% % % 
% % % P.saveAcquisition = 0; %Default doesn't save
% % % P.settingsNumber = 1; %Which version of the settings are you on?
% % % P.settingsChanged = 1; %Whether the settings have changed since the last save.  Starts at 1 so that it doesn't automatically iterate to 2
% % % 
% % % P.runNumber = 1; %What run on the current setting?
% % % P.itNumber = 1; %What iteration on the current run?

P.startDepth = 5;   % Acquisition depth in wavelengths
P.endDepth = 192;   % This should preferrably be a multiple of 128 samples.

RcvProfile.LnaZinSel = 31;

na = 5;      % Set na = number of angles.
if (na > 1)
    dtheta = (12*pi/180)/(na-1);
    P.startAngle = -12*pi/180/2;
else
    dtheta = 0;
    P.startAngle=0;
end

PRF=na*500; % Acquisition Rate
pgs=200; % Number of pages (containing na compounded recons)

% Define system parameters.
Resource.Parameters.numTransmit = 128;      % number of transmit channels.
Resource.Parameters.numRcvChannels = 128;    % number of receive channels.
Resource.Parameters.speedOfSound = 1540;    % set speed of sound in m/sec before calling computeTrans
Resource.Parameters.verbose = 2;
Resource.Parameters.initializeOnly = 0;
Resource.Parameters.simulateMode = 1;

% Specify Trans structure array.
Trans.name = 'L22-14v';
Trans.units = 'wavelengths';
Trans = computeTrans(Trans);
Trans.maxHighVoltage = 25; % mfr data sheet lists 30 Volt limit

% Specify PData structure array.
PData(1).PDelta = [0.4, 0, 0.25];
PData(1).Size(1) = ceil((P.endDepth-P.startDepth)/PData(1).PDelta(3)); % startDepth, endDepth and pdelta set PData(1).Size.
PData(1).Size(2) = ceil((Trans.numelements*Trans.spacing)/PData(1).PDelta(1));
PData(1).Size(3) = 1;      % single image page
PData(1).Origin = [-Trans.spacing*(Trans.numelements-1)/2,0,P.startDepth]; % x,y,z of upper lft crnr.
% No PData.Region specified, so a default Region for the entire PData array will be created by computeRegions.

% Specify Media object. 'pt1.m' script defines array of point targets.
% pt1;
% Media.attenuation = -0.5;
% Media.function = 'movePoints';
Media.MP=[0,0,100,1];
Media.NumPoints=1;

% Specify Resources.
Resource.RcvBuffer(1).datatype = 'int16';
Resource.RcvBuffer(1).rowsPerFrame = na*pgs*2048; % this size allows for maximum range
Resource.RcvBuffer(1).colsPerFrame = Resource.Parameters.numRcvChannels;
Resource.RcvBuffer(1).numFrames = 1;    % 30 frames stored in RcvBuffer.
Resource.InterBuffer(1).datatype = 'complex';
Resource.InterBuffer(1).numFrames = 1;   % one intermediate buffer needed.
Resource.InterBuffer(1).pagesPerFrame = pgs;
Resource.ImageBuffer(1).numFrames = 1;
% No image display to reduce time delays

% Specify Transmit waveform structure.
TW.type = 'parametric';
TW.Parameters = [18, 0.67, 3, 1];   % 18 MHz center frequency, 67% pulsewidth 1.5 cycle burst

% Specify TX structure array.
TX = repmat(struct('waveform', 1, ...
                   'Origin', [0.0,0.0,0.0], ...
                   'Apod', kaiser(Resource.Parameters.numTransmit,1)', ...
                   'focus', 0.0, ...
                   'Steer', [0.0,0.0], ...
                   'Delay', zeros(1,Trans.numelements)), 1, na);
% - Set event specific TX attributes.
if fix(na/2) == na/2       % if na even
    P.startAngle = (-(fix(na/2) - 1) - 0.5)*dtheta;
else
    P.startAngle = -fix(na/2)*dtheta;
end
for n = 1:na   % na transmit events
    TX(n).Steer = [(P.startAngle+(n-1)*dtheta),0.0];
    TX(n).Delay = computeTXDelays(TX(n));
end


% Specify TGC Waveform structure.
TGC.CntrlPts = [330 560 780 1010 1023 1023 1023 1023]; % [0,511,716,920,1023,1023,1023,1023];
TGC.rangeMax = P.endDepth;
TGC.Waveform = computeTGCWaveform(TGC);

% Specify Receive structure arrays.
% - We need na Receives for every frame.

% sampling center frequency is 15.625, but we want the bandpass filter
% centered on the actual transducer center frequency of 18 MHz with 67%
% bandwidth, or 12 to 24 MHz.  Coefficients below were set using
% "filterTool" with normalized cf=1.15 (18 MHz), bw=0.85,
% xsn wdth=0.41 resulting in -3 dB 0.71 to 1.6 (11.1 to 25 MHz), and
% -20 dB 0.57 to 1.74 (8.9 to 27.2 MHz)
%
BPF1 = [ -0.00009 -0.00128 +0.00104 +0.00085 +0.00159 +0.00244 -0.00955 ...
         +0.00079 -0.00476 +0.01108 +0.02103 -0.01892 +0.00281 -0.05206 ...
         +0.01358 +0.06165 +0.00735 +0.09698 -0.27612 -0.10144 +0.48608 ];

maxAcqLength = ceil(sqrt(P.endDepth^2 + ((Trans.numelements-1)*Trans.spacing)^2));
Receive = repmat(struct('Apod', ones(1,Trans.numelements), ...
                        'startDepth', P.startDepth, ...
                        'endDepth', maxAcqLength,...
                        'TGC', 1, ...
                        'bufnum', 1, ...
                        'framenum', 1, ...
                        'acqNum', 1, ...
                        'sampleMode', 'NS200BW', ...
                        'InputFilter', BPF1, ...
                        'mode', 0, ...
                        'callMediaFunc', 0), 1, pgs*na*Resource.RcvBuffer(1).numFrames);

% - Set event specific Receive attributes for each frame.
for i = 1:Resource.RcvBuffer(1).numFrames
    Receive(na*(i-1)+1).callMediaFunc = 1;
    for j = 1:na*pgs % # of receive events equals # pages * # angles
        Receive(na*(i-1)+j).framenum = i;
        Receive(na*(i-1)+j).acqNum = j;
    end
end

% Specify Recon structure arrays.
% - We need one Recon structure which will be used for each frame.
Recon = struct('senscutoff', 0.6, ...
               'pdatanum', 1, ...
               'rcvBufFrame',-1, ...
               'IntBufDest', [1,1], ...
               'ImgBufDest', [1,-1], ...
               'RINums', 1:na*pgs);

% Define ReconInfo structures.
% We need na ReconInfo structures for na steering angles.
ReconInfo = repmat(struct('mode', 'accumIQ', ...  % default is to accumulate IQ data.
                   'txnum', 1, ...
                   'rcvnum', 1, ...
                   'regionnum', 1), 1, na*pgs);
% % - Set specific ReconInfo attributes.
if na>1
    
    for j = 1:na*pgs  % For each row in the column
        
        if isequal(rem(j,na),1)
            ReconInfo(j).mode = 'replaceIQ'; % replace IQ data every na acquisitions
        end
        
        if isequal(rem(j,na),0) % cycle through angle acquisitions in each page
            ReconInfo(j).txnum=na;
        else
            ReconInfo(j).txnum=rem(j,na);
        end
        
        ReconInfo(j).rcvnum = j;
        ReconInfo(j).pagenum = ceil(j/na);
        
        if isequal(rem(j,na),0) % Acummulate angle data every na acquisitions
            ReconInfo(j).mode = 'accumIQ_replaceIntensity';
        end
        
    end
        
else
    ReconInfo(1).mode = 'replaceIntensity';
end

% Specify an external processing event.
% Process(1).classname = 'External';
% Process(1).method = 'saveData';
% Process(1).Parameters = {'srcbuffer','inter',... % name of buffer to process.
%                     'srcbufnum',1,...
%                     'srcframenum',1,...
%                     'srcframenum',[1,pgs], ...
%                     'dstbuffer','none'};

% Specify SeqControl structure arrays.
SeqControl(1).command = 'jump'; % jump back to start
SeqControl(1).argument = 1;
SeqControl(2).command = 'timeToNextAcq';  % time between synthetic aperture acquisitions
SeqControl(2).argument = 1/PRF*1e6; % Acquire at PRF
% SeqControl(3).command = 'returnToMatlab';
nsc = 3; % nsc is count of SeqControl objects

% Specify Event structure arrays.
n = 1;
for i = 1:Resource.RcvBuffer(1).numFrames
    for j = 1:na*pgs                      % Acquire frame
        Event(n).info = 'Full aperture.';
        
        if isequal(rem(j,na),0)
            Event(n).tx = na;
        else
            Event(n).tx=rem(j,na);
        end
        
        Event(n).rcv = na*(i-1)+j;
        Event(n).recon = 0;
        Event(n).process = 0;
        Event(n).seqControl = 2;
        n = n+1;
    end

end
Event(n-1).seqControl = [2,nsc]; % modify last acquisition Event's seqControl
      SeqControl(nsc).command = 'transferToHost'; % transfer frame to host buffer
      nsc = nsc+1;
      
Event(n).info = 'recon';
Event(n).tx = 0;
Event(n).rcv = 0;
Event(n).recon = 1;
Event(n).process = 0;
Event(n).seqControl = 0;

% Event(n).info = 'save';
% Event(n).tx = 0;
% Event(n).rcv = 0;
% Event(n).recon = 0;
% Event(n).process = 1;
% Event(n).seqControl = 0;

% Save all the structures to a .mat file.
save('MatFiles/L22-14vFlashAngles');
VSX
return

% **** Callback routines to be converted by text2cell function. ****
%SensCutoffCallback - Sensitivity cutoff change
ReconL = evalin('base', 'Recon');
for i = 1:size(ReconL,2)
    ReconL(i).senscutoff = UIValue;
end
assignin('base','Recon',ReconL);
Control = evalin('base','Control');
Control.Command = 'update&Run';
Control.Parameters = {'Recon'};
assignin('base','Control', Control);
return
%SensCutoffCallback

%RangeChangeCallback - Range change
simMode = evalin('base','Resource.Parameters.simulateMode');
% No range change if in simulate mode 2.
if simMode == 2
    set(hObject,'Value',evalin('base','P.endDepth'));
    return
end
Trans = evalin('base','Trans');
Resource = evalin('base','Resource');
scaleToWvl = Trans.frequency/(Resource.Parameters.speedOfSound/1000);

P = evalin('base','P');
P.endDepth = UIValue;
if isfield(Resource.DisplayWindow(1),'AxesUnits')&&~isempty(Resource.DisplayWindow(1).AxesUnits)
    if strcmp(Resource.DisplayWindow(1).AxesUnits,'mm');
        P.endDepth = UIValue*scaleToWvl;
    end
end
assignin('base','P',P);

evalin('base','PData(1).Size(1) = ceil((P.endDepth-P.startDepth)/PData(1).PDelta(3));');
evalin('base','PData(1).Region = computeRegions(PData(1));');
evalin('base','Resource.DisplayWindow(1).Position(4) = ceil(PData(1).Size(1)*PData(1).PDelta(3)/Resource.DisplayWindow(1).pdelta);');
Receive = evalin('base', 'Receive');
maxAcqLength = ceil(sqrt(P.endDepth^2 + ((Trans.numelements-1)*Trans.spacing)^2));
for i = 1:size(Receive,2)
    Receive(i).endDepth = maxAcqLength;
end
assignin('base','Receive',Receive);
evalin('base','TGC.rangeMax = P.endDepth;');
evalin('base','TGC.Waveform = computeTGCWaveform(TGC);');
Control = evalin('base','Control');
Control.Command = 'update&Run';
Control.Parameters = {'PData','InterBuffer','ImageBuffer','DisplayWindow','Receive','TGC','Recon'};
assignin('base','Control', Control);
assignin('base', 'action', 'displayChange');
return
%RangeChangeCallback
