function cfg = dr_config()
% DR_CONFIG  Central configuration for OCULA AI Multi-Disease Suite
%   Returns a struct with all hyperparameters, paths and clinical thresholds.
%   Optimised for Snapdragon X (ARM64) - parallelism via parfor.

%% ── Paths ────────────────────────────────────────────────────────────
cfg.rootDir    = fileparts(mfilename('fullpath'));
cfg.outputDir  = fullfile(cfg.rootDir, 'reports');
cfg.modelDir   = fullfile(cfg.rootDir, 'models');
cfg.testImgDir = fullfile(cfg.rootDir, 'test_images');
cfg.benchDir   = fullfile(cfg.rootDir, 'benchmarks');

%% ── Hot-Folder Autonomous Daemon Paths ──────────────────────────────
cfg.hotfolder.incomingDir = fullfile(cfg.rootDir, 'incoming_fundus');
cfg.hotfolder.screenedDir = fullfile(cfg.rootDir, 'screened_reports');
cfg.hotfolder.routineDir  = fullfile(cfg.hotfolder.screenedDir, 'Clear_Routine');
cfg.hotfolder.urgentDir   = fullfile(cfg.hotfolder.screenedDir, 'Urgent_Referrals');

%% ── Image Quality ────────────────────────────────────────────────────
cfg.targetSize     = [512 512];   % resize all images to this
cfg.minSharpness   = 0.15;        % Laplacian variance threshold
cfg.minBrightness  = 30;         % mean pixel (0-255)
cfg.maxBrightness  = 220;
cfg.minFOV         = 0.55;       % retina circle fraction of frame

%% ── CLAHE Enhancement ─────────────────────────────────────────────────
cfg.clahe.NumTiles    = [8 8];
cfg.clahe.ClipLimit   = 0.02;
cfg.clahe.NBins       = 256;

%% ── Vessel Segmentation & Calibre (AVR) ──────────────────────────────
cfg.vessel.sigmas    = [1 2 3 4];   % Frangi filter scales
cfg.vessel.beta1     = 0.5;
cfg.vessel.beta2     = 15;
cfg.vessel.threshold = 0.12;
cfg.hypertension.normalAVR       = 0.67; % Normal Arteriolar-to-Venular Ratio
cfg.hypertension.narrowingThresh = 0.60; % AVR < 0.60 flags arteriolar narrowing

%% ── Microaneurysm Detection ──────────────────────────────────────────
cfg.ma.minArea       = 4;    % pixels
cfg.ma.maxArea       = 40;
cfg.ma.eccentricity  = 0.8;

%% ── Exudate & DME Detection ──────────────────────────────────────────
cfg.exudate.brightThresh = 0.75;   % normalised
cfg.exudate.minArea      = 10;
cfg.dme.csmeDistanceDD   = 0.80;   % <= 0.80 Optic Disc Diameters -> CSME
cfg.dme.modDistanceDD    = 1.50;   % <= 1.50 DD -> Moderate DME

%% ── Glaucoma Screening (Cup-to-Disc Ratio) ───────────────────────────
cfg.glaucoma.cdrSuspectThresh    = 0.65; % Vertical CDR > 0.65 => Glaucoma Suspect
cfg.glaucoma.cdrBorderlineThresh = 0.50; % CDR 0.50 - 0.65 => Borderline
cfg.glaucoma.cupBrightnessPerc   = 98.5; % Pallor seed inside OD

%% ── AMD Screening (Macular Drusen) ───────────────────────────────────
cfg.amd.minDrusenArea            = 5;    % pixels
cfg.amd.earlyDrusenCountThresh   = 5;
cfg.amd.intermDrusenAreaThresh   = 0.04; % fraction of macular zone

%% ── Haemorrhage Detection ────────────────────────────────────────────
cfg.haem.darkThresh      = 0.25;
cfg.haem.minArea         = 15;

%% ── Optic Disc ────────────────────────────────────────────────────────
cfg.od.brightnessPerc    = 97;     % top percentile for OD seed
cfg.od.radiiRange        = [30 90];

%% ── Deep Learning / Grading ──────────────────────────────────────────
cfg.dl.inputSize        = [224 224 3];
cfg.dl.numClasses       = 5;       % ICDR 0-4
cfg.dl.batchSize        = 8;
cfg.dl.referableThresh  = 2;       % Grade >= 2 => referable
cfg.dl.confThreshLow    = 0.60;    % below => uncertain -> review
cfg.dl.confThreshHigh   = 0.85;   % above => high confidence

%% ── Grad-CAM ──────────────────────────────────────────────────────────
cfg.gradcam.layer       = 'relu_final';  % target conv layer name
cfg.gradcam.alpha       = 0.5;           % overlay transparency

%% ── Clinical Thresholds ──────────────────────────────────────────────
cfg.clinSensitivity     = 0.90;
cfg.clinSpecificity     = 0.85;
cfg.reportLanguages     = {'en', 'es', 'hi', 'fr', 'ar'};

%% ── Output ────────────────────────────────────────────────────────────
cfg.saveReports    = true;
cfg.verbosity      = 1;   % 0=quiet, 1=normal, 2=debug
cfg.useParallel    = true; % parfor on Snapdragon X multi-core
cfg.maxWorkers     = 8;    % Snapdragon X Elite = up to 12 cores

%% ── Create output dirs if missing ────────────────────────────────────
dirs = {cfg.outputDir, cfg.modelDir, cfg.hotfolder.incomingDir, ...
        cfg.hotfolder.routineDir, cfg.hotfolder.urgentDir};
for i = 1:numel(dirs)
    if ~exist(dirs{i},'dir'), mkdir(dirs{i}); end
end
end
