function run_simulink_model(cfg)
% RUN_SIMULINK_MODEL  Module 6 - Telemedicine pipeline simulation
%
%  Simulates the end-to-end district DR screening workflow:
%
%   [Image Acquisition] --> [Bandwidth/Upload] --> [AI Processing]
%        --> [Triage] --> [Ophthalmologist Review] --> [Disposition]
%
%  Uses a discrete-event / queueing model implemented in MATLAB
%  (Simulink version also available - see create_simulink_model()).
%
%  Analyses:
%    - Patient throughput per day per centre
%    - Bandwidth bottleneck analysis
%    - Ophthalmologist workload (referral queue)
%    - System utilisation vs capacity
%    - Optimal centre-count for 100,000 patients/year

fprintf('\n--- Telemedicine Workflow Simulation ---\n');

%% Simulation parameters (from config)
N_centers    = cfg.slx.centersCount;
bw_kbps      = cfg.slx.bandwidth_kbps;
imgSize_kb   = cfg.slx.imgSize_kb;
procTime_s   = cfg.slx.procTime_s;
reviewTime_s = cfg.slx.reviewTime_s;
daySeconds   = cfg.slx.simDuration;

%% Derived timing constants
uploadTime_s  = (imgSize_kb * 8) / bw_kbps;   % seconds to upload one image
totalAI_s     = uploadTime_s + procTime_s;      % upload + inference
referralRate  = 0.28;   % ~28% of patients are referable (field data)
ophLoad_frac  = referralRate;  % fraction needing human review

%% Per-centre capacity
% 8-hour clinic day, pipeline processes one patient at a time per centre
clinicHours   = 8;
clinicSeconds = clinicHours * 3600;

% Patients/day/centre (AI-gated)
patientsPerDayPerCentre = floor(clinicSeconds / totalAI_s);
patientsPerDayTotal     = patientsPerDayPerCentre * N_centers;

% Ophthalmologist time: reviewing referrals
referralsPerDay    = round(patientsPerDayTotal * referralRate);
ophTimeRequired_s  = referralsPerDay * reviewTime_s;
ophWorkdayCapacity = 6 * 3600;   % 6-hour review session
ophsRequired       = ceil(ophTimeRequired_s / ophWorkdayCapacity);

%% Annual capacity
workingDaysPerYear    = 250;
annualCapacity        = patientsPerDayTotal * workingDaysPerYear;
targetAnnual          = cfg.slx.patientsPerYear;
centersNeeded         = ceil(targetAnnual / (patientsPerDayPerCentre * workingDaysPerYear));

%% Discrete-event Monte Carlo simulation (1 day)
rng(42, 'twister');
nSimPatients = min(500, patientsPerDayTotal);   % simulate N patients

arrivalRate  = nSimPatients / clinicSeconds;    % patients/second (Poisson)

% Generate inter-arrival times (exponential)
% Exponential inter-arrivals via inverse CDF: -ln(U)/rate  (no Stats Toolbox needed)
interArrivals = -log(rand(nSimPatients, 1)) / arrivalRate;
arrivalTimes  = cumsum(interArrivals);
arrivalTimes  = arrivalTimes(arrivalTimes < clinicSeconds);
nArrivals     = numel(arrivalTimes);

% Service times (processing pipeline)
serviceTimes  = totalAI_s * ones(nArrivals, 1) + 2*randn(nArrivals,1);
serviceTimes  = max(serviceTimes, 1);

% Queue simulation (M/D/1 approximation)
queueWait     = zeros(nArrivals, 1);
serverFree    = 0;
for k = 1:nArrivals
    startTime    = max(arrivalTimes(k), serverFree);
    queueWait(k) = startTime - arrivalTimes(k);
    serverFree   = startTime + serviceTimes(k);
end
endTimes      = arrivalTimes + queueWait + serviceTimes;

% Referral processing
isReferable   = rand(nArrivals, 1) < referralRate;
nReferrals    = sum(isReferable);

% Ophthalmologist queue (FIFO, assuming 1 ophthalmologist remote)
refTimes      = endTimes(isReferable);
refTimes      = sort(refTimes);
ophReview     = reviewTime_s * ones(nReferrals,1) + 5*randn(nReferrals,1);
ophReview     = max(ophReview, 15);
ophFree       = 0;
ophWait       = zeros(nReferrals, 1);
for k = 1:nReferrals
    ophStart   = max(refTimes(k), ophFree);
    ophWait(k) = ophStart - refTimes(k);
    ophFree    = ophStart + ophReview(k);
end

%% Print simulation results
fprintf('\n  ┌─────────────────────────────────────────────────────┐\n');
fprintf('  │        DISTRICT DR SCREENING - CAPACITY MODEL       │\n');
fprintf('  ├─────────────────────────────────────────────────────┤\n');
fprintf('  │ Infrastructure                                       │\n');
fprintf('  │   Screening centres:    %3d                         │\n', N_centers);
fprintf('  │   Rural bandwidth:      %d kbps                   │\n', bw_kbps);
fprintf('  │   Image upload time:    %.1f sec                    │\n', uploadTime_s);
fprintf('  │   AI inference time:    %.1f sec                    │\n', procTime_s);
fprintf('  │   Total per patient:    %.1f sec                    │\n', totalAI_s);
fprintf('  ├─────────────────────────────────────────────────────┤\n');
fprintf('  │ Daily Capacity                                       │\n');
fprintf('  │   Patients/centre/day:  %4d                        │\n', patientsPerDayPerCentre);
fprintf('  │   System total/day:     %4d                        │\n', patientsPerDayTotal);
fprintf('  │   Annual capacity:    %6d                        │\n', annualCapacity);
fprintf('  │   Target (100K/yr):   %6d  %s                  │\n', targetAnnual, ...
    bool2str(annualCapacity >= targetAnnual));
fprintf('  ├─────────────────────────────────────────────────────┤\n');
fprintf('  │ Referral Pathway                                     │\n');
fprintf('  │   Referral rate:        %.1f%%                       │\n', referralRate*100);
fprintf('  │   Referrals/day:        %4d                        │\n', referralsPerDay);
fprintf('  │   Ophthalmologists req: %4d                        │\n', ophsRequired);
fprintf('  │   Centres needed (100K):%4d                        │\n', centersNeeded);
fprintf('  ├─────────────────────────────────────────────────────┤\n');
fprintf('  │ Monte Carlo Sim (n=%d patients)                    │\n', nArrivals);
fprintf('  │   Mean AI queue wait:   %.1f sec                    │\n', mean(queueWait));
fprintf('  │   Max AI queue wait:    %.1f sec                    │\n', max(queueWait));
fprintf('  │   Referrals generated:  %4d (%.1f%%)               │\n', nReferrals, nReferrals/nArrivals*100);
fprintf('  │   Mean Oph wait:        %.1f min                    │\n', mean(ophWait)/60);
fprintf('  │   Max Oph wait:         %.1f min                    │\n', max(ophWait)/60);
fprintf('  └─────────────────────────────────────────────────────┘\n');

%% Plot simulation results
fig = figure('Visible','off', 'Position',[100 100 1300 800], 'Color','w');
sgtitle('Telemedicine DR Screening - Workflow Simulation', ...
    'FontSize',14, 'FontWeight','bold');

% 1. Timeline: patient flow
ax1 = subplot(2,3,1);
plot(arrivalTimes/60, 'b.', 'MarkerSize', 3);
hold on;
plot(endTimes(isReferable)/60, 'r.', 'MarkerSize', 5);
xlabel('Patient Index'); ylabel('Time (min)');
title('Patient Arrival & Completion Times', 'FontWeight','bold');
legend({'AI Arrival','Referral Complete'}, 'Location','northwest');
grid on;

% 2. Queue wait time histogram
ax2 = subplot(2,3,2);
histogram(queueWait, 20, 'FaceColor',[0.2 0.5 0.9], 'EdgeColor','w');
xlabel('Queue Wait (sec)'); ylabel('Count');
title('AI Processing Queue Wait', 'FontWeight','bold');
xline(mean(queueWait), 'r--', sprintf('Mean: %.1fs', mean(queueWait)), 'LineWidth',2);
grid on;

% 3. Ophthalmologist wait time
ax3 = subplot(2,3,3);
histogram(ophWait/60, 15, 'FaceColor',[0.9 0.4 0.1], 'EdgeColor','w');
xlabel('Ophthalmologist Wait (min)'); ylabel('Count');
title('Referral Review Wait Time', 'FontWeight','bold');
xline(mean(ophWait/60), 'b--', sprintf('Mean: %.0f min', mean(ophWait/60)), 'LineWidth',2);
grid on;

% 4. System utilisation vs bandwidth
ax4 = subplot(2,3,4);
bwRange   = [128 256 512 1024 2048];
capRange  = (clinicHours*3600) ./ ((bwRange.*1e3/8./imgSize_kb/1e3) .^-1 + procTime_s);
plot(bwRange, capRange, 'b-o', 'LineWidth', 2, 'MarkerSize', 8);
hold on;
xline(bw_kbps, 'r--', sprintf('Current: %d kbps', bw_kbps), 'LineWidth',2);
xlabel('Bandwidth (kbps)'); ylabel('Patients/centre/day');
title('Bandwidth vs. Throughput', 'FontWeight','bold'); grid on;
legend({'Capacity curve','Current bandwidth'}, 'Location','southeast');

% 5. Scale-up: centres needed
ax5 = subplot(2,3,5);
popSizes   = [10000 25000 50000 100000 250000 500000];
cenNeeded  = ceil(popSizes / (patientsPerDayPerCentre * workingDaysPerYear));
bar(1:numel(popSizes), cenNeeded, 'FaceColor',[0.3 0.7 0.4]);
set(ax5, 'XTickLabel', {'10K','25K','50K','100K','250K','500K'});
xlabel('Annual Target Patients'); ylabel('Centres Required');
title('Scale-Up Planning', 'FontWeight','bold'); grid on;
xline(find(popSizes==targetAnnual), 'r--', '100K target', 'LineWidth',2);

% 6. Resource allocation pie
ax6 = subplot(2,3,6);
timeBreakdown = [uploadTime_s, procTime_s, reviewTime_s*referralRate];
lbls = {sprintf('Upload (%.1fs)', uploadTime_s), ...
        sprintf('AI Inference (%.1fs)', procTime_s), ...
        sprintf('Oph Review (avg %.1fs)', reviewTime_s*referralRate)};
pie(timeBreakdown, lbls);
title('Time Budget per Patient', 'FontWeight','bold');
colormap(ax6, [0.4 0.6 0.9; 0.3 0.8 0.4; 0.9 0.5 0.2]);

% Save
outFile = fullfile(cfg.outputDir, 'simulink_workflow.png');
exportgraphics(fig, outFile, 'Resolution', 150);
fprintf('\n  Simulation figure saved: %s\n', outFile);
close(fig);

%% Try to create/open actual Simulink model
create_simulink_slx(cfg);
end

% =========================================================================
function create_simulink_slx(cfg)
% Create actual Simulink model for the telemedicine pipeline.
% Requires Simulink license.

modelName = cfg.slx.modelName;

try
    if ~license('test', 'Simulink')
        fprintf('  [INFO] Simulink license not available. Analytical model used.\n');
        return;
    end

    % Close existing model if open
    if bdIsLoaded(modelName), close_system(modelName, 0); end

    % Create new model
    new_system(modelName);
    open_system(modelName);

    % --- Set simulation parameters ---
    set_param(modelName, 'Solver','ode45', 'StopTime', num2str(cfg.slx.simDuration), ...
        'MaxStep','0.1');

    %% -- Add blocks --
    % 1. Patient Generator (Poisson arrivals)
    add_block('built-in/Constant', [modelName '/PatientArrivalRate'], ...
        'Value', num2str(100000/250/8/3600), 'Position',[50 50 130 80]);

    % 2. Image Upload (transport delay = bandwidth-limited)
    add_block('built-in/TransportDelay', [modelName '/UploadDelay'], ...
        'DelayTime', num2str((cfg.slx.imgSize_kb*8)/cfg.slx.bandwidth_kbps), ...
        'Position',[200 50 280 80]);

    % 3. AI Inference (fixed delay)
    add_block('built-in/TransportDelay', [modelName '/AIInference'], ...
        'DelayTime', num2str(cfg.slx.procTime_s), ...
        'Position',[350 50 430 80]);

    % 4. Triage (referral splitter) - using Switch block
    add_block('built-in/Switch', [modelName '/Triage'], ...
        'Threshold', num2str(1-0.28), ...
        'Position',[500 50 560 110]);

    % 5. Ophthalmologist review
    add_block('built-in/TransportDelay', [modelName '/OphReview'], ...
        'DelayTime', num2str(cfg.slx.reviewTime_s), ...
        'Position',[640 50 720 80]);

    % 6. Scope (output monitor)
    add_block('built-in/Scope', [modelName '/Throughput'], ...
        'Position',[800 50 850 80]);

    % Connect blocks
    add_line(modelName, 'PatientArrivalRate/1', 'UploadDelay/1');
    add_line(modelName, 'UploadDelay/1',         'AIInference/1');
    add_line(modelName, 'AIInference/1',          'Triage/1');
    add_line(modelName, 'Triage/1',               'OphReview/1');
    add_line(modelName, 'OphReview/1',            'Throughput/1');

    % Save model
    slxFile = fullfile(cfg.outputDir, [modelName '.slx']);
    save_system(modelName, slxFile);
    fprintf('  Simulink model saved: %s\n', slxFile);

    % Run simulation
    fprintf('  Running Simulink simulation...\n');
    sim(modelName);
    fprintf('  Simulink simulation complete.\n');

catch ME
    fprintf('  [WARN] Simulink model creation: %s\n', ME.message);
    fprintf('  Analytical simulation results used instead.\n');
end
end

% =========================================================================
function s = bool2str(b)
if b, s = '✓'; else, s = '✗ (add centres)'; end
end
