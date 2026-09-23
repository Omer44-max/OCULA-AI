function [enhancedImgs, qcResults] = batch_quality_pipeline(imgList, cfg)
% BATCH_QUALITY_PIPELINE  Quality assess and enhance all images

n             = numel(imgList);
enhancedImgs  = cell(n, 1);
qcResults     = struct('status',cell(n,1), 'sharpness',0, 'brightness',0, ...
                       'fovCoverage',0, 'overallScore',0);

for i = 1:n
    [enhancedImgs{i}, qcResults(i)] = assess_and_enhance(imgList{i}, cfg);
    if cfg.verbosity >= 1
        fprintf('  [QC %d/%d] %s | Sharp=%.3f Bright=%.1f Score=%.2f\n', ...
            i, n, qcResults(i).status, qcResults(i).sharpness, ...
            qcResults(i).brightness, qcResults(i).overallScore);
    end
end
end

% ─────────────────────────────────────────────────────────────────────────
function [enhImg, qc] = assess_and_enhance(img, cfg)
% Full IQA + enhancement pipeline for one image

    % ── Convert to uint8 RGB ──────────────────────────────────────────
    if isinteger(img), img = im2single(img); end
    if size(img,3)==1,  img = repmat(img,[1 1 3]); end
    img = im2uint8(img);
    
    % ── Resize ────────────────────────────────────────────────────────
    img = imresize(img, cfg.targetSize);
    
    % ── Quality Metrics ───────────────────────────────────────────────
    gray         = rgb2gray(img);
    grayD        = double(gray);
    
    % Sharpness: normalised Laplacian variance
    lap          = imfilter(grayD, fspecial('laplacian'));
    sharpness    = var(lap(:)) / (255^2);
    
    % Brightness
    brightness   = mean(grayD(:));
    
    % Field of View: fraction of pixels with intensity > threshold
    fovMask      = grayD > 20;
    fovCoverage  = sum(fovMask(:)) / numel(fovMask);
    
    % Overall quality score (0-1)
    s1 = min(1, sharpness / cfg.minSharpness);
    s2 = min(1, brightness / cfg.minBrightness);
    s3 = min(1, fovCoverage / cfg.minFOV);
    overallScore = (s1 + s2 + s3) / 3;
    
    % ── Status Decision ───────────────────────────────────────────────
    if overallScore < 0.40
        status = 'REJECTED';
    elseif overallScore < 0.70
        status = 'BORDERLINE';
    else
        status = 'ACCEPTED';
    end
    
    % ── Enhancement (for BORDERLINE or ACCEPTED) ──────────────────────
    if strcmp(status, 'REJECTED')
        enhImg = img;   % still pass original for pipeline continuity
    else
        enhImg = enhance_fundus(img, cfg);
    end
    
    % ── Pack QC struct ─────────────────────────────────────────────────
    qc.status       = status;
    qc.sharpness    = sharpness;
    qc.brightness   = brightness;
    qc.fovCoverage  = fovCoverage;
    qc.overallScore = overallScore;
end

% ─────────────────────────────────────────────────────────────────────────
function enhanced = enhance_fundus(img, cfg)
% Apply retinal-specific enhancement chain

    % Step 1: Convert to LAB, enhance L channel
    lab    = rgb2lab(img);
    L      = lab(:,:,1) / 100;   % normalise to [0,1]
    
    % Step 2: CLAHE on luminance
    Lenh   = adapthisteq(L, ...
                'NumTiles',  cfg.clahe.NumTiles, ...
                'ClipLimit', cfg.clahe.ClipLimit, ...
                'NBins',     cfg.clahe.NBins);
    
    % Step 3: Illumination correction via morphological background
    se      = strel('disk', 45);
    bgEst   = imopen(Lenh, se);
    Lcorr   = Lenh - bgEst + mean(Lenh(:));
    Lcorr   = imadjust(Lcorr);
    
    % Step 4: Gaussian denoising
    Lcorr   = imgaussfilt(Lcorr, 0.7);
    
    % Rebuild LAB and convert back
    lab(:,:,1) = Lcorr * 100;
    enhanced   = im2uint8(lab2rgb(lab));
    
    % Step 5: Unsharp masking for vessel edge crispness
    enhanced = imsharpen(enhanced, 'Radius', 1.5, 'Amount', 0.4);
end
