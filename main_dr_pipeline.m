%% =========================================================================
%  EXPLAINABLE AI FOR DIABETIC RETINOPATHY SCREENING - RURAL INDIA
%  Main Pipeline Controller
%  Optimised for Snapdragon X Elite / ARM64 via MATLAB ARM64 runtime
%
%  Pipeline Modules:
%    1. Image Quality Assessment & Enhancement
%    2. Retinal Structure Segmentation
%    3. DR Severity Grading (ICDR 0-4)
%    4. Explainability (Grad-CAM + Reports)
%    5. Simulink Workflow Simulation
%
%  ICDR Grading Scale:
%    Grade 0: No DR
%    Grade 1: Mild NPDR  (microaneurysms only)
%    Grade 2: Moderate NPDR (referable threshold)
%    Grade 3: Severe NPDR
%    Grade 4: Proliferative DR
%
%  Clinical Targets: Sensitivity >90%, Specificity >85% for Grade >=2
%  Author : DR-AI Team | Version: 2.0
% =========================================================================

clearvars; close all; clc;
addpath(genpath(pwd));   % add all sub-folders to path

fprintf('=======================================================\n');
fprintf('  DR Screening System  -  Rural India Deployment\n');
fprintf('  Platform: %s | MATLAB %s\n', computer, version('-release'));
fprintf('=======================================================\n\n');

%% 0. CONFIGURATION
cfg = dr_config();

%% 1. DATA INGESTION
fprintf('[1/6] Loading fundus image(s)...\n');
[imgList, labelList] = load_fundus_dataset(cfg);

%% 2. IMAGE QUALITY ASSESSMENT & ENHANCEMENT
fprintf('[2/6] Image Quality Assessment & Enhancement...\n');
[enhancedImgs, qcResults] = batch_quality_pipeline(imgList, cfg);

%% 3. RETINAL STRUCTURE SEGMENTATION
fprintf('[3/6] Retinal Structure Segmentation...\n');
segResults = batch_segment_retina(enhancedImgs, cfg);

%% 4. DR SEVERITY GRADING
fprintf('[4/6] DR Severity Grading (ICDR 0-4)...\n');
[gradeResults, netFeatures] = batch_grade_dr(enhancedImgs, segResults, cfg);

%% 5. EXPLAINABILITY MODULE
fprintf('[5/6] Generating Explainability Reports (Grad-CAM)...\n');
batch_explain_and_report(enhancedImgs, gradeResults, netFeatures, ...
                         segResults, cfg);

%% 6. PERFORMANCE VALIDATION
fprintf('[6/6] Clinical Validation Metrics...\n');
if ~isempty(labelList) && ~all(isnan(labelList))
    validate_performance(gradeResults, labelList, cfg);
else
    fprintf('  No ground-truth labels available. Skipping validation.\n');
end

%% 7. SIMULINK SIMULATION
fprintf('\n[7/7] Simulink Telemedicine Workflow Simulation...\n');
run_simulink_model(cfg);

fprintf('\n=======================================================\n');
fprintf('Pipeline complete. Reports in: %s\n', cfg.outputDir);
fprintf('=======================================================\n');
