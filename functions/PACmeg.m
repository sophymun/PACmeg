function [MI_matrix_raw,MI_matrix_surr] = PACmeg(cfg,data)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% PACmeg: a function to do PAC
%
% Author: Robert Seymour (robert.seymour@mq.edu.au)
%
%%%%%%%%%%%
% Inputs:
%%%%%%%%%%%
%
% data              = data for PAC (size: 1*time)
% cfg.Fs            = Sampling frequency (in Hz)
% cfg.phase_freqs   = Phase Frequencies in Hz (e.g. [8:1:13])
% cfg.amp_freqs     = Amplitude Frequencies in Hz (e.g. [40:2:100])
% cfg.filt_order    = Filter order used by ft_preproc_bandpassfilter
%
% cfg.method        = Method for PAC Computation:
%                   ('Tort','Ozkurt','PLV','Canolty)
% 
% cfg.surr_method   = Method to compute surrogates ('[], swap_blocks')
% cfg.surr_N        = Number of iterations to use for surrogate analysis
%
%
%%%%%%%%%%%
% Outputs:
%%%%%%%%%%%
%
% - MI_matrix_raw   = comodulagram matrix (size: amp*phase)
% - MI_matrix_surr  = surrogate comodulagram matrix (size: surr*amp*phase)
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Get function inputs
% Get sampling frequency
Fs = ft_getopt(cfg,'Fs',[]);

if isempty(Fs)
    error('Please Specify cfg.Fs');
elseif ~isnumeric(Fs)
    error('cfg.Fs needs to be numeric (e.g. 1000)');
end

% Get phase frequencies
phase_freqs = ft_getopt(cfg,'phase_freqs',[]);

if isempty(phase_freqs)
    error('Please Specify cfg.phase_freqs');
end

% Get amplitude frequencies
amp_freqs = ft_getopt(cfg,'amp_freqs',[max(phase_freqs):2:Fs/2]);

% Get filter order
filt_order = ft_getopt(cfg,'filt_order',4);

% Get amplitude bandwidth method
amp_bandw_method = ft_getopt(cfg,'amp_bandw_method','maxphase');
amp_bandw = ft_getopt(cfg,'amp_bandw',10);

% Get PAC Method
method = ft_getopt(cfg,'method','tort');
fprintf('Using the %s method for PAC computation\n',method);

% Get surrogate method & number of iterations
surr_method = ft_getopt(cfg,'surr_method',[]);
surr_N = ft_getopt(cfg,'surr_N',200);

%% Check inputs

% Check whether the inouts are numbers(!)
if ~floor(phase_freqs) == phase_freqs
    error('Numeric Values ONLY for Phase');
end

if ~floor(amp_freqs) == amp_freqs
    ft_error('Numeric Values ONLY for Amplitude');
end

% Give user a warning if using low-frequencies for phase
if min(phase_freqs) < 7 && filt_order > 3
    ft_warning(['Think about using a lower filter order '...
        '(e.g. cfg.filt_order = 3)']);
end

% Check whether PAC can be detected
switch amp_bandw_method
    
    case 'number'
        % If the bandwidth is less than the maximum phase frequency...
        if amp_bandw < max(phase_freqs)
            
            error(['You will not be able to detect PAC with this configuration.'...
                ' Reduce the phase to ' ...
                num2str(amp_bandw) 'Hz, or increase the amplitude bandwidth to '...
                num2str(max(phase_freqs)+1) 'Hz']);
        end
    case 'maxphase'
        % If minimum
        if min(amp_freqs) - max(phase_freqs)*1.5 < max(phase_freqs)
            error(['You will not be able to detect PAC with this configuration.'])
        end
    case 'centre_freq'
        % If
        if min(amp_freqs)/2.5 < max(phase_freqs)
            try
                low_amp = min(amp_freqs(find(amp_freqs/2.5 > max(phase_freqs))));
            catch
                low_amp = '?';
            end
            
            error(['You will not be able to detect PAC with this configuration.'...
                ' Reduce the phase to ' ...
                num2str(min(amp_freqs)/2.5) 'Hz, or increase the amplitude to '...
                num2str(low_amp) 'Hz']);
        end
end

%% Filter Phase Frequencies & take 'angle'
disp('Filtering Phase...');

phase_filtered = zeros(length(phase_freqs),length(data));

for phase = 1:length(phase_freqs)
    try
        [filt] = ft_preproc_bandpassfilter(data, Fs,...
            [phase_freqs(phase)-1 phase_freqs(phase)+1],...
            filt_order, 'but', 'twopass', 'no');
    catch
        error('Could not filter ... Perhaps try a lower filter order');
    end
    
    phase_filtered(phase,:) = ft_preproc_hilbert(filt, 'angle');
    clear filt
end

%% Filter Amplitude & Take 'abs'
disp('Filtering Amplitude...');

amp_filtered = zeros(length(amp_freqs),length(data));

for amp = 1:length(amp_freqs)
    
    % Switch based on bandwidth method
    switch amp_bandw_method
        
        case 'number'
            
            if amp == 1
                fprintf('Bandwidth = %.1fHz\n',amp_bandw);
            end
            
            Af1 = amp_freqs(amp) - amp_bandw;
            Af2 = amp_freqs(amp) + amp_bandw;
            %
        case 'maxphase'
            if amp == 1
                fprintf('Bandwidth = %.1fHz\n',1.5.*max(phase_freqs));
            end
            %
            Af1 = amp_freqs(amp) - 1.5*max(phase_freqs);
            Af2 = amp_freqs(amp) + 1.5*max(phase_freqs);
            
        case 'centre_freq'
            if amp == 1
                fprintf('Bandwidth = 2.5* centre amplitude frequency\n')
            end
            
            Af1 = round(amp_freqs(amp) -(amp_freqs(amp)/2.5));
            Af2 = round(amp_freqs(amp) +(amp_freqs(amp)/2.5));
            
            
    end
    
    % Filter
    [filt] = ft_preproc_bandpassfilter(data, Fs,...
        [Af1 Af2],filt_order, 'but', 'twopass', 'no');
    
    % Take abs
    amp_filtered(amp,:) = ft_preproc_hilbert(filt, 'abs');
    clear filt Af1 Af2
end

%% Compute Surrogates
if ~isempty(surr_method)
    % Switch based on the surrogate methods
    switch surr_method
        case 'swap_blocks'
            
            % Get random points to segment
            surr_data_rand = randi([size(amp_filtered,2)./10 ...
                size(amp_filtered,2)], size(amp_filtered,1), surr_N);
            
            % Create matrix of zeros
            surr_data = zeros(surr_N,size(amp_filtered,1),...
                size(amp_filtered,2));
            
            disp('Computing surrogate data...');
            for surr = 1:surr_N
                for amp = 1:size(amp_filtered,1)
                    
                    % Split data
                    seg1 = amp_filtered(amp,surr_data_rand(amp,surr):end);
                    seg2 = amp_filtered(amp,1:surr_data_rand(amp,surr)-1);
                    
                    surr_data(surr,amp,:) = [seg1 seg2];
                end
            end
    end
end

%% PAC computation
MI_matrix_raw = zeros(length(amp_freqs),length(phase_freqs));

for phase = 1:length(phase_freqs)
    for amp = 1:length(amp_freqs)
        
        % Switch based on the method of PAC computation
        switch method
            case 'tort'
                [MI] = calc_MI_tort(phase_filtered(phase,:),...
                    amp_filtered(amp,:),18);
                
            case 'ozkurt'
                [MI] = calc_MI_ozkurt(phase_filtered(phase,:),...
                    amp_filtered(amp,:));
                
            case 'PLV'
                [MI] = cohen_PLV(phase_filtered(phase,:),...
                    amp_filtered(amp,:));
                
            case 'canolty'
                [MI] = calc_MI_canolty(phase_filtered(phase,:),...
                    amp_filtered(amp,:));
                
        end
        
        % Add to matrix outside the loop
        MI_matrix_raw(amp,phase) = MI;
    end
end

%% Perform surrogate PAC Analysis
if ~isempty(surr_method)
    
    % Matrix to hold surrogates
    MI_matrix_surr = zeros(surr_N,length(amp_freqs),length(phase_freqs));
    
    % Length of amplitudes
    len_of_amp = size(amp_filtered,2);

    % Start surrogate loop
    ft_progress('init', 'text',    'Please wait...')
    for surr = 1:surr_N
        ft_progress(surr/surr_N, 'Surrogate %d of %d', surr, surr_N)  % show string, x=i/N
        
        for phase = 1:length(phase_freqs)
            for amp = 1:length(amp_freqs)
                
                % Switch based on the method of PAC computation
                switch method
                    case 'tort'
                        [MI] = calc_MI_tort(phase_filtered(phase,:),...
                            reshape(surr_data(surr,amp,:),[1 len_of_amp]),18);
                        
                    case 'ozkurt'
                        [MI] = calc_MI_ozkurt(phase_filtered(phase,:),...
                            reshape(surr_data(surr,amp,:),[1 len_of_amp]));
                        
                    case 'PLV'
                        [MI] = cohen_PLV(phase_filtered(phase,:),...
                            reshape(surr_data(surr,amp,:),[1 len_of_amp]));
                        
                    case 'canolty'
                        [MI] = calc_MI_canolty(phase_filtered(phase,:),...
                            reshape(surr_data(surr,amp,:),[1 len_of_amp]));
                        
                end
                
                % Add to matrix outside the loop
                MI_matrix_surr(surr,amp,phase) = MI;
            end
        end
    end
ft_progress('close')
    
    
end

