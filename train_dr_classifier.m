function train_dr_classifier(dataDir, cfg)
% TRAIN_DR_CLASSIFIER  Transfer-learning-based DR classifier training.
%
%  Uses InceptionV3 or ResNet18 backbone with DR-specific head.
%  Designed for IDRiD / EyePACS / APTOS 2019 / Messidor-2 datasets.
%
%  Usage:
%    cfg = dr_config();
%    train_dr_classifier('path/to/dataset', cfg);
%
%  Dataset structure expected:
%    dataDir/
%      Grade_0/  *.jpg
%      Grade_1/  *.jpg
%      Grade_2/  *.jpg
%      Grade_3/  *.jpg
%      Grade_4/  *.jpg
%
%  Output: models/dr_classifier.mat

if nargin < 2, cfg = dr_config(); end
if nargin < 1, dataDir = cfg.testImgDir; end

fprintf('=== DR Classifier Training ===\n');
fprintf('  Dataset: %s\n', dataDir);

%% Check toolbox availability
if ~license('test','Neural_Network_Toolbox')
    error('Deep Learning Toolbox required for training.');
end

%% Load dataset
imdsTrain = imageDatastore(dataDir, ...
    'IncludeSubfolders', true, ...
    'LabelSource', 'foldernames');
imdsTrain.Labels = recodecats(imdsTrain.Labels);

% Split train/validation
[imdsT, imdsV] = splitEachLabel(imdsTrain, 0.80, 'randomised');

fprintf('  Training images:   %d\n', numel(imdsT.Files));
fprintf('  Validation images: %d\n', numel(imdsV.Files));

%% Data augmentation pipeline (fundus-specific)
augT = imageDataAugmenter(...
    'RandRotation',      [-180 180], ...
    'RandXReflection',   true, ...
    'RandYReflection',   true, ...
    'RandScale',         [0.85 1.15], ...
    'RandXTranslation',  [-20 20], ...
    'RandYTranslation',  [-20 20]);

inputSz   = cfg.dl.inputSize;
augImdsT  = augmentedImageDatastore(inputSz, imdsT, ...
    'DataAugmentation', augT, 'ColorPreprocessing', 'gray2rgb');
augImdsV  = augmentedImageDatastore(inputSz, imdsV, ...
    'ColorPreprocessing', 'gray2rgb');

%% Load pre-trained backbone
fprintf('  Loading InceptionV3 backbone...\n');
try
    baseNet = inceptionv3;
    layerName = 'predictions';   % last layer to replace
catch
    try
        baseNet = resnet18;
        layerName = 'fc1000';
    catch
        error('Install inceptionv3 or resnet18 support package.');
    end
end

%% Replace classification head for DR (5 classes)
nClasses   = cfg.dl.numClasses;
lgraph     = layerGraph(baseNet);

% Remove old head, add DR-specific head
lgraph = removeLayers(lgraph, {layerName, [layerName '_softmax'], 'ClassificationLayer_predictions'});
newLayers = [
    fullyConnectedLayer(512, 'Name','fc_dr', 'WeightLearnRateFactor',10, 'BiasLearnRateFactor',10)
    batchNormalizationLayer('Name','bn_dr')
    reluLayer('Name','relu_dr')
    dropoutLayer(0.4, 'Name','drop_dr')
    fullyConnectedLayer(nClasses, 'Name','fc_out', 'WeightLearnRateFactor',10)
    softmaxLayer('Name','softmax_dr')
    classificationLayer('Name','cl_dr')
];
lgraph = addLayers(lgraph, newLayers);

% Connect to last shared layer
connLayer = 'avg_pool';   % adjust for your backbone
try
    lgraph = connectLayers(lgraph, connLayer, 'fc_dr');
catch
    lgraph = connectLayers(lgraph, 'pool5-drop_7x7_s1', 'fc_dr');
end

%% Compute class weights for imbalanced DR dataset
labelCounts = countEachLabel(imdsT);
classWeights = max(labelCounts.Count) ./ labelCounts.Count;
classWeights = classWeights / sum(classWeights) * nClasses;
fprintf('  Class weights: %s\n', mat2str(classWeights', 2));

%% Training options
opts = trainingOptions('adam', ...
    'MaxEpochs',            20, ...
    'MiniBatchSize',        cfg.dl.batchSize, ...
    'InitialLearnRate',     1e-4, ...
    'LearnRateSchedule',    'piecewise', ...
    'LearnRateDropFactor',  0.5, ...
    'LearnRateDropPeriod',  7, ...
    'L2Regularization',     1e-4, ...
    'ValidationData',       augImdsV, ...
    'ValidationFrequency',  50, ...
    'ValidationPatience',   5, ...
    'Shuffle',              'every-epoch', ...
    'Plots',                'training-progress', ...
    'Verbose',              true, ...
    'ExecutionEnvironment', 'auto', ...   % uses GPU if available, else CPU
    'OutputNetwork',        'best-validation-loss');

%% Train
fprintf('\n  Starting training...\n');
tic;
[net, info] = trainNetwork(augImdsT, lgraph, opts);
trainTime = toc;
fprintf('  Training complete in %.1f min.\n', trainTime/60);

%% Evaluate on validation set
fprintf('\n  Evaluating on validation set...\n');
predsV    = classify(net, augImdsV, 'ExecutionEnvironment','auto');
trueV     = imdsV.Labels;
acc       = sum(predsV == trueV) / numel(trueV);
fprintf('  Validation accuracy: %.1f%%\n', acc*100);

CM = confusionmat(trueV, predsV);
fprintf('  Confusion matrix:\n');
disp(CM);

%% Save model
modelPath = fullfile(cfg.modelDir, 'dr_classifier.mat');
save(modelPath, 'net', 'info', 'acc', 'CM', '-v7.3');
fprintf('  Model saved: %s\n', modelPath);

%% Save training curve figure
fig = figure('Visible','off');
plot(info.TrainingLoss,'b-'); hold on;
plot(info.ValidationLoss,'r--');
legend({'Training','Validation'});
xlabel('Iteration'); ylabel('Loss');
title('DR Classifier Training Curve');
grid on;
exportgraphics(fig, fullfile(cfg.outputDir,'training_curve.png'),'Resolution',150);
close(fig);
end

function cats = recodecats(labels)
% Map folder names (Grade_0..Grade_4) to categorical grade integers
cats = labels;
end
