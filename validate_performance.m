function validate_performance(gradeResults, labelList, cfg)
% VALIDATE_PERFORMANCE  Module 5 - Clinical validation metrics
%
%  Computes:
%    - Confusion matrix (5-class)
%    - Sensitivity & Specificity for referable DR (Grade >= 2)
%    - AUC-ROC for referable vs non-referable
%    - Kappa coefficient
%    - Comparison against published benchmarks

fprintf('\n--- Clinical Validation Results ---\n');

n        = numel(gradeResults);
validIdx = find(~isnan(labelList) & (1:n)' <= n);

if isempty(validIdx)
    fprintf('  No valid ground-truth labels. Skipping validation.\n');
    return;
end

trueGrades = labelList(validIdx);
predGrades = [gradeResults(validIdx).predictedGrade]';
predConf   = [gradeResults(validIdx).confScore]';

%% --- 5-class confusion matrix (no Stats Toolbox needed) ---
CM = manual_confmat(trueGrades, predGrades, 0:4);
fprintf('\n  5-class Confusion Matrix (rows=true, cols=pred):\n');
fprintf('         G0   G1   G2   G3   G4\n');
rowLabels = {'G0:','G1:','G2:','G3:','G4:'};
for r = 1:5
    fprintf('  %s   %3d  %3d  %3d  %3d  %3d\n', ...
        rowLabels{r}, CM(r,1), CM(r,2), CM(r,3), CM(r,4), CM(r,5));
end

%% --- Binary: Referable (G2+) vs Non-referable ---
trueRef  = trueGrades >= cfg.dl.referableThresh;
predRef  = predGrades >= cfg.dl.referableThresh;

TP = sum( trueRef &  predRef);
TN = sum(~trueRef & ~predRef);
FP = sum(~trueRef &  predRef);
FN = sum( trueRef & ~predRef);

sensitivity = TP / (TP + FN + eps);
specificity = TN / (TN + FP + eps);
ppv         = TP / (TP + FP + eps);
npv         = TN / (TN + FN + eps);
accuracy    = (TP + TN) / n;
f1          = 2*TP / (2*TP + FP + FN + eps);

fprintf('\n  --- Binary: Referable DR (Grade >= 2) ---\n');
fprintf('  Sensitivity (Recall): %.1f%%  [Target: >%.0f%%]', ...
    sensitivity*100, cfg.clinSensitivity*100);
if sensitivity >= cfg.clinSensitivity, fprintf(' ✓\n'); else, fprintf(' ✗\n'); end

fprintf('  Specificity:          %.1f%%  [Target: >%.0f%%]', ...
    specificity*100, cfg.clinSpecificity*100);
if specificity >= cfg.clinSpecificity, fprintf(' ✓\n'); else, fprintf(' ✗\n'); end

fprintf('  PPV (Precision):      %.1f%%\n', ppv*100);
fprintf('  NPV:                  %.1f%%\n', npv*100);
fprintf('  Accuracy:             %.1f%%\n', accuracy*100);
fprintf('  F1 Score:             %.3f\n',   f1);

%% --- AUC-ROC (if enough positive cases) ---
predScores = arrayfun(@(x) x.confidence(cfg.dl.referableThresh+1:end), ...
    gradeResults(validIdx), 'UniformOutput', false);
scoreVec   = cellfun(@sum, predScores);  % P(referable) = sum of P(G2)+P(G3)+P(G4)

try
    [X,Y,~,AUC] = perfcurve(double(trueRef), scoreVec, 1);
    fprintf('  AUC-ROC:              %.3f\n', AUC);
catch
    fprintf('  AUC-ROC:              N/A (requires Stats Toolbox)\n');
    X = []; Y = []; AUC = NaN;
end

%% --- Cohen's Kappa ---
kappa = compute_kappa(CM);
fprintf('  Cohen''s Kappa (5-class): %.3f', kappa);
if kappa > 0.7, fprintf(' (Substantial)\n');
elseif kappa > 0.6, fprintf(' (Moderate)\n');
else, fprintf(' (Fair)\n'); end

%% --- Per-grade Sensitivity ---
fprintf('\n  Per-grade sensitivity:\n');
for g = 0:4
    trueG = trueGrades == g;
    predG = predGrades == g;
    if sum(trueG) > 0
        sG = sum(trueG & predG) / sum(trueG);
        fprintf('    Grade %d: %.1f%%  (n=%d)\n', g, sG*100, sum(trueG));
    end
end

%% --- Benchmark Comparison ---
fprintf('\n  --- Published Benchmark Comparison ---\n');
benchmarks = {
    'IDRiD Dataset (Porwal 2020)',  0.938, 0.872;
    'EyePACS (Gulshan 2016)',       0.970, 0.870;
    'Messidor-2 (Abramoff 2016)',   0.960, 0.870;
    'This System',                  sensitivity, specificity;
};
fprintf('  %-35s  Sens     Spec\n', 'System');
fprintf('  %s\n', repmat('-',1,60));
for r = 1:size(benchmarks,1)
    if r == size(benchmarks,1)
        fprintf('  %-35s  %.1f%%   %.1f%%  <<\n', ...
            benchmarks{r,1}, benchmarks{r,2}*100, benchmarks{r,3}*100);
    else
        fprintf('  %-35s  %.1f%%   %.1f%%\n', ...
            benchmarks{r,1}, benchmarks{r,2}*100, benchmarks{r,3}*100);
    end
end

%% --- Visualise Confusion Matrix + ROC ---
fig = figure('Visible','off','Position',[100 100 1000 450],'Color','w');

subplot(1,2,1);
cM_norm = CM ./ (sum(CM,2) + eps);
imagesc(cM_norm); colormap(gca, flipud(autumn));
cb = colorbar; cb.Label.String = 'Fraction';
set(gca,'XTick',1:5,'YTick',1:5,...
    'XTickLabel',{'G0','G1','G2','G3','G4'},...
    'YTickLabel',{'G0','G1','G2','G3','G4'});
xlabel('Predicted Grade'); ylabel('True Grade');
title('Normalised Confusion Matrix','FontWeight','bold');
for r=1:5
    for c=1:5
        text(c,r,sprintf('%.2f',cM_norm(r,c)),...
            'HorizontalAlignment','center','Color','k','FontSize',9);
    end
end

subplot(1,2,2);
if ~isempty(X)
    plot(X, Y, 'b-', 'LineWidth', 2.5);
    hold on;
    plot([0 1],[0 1],'k--');
    xlabel('False Positive Rate'); ylabel('True Positive Rate');
    title(sprintf('ROC Curve - AUC = %.3f', AUC), 'FontWeight','bold');
    legend({sprintf('Referable DR (AUC=%.3f)',AUC),'Random'}, 'Location','southeast');
    grid on;
else
    text(0.5,0.5,'ROC N/A','HorizontalAlignment','center');
    axis([0 1 0 1]);
end

sgtitle('Clinical Validation - DR Screening System', 'FontWeight','bold','FontSize',13);

outFile = fullfile(cfg.outputDir, 'validation_metrics.png');
exportgraphics(fig, outFile, 'Resolution', 150);
fprintf('\n  Validation figure saved: %s\n', outFile);
close(fig);
end

% =========================================================================
function k = compute_kappa(CM)
n      = sum(CM(:));
po     = trace(CM) / n;
rowSum = sum(CM, 2);
colSum = sum(CM, 1);
pe     = sum(rowSum .* colSum') / n^2;
k      = (po - pe) / (1 - pe + eps);
end

% =========================================================================
function CM = manual_confmat(trueLabels, predLabels, order)
% Manual confusion matrix — no Stats/ML Toolbox needed
nC = numel(order);
CM = zeros(nC, nC);
for i = 1:numel(trueLabels)
    r = find(order == trueLabels(i), 1);
    c = find(order == predLabels(i), 1);
    if ~isempty(r) && ~isempty(c)
        CM(r, c) = CM(r, c) + 1;
    end
end
end

% =========================================================================
function [X, Y, AUC] = manual_roc(scores, labels)
% Manual ROC curve — no Stats/ML Toolbox needed
thresholds = unique(scores);
thresholds = sort(thresholds, 'descend');
X = zeros(numel(thresholds)+1, 1);   % FPR
Y = zeros(numel(thresholds)+1, 1);   % TPR
P = sum(labels == 1);
N = sum(labels == 0);
for k = 1:numel(thresholds)
    pred    = scores >= thresholds(k);
    X(k+1)  = sum(pred & ~labels) / (N + eps);
    Y(k+1)  = sum(pred &  labels) / (P + eps);
end
X(1) = 0; Y(1) = 0;
X(end+1) = 1; Y(end+1) = 1;   %#ok<AGROW>
AUC = abs(trapz(X, Y));
end
