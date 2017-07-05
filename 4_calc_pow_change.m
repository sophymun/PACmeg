%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 
% 4_calc_pow_change.m
%
% This is a script to compute the % change in power from 1-100Hz
% usng data from the the V1 virtual electrode. A multi-taper approach is
% employed.
%
% Written by: Robert Seymour, June 2017
%
% Runtime: 10-15 minutes
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Load computer-specific information
restoredefaultpath
sensory_PAC;
addpath(fieldtrip_dir);
ft_defaults

% If you do not run these lines you will have to manually specify:
% - subject = subject list
% - data_dir = directory which contains the MEG & anatomical information
% - scripts_dir = directory with ALL the scripts
% - fieldtrip_dir = directory containing the Fieldtrip toolbox

%% Create figure to be used
figure; hold on; 
perc_change_all = []; % variabe to hold output from all subjects

%% Start loop for each subject
for i = 1:length(subject)
    
    % cd to the right place and load the V1 virtual electrode
    
    load([scripts_dir '\' subject{i} '\VE_V1.mat']);
    
    % Calculate Power in Grating & Baseline Periods
    cfg = [];
    cfg.method = 'mtmconvol';
    cfg.output = 'pow';
    cfg.foi = 1:1:100; %1-100Hz
    cfg.toi = 0.3:0.02:1.5; %300-1200ms period
    cfg.t_ftimwin    = ones(length(cfg.foi),1).*0.5;
    cfg.tapsmofrq  = ones(length(cfg.foi),1).*8;
    multitaper_post = ft_freqanalysis(cfg, VE_V1);
    cfg.toi = -1.5:0.02:-0.3; %change time-window
    multitaper_pre = ft_freqanalysis(cfg, VE_V1);
    
    % Calculate % change by averaging over time
    perc_change = (squeeze(mean(multitaper_post.powspctrm,3))...
        -  squeeze(mean(multitaper_pre.powspctrm,3)));
    perc_change(:,:) = perc_change(:,:)./squeeze(mean(multitaper_pre.powspctrm,3))
    perc_change(:,:) = perc_change(:,:)*100;
    
    % Add to array outside the loop
    perc_change_all(i,:) = perc_change;

end

%% Add overall mean % change to graph in black and add information to the graph

% This corresponds to Figure 3D

average_change = mean(perc_change_all);
figHandle = figure;
% Add the line to the figure
hold on;
for sub = 1:length(subject)
    plot([1:1:100],perc_change_all(sub,:),'LineWidth',3);
    hold on;
end
plot([1:1:100],average_change,'k','LineWidth',6);
ylabel('% Power Change');
xlabel('Frequency (Hz)');
set(gca,'FontName','Arial');
set(gca,'FontSize',20);
set(gcf, 'Color', 'w');

