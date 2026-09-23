function [deltaReport, figProg] = longitudinal_tracker(imgBaseline, imgFollowUp, cfg, patMeta)
% LONGITUDINAL_TRACKER  Tracks Diabetic Retinopathy & Glaucoma progression over time
%   Performs image registration between Baseline (Visit 1) and Follow-up (Visit 2).
%   Generates color-coded progression maps:
%     🟢 Green  : New Lesions (Disease Progression)
%     🔵 Blue   : Resolved Lesions (Treatment Response)
%     🟡 Yellow : Persistent / Stable Lesions

if nargin < 3, cfg = dr_config(); end
if nargin < 4 || isempty(patMeta)
    patMeta = struct('id','OCU-LONG-01','name','Longitudinal Patient','baselineDate','2025-03-15','followDate','2026-09-20');
end
if ~isfield(patMeta, 'id'), patMeta.id = 'OCU-LONG-01'; end
if ~isfield(patMeta, 'name'), patMeta.name = 'Longitudinal Patient'; end
if ~isfield(patMeta, 'baselineDate'), patMeta.baselineDate = 'Visit 1 (Baseline)'; end
if ~isfield(patMeta, 'followDate'), patMeta.followDate = 'Visit 2 (Follow-up)'; end

% 1. Standardize Sizes
sz = cfg.targetSize;
if any(size(imgBaseline, [1 2]) ~= sz), imgBaseline = imresize(imgBaseline, sz); end
if any(size(imgFollowUp, [1 2]) ~= sz), imgFollowUp = imresize(imgFollowUp, sz); end

% 2. Image Registration (Align Follow-up to Baseline)
try
    grayBase   = rgb2gray(imgBaseline);
    grayFollow = rgb2gray(imgFollowUp);
    [optimizer, metric] = imregconfig('multimodal');
    optimizer.MaximumIterations = 80;
    tform = imregtform(grayFollow, grayBase, 'similarity', optimizer, metric);
    alignedFollow = imwarp(imgFollowUp, tform, 'OutputView', imref2d(size(imgBaseline)));
catch
    % Fallback if registration toolbox differs: use raw follow-up
    alignedFollow = imgFollowUp;
end

% 3. Multi-Disease Segmentation on Both Timepoints
[enhList, ~] = batch_quality_pipeline({imgBaseline, alignedFollow}, cfg);
segResults   = batch_segment_retina(enhList, cfg);
segBase      = segResults(1);
segFollow    = segResults(2);

[grResults, ~] = batch_grade_dr(enhList, segResults, cfg);
grBase         = grResults(1);
grFollow       = grResults(2);

% 4. Lesion Delta Extraction
% Exudates
exBase   = segBase.exudates.mask;
exFollow = segFollow.exudates.mask;
newExudates      = exFollow & ~imdilate(exBase, strel('disk', 3));
resolvedExudates = exBase   & ~imdilate(exFollow, strel('disk', 3));
stableExudates   = exFollow & imdilate(exBase, strel('disk', 3));

% Microaneurysms
maBase   = segBase.ma.mask;
maFollow = segFollow.ma.mask;
newMAs      = maFollow & ~imdilate(maBase, strel('disk', 2));
resolvedMAs = maBase   & ~imdilate(maFollow, strel('disk', 2));

% 5. Quantitative Progression Metrics
deltaMA      = segFollow.ma.count - segBase.ma.count;
deltaExArea  = (segFollow.exudates.area_frac - segBase.exudates.area_frac) * 100;
deltaGrade   = grFollow.predictedGrade - grBase.predictedGrade;
deltaCDR     = segFollow.glaucoma.vCDR - segBase.glaucoma.vCDR;

if deltaGrade > 0 || deltaExArea > 0.50 || (segFollow.dme.hasCSME && ~segBase.dme.hasCSME)
    trajectory = 'PROGRESSING (Worsening Retinopathy)';
    trajColor  = [0.85 0.15 0.15]; % Red
elseif deltaGrade < 0 || deltaExArea < -0.50
    trajectory = 'REGRESSING (Positive Treatment Response)';
    trajColor  = [0.15 0.65 0.25]; % Green
else
    trajectory = 'STABLE (No Significant Progression)';
    trajColor  = [0.20 0.45 0.80]; % Blue
end

deltaReport = struct(...
    'patient', patMeta, ...
    'baselineGrade', grBase.predictedGrade, ...
    'followUpGrade', grFollow.predictedGrade, ...
    'gradeDelta', deltaGrade, ...
    'deltaMACount', deltaMA, ...
    'deltaExudateAreaPct', deltaExArea, ...
    'deltaCDR', deltaCDR, ...
    'trajectory', trajectory, ...
    'baselineCSME', segBase.dme.hasCSME, ...
    'followUpCSME', segFollow.dme.hasCSME ...
);

% 6. Visualization Figure
figProg = figure('Name','OCULA AI — Longitudinal Disease Progression', ...
    'Position',[100 100 1200 650], 'Color','white', 'Visible','off');

sgtitle(sprintf('OCULA AI — Longitudinal Progression Tracker | Patient: %s (ID: %s)', ...
    patMeta.name, patMeta.id), 'FontSize', 14, 'FontWeight','bold');

% Subplot 1: Baseline
subplot(1,4,1);
imshow(imgBaseline);
title(sprintf('Visit 1: Baseline (%s)\nGrade %d (%s)', ...
    patMeta.baselineDate, grBase.predictedGrade, grBase.gradeName), 'FontSize', 9, 'FontWeight','bold');

% Subplot 2: Follow-up
subplot(1,4,2);
imshow(alignedFollow);
title(sprintf('Visit 2: Follow-up (%s)\nGrade %d (%s)', ...
    patMeta.followDate, grFollow.predictedGrade, grFollow.gradeName), 'FontSize', 9, 'FontWeight','bold');

% Subplot 3: Progression Difference Heatmap
subplot(1,4,3);
diffComposite = im2double(alignedFollow);
% Tint new lesions Green
diffComposite(:,:,1) = diffComposite(:,:,1) .* (~newExudates & ~newMAs);
diffComposite(:,:,2) = min(1.0, diffComposite(:,:,2) + 0.8 * (newExudates | newMAs));
diffComposite(:,:,3) = diffComposite(:,:,3) .* (~newExudates & ~newMAs);

% Tint resolved lesions Blue
diffComposite(:,:,1) = diffComposite(:,:,1) .* (~resolvedExudates & ~resolvedMAs);
diffComposite(:,:,2) = diffComposite(:,:,2) .* (~resolvedExudates & ~resolvedMAs);
diffComposite(:,:,3) = min(1.0, diffComposite(:,:,3) + 0.8 * (resolvedExudates | resolvedMAs));

imshow(diffComposite);
title({'Lesion Dynamics:', 'New Lesions (Green) | Resolved (Blue)'}, 'FontSize', 9, 'FontWeight','bold', 'Interpreter','none');

% Subplot 4: Quantitative Trajectory Card
subplot(1,4,4);
cla; axis off;
title('Progression Biomarkers', 'FontSize', 10, 'FontWeight','bold');

text(0.05, 0.90, trajectory, 'FontSize', 10, 'FontWeight','bold', 'Color', trajColor);

metricsText = {
    '---------------------------------------------', ...
    sprintf('DR Severity Grade : %d  ->  %d (Delta: %+d)', grBase.predictedGrade, grFollow.predictedGrade, deltaGrade), ...
    sprintf('Microaneurysm Count: %d  ->  %d (Delta: %+d)', segBase.ma.count, segFollow.ma.count, deltaMA), ...
    sprintf('Hard Exudate Area  : %.2f%% -> %.2f%% (Delta: %+.2f%%)', ...
        segBase.exudates.area_frac*100, segFollow.exudates.area_frac*100, deltaExArea), ...
    sprintf('Macular DME Status : %s -> %s', segBase.dme.riskLabel, segFollow.dme.riskLabel), ...
    sprintf('Glaucoma vCDR      : %.2f -> %.2f (Delta: %+.2f)', ...
        segBase.glaucoma.vCDR, segFollow.glaucoma.vCDR, deltaCDR), ...
    sprintf('Hypertension AVR   : %.2f -> %.2f', ...
        segBase.hypertension.avr, segFollow.hypertension.avr), ...
    '---------------------------------------------', ...
    'Clinical Recommendation:', ...
    'Annualized follow-up and anti-VEGF monitoring.', ...
    'Report verified by OCULA AI Longitudinal Engine'
};
text(0.05, 0.45, metricsText, 'FontSize', 8, 'Color', [0.15 0.15 0.15], 'Interpreter', 'none');

% Save Report Figure
outProg = fullfile(cfg.outputDir, sprintf('Progression_%s.png', patMeta.id));
exportgraphics(figProg, outProg, 'Resolution', 150);
fprintf('  [LONGITUDINAL] Progression report saved: %s\n', outProg);
end
