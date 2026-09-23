%% =========================================================================
%  DEMO RUNNER - DR Screening System
%  Run this script to test the pipeline without any real images.
%  Creates 5 synthetic fundus images (Grade 0-4) and runs the full pipeline.
%
%  Estimated runtime (Snapdragon X Elite):
%    Without GPU DL inference: ~30-60 seconds
%    With GPU DL inference:    ~10-15 seconds
% =========================================================================

clearvars; close all; clc;
fprintf('=======================================================\n');
fprintf('  DR SCREENING SYSTEM - DEMO MODE\n');
fprintf('  Snapdragon X Elite / ARM64 Optimised\n');
fprintf('=======================================================\n\n');

addpath(genpath(pwd));

% Load config
cfg = dr_config();
cfg.verbosity = 1;

% Delete any existing synthetic images for fresh demo
synFiles = dir(fullfile(cfg.testImgDir,'synthetic_grade*.png'));
for i=1:numel(synFiles)
    delete(fullfile(synFiles(i).folder, synFiles(i).name));
end

% Run full pipeline
tic;
main_dr_pipeline;
elapsed = toc;

fprintf('\n=======================================================\n');
fprintf('  Demo complete in %.1f seconds.\n', elapsed);
fprintf('  Reports: %s\n', cfg.outputDir);
fprintf('  Open report_image001.png ... report_image005.png\n');
fprintf('  Open screening_dashboard.png for population view\n');
fprintf('  Open simulink_workflow.png for capacity planning\n');
fprintf('=======================================================\n');
