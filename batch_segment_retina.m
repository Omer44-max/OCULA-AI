function segResults = batch_segment_retina(enhancedImgs, cfg)
% BATCH_SEGMENT_RETINA  Module 2 - Extract retinal structures & Multi-Disease Biomarkers
%
%  Structures extracted:
%    - Optic Disc (OD) & Eye Laterality (OD/OS)
%    - Optic Cup & Vertical Cup-to-Disc Ratio (vCDR) + ISNT rule (Glaucoma)
%    - Fovea localization (temporal mirroring)
%    - Blood Vessels & Calibre Ratio (AVR) (Hypertensive Retinopathy)
%    - Microaneurysms (MA) & Haemorrhages
%    - Hard Exudates & DME/CSME Risk Scoring
%    - Macular Drusen profiling (Age-Related Macular Degeneration - AMD)
%    - Neovascularization (NVD / NVE)

n          = numel(enhancedImgs);
segResults = repmat(struct(...
    'odCenter',  [NaN NaN], ...
    'odRadius',  NaN, ...
    'foveaCenter',[NaN NaN], ...
    'eyeLaterality', 'OD', ...
    'eyeLateralityLong', 'Right Eye (OD)', ...
    'vessels',   [], ...
    'ma',        struct('mask',[],'count',0,'area_px2',0), ...
    'exudates',  struct('mask',[],'area_frac',0), ...
    'haem',      struct('mask',[],'count',0), ...
    'neovasc',   struct('detected',false,'density',0), ...
    'dme',       struct('riskGrade',0,'riskLabel','No DME Risk','hasCSME',false,'foveaDistPx',NaN), ...
    'glaucoma',  struct('cupCenter',[NaN NaN],'cupRadius',NaN,'vCDR',0.35,'hCDR',0.35,'isSuspect',false,'isntViolated',false,'status','Normal CDR'), ...
    'amd',       struct('drusenMask',[],'drusenCount',0,'drusenAreaFrac',0,'amdStage',0,'isSuspect',false,'status','No AMD (Clear)'), ...
    'hypertension', struct('avr',0.68,'isNarrowed',false,'grade',0,'status','Normal Calibre (AVR Normal)') ...
    ), n, 1);

for i = 1:n
    img           = enhancedImgs{i};
    segResults(i) = segment_one_image(img, cfg);

    if cfg.verbosity >= 1
        fprintf('  [SEG %d/%d] Eye=%s | vCDR=%.2f (%s) | Drusen=%d | AVR=%.2f | DME=%s\n',...
            i, n, segResults(i).eyeLaterality, ...
            segResults(i).glaucoma.vCDR, segResults(i).glaucoma.status, ...
            segResults(i).amd.drusenCount, segResults(i).hypertension.avr, ...
            segResults(i).dme.riskLabel);
    end
end
end

% =========================================================================
function seg = segment_one_image(img, cfg)
% Full segmentation pipeline for a single fundus image

gray  = rgb2gray(img);
gD    = im2double(gray);
imgD  = im2double(img);

%% --- Optic Disc Localisation ---
green = imgD(:,:,2);
red   = imgD(:,:,1);
blue  = imgD(:,:,3);

% OD candidate: brightest region
brightMap  = (red + green) / 2;
brightMap  = imgaussfilt(brightMap, 5);
thresh_od  = prctile(brightMap(:), cfg.od.brightnessPerc);
odSeed     = brightMap > thresh_od;
odSeed     = imfill(odSeed, 'holes');
odSeed     = bwareafilt(odSeed, 1);
odProps    = regionprops(odSeed, 'Centroid','EquivDiameter');

if ~isempty(odProps)
    seg.odCenter = odProps(1).Centroid;          % [col, row]
    seg.odRadius = max(25, odProps(1).EquivDiameter / 2);
else
    sz             = size(gray);
    seg.odCenter   = [sz(2)*0.7, sz(1)*0.5];    % default right side
    seg.odRadius   = 50;
end

%% --- Eye Laterality Detection (OD = Right Eye, OS = Left Eye) ---
imgCenterCol = size(gray, 2) / 2;
if seg.odCenter(1) >= imgCenterCol
    seg.eyeLaterality = 'OD';
    seg.eyeLateralityLong = 'Right Eye (OD)';
    isRightEye = true;
else
    seg.eyeLaterality = 'OS';
    seg.eyeLateralityLong = 'Left Eye (OS)';
    isRightEye = false;
end

%% --- Fovea Localisation ---
foveaSearchRadius = round(2.5 * seg.odRadius);
cx = round(seg.odCenter(1)); cy = round(seg.odCenter(2));
sz = size(gray);

if isRightEye
    % OD: Disc is right -> Fovea is to the left (temporal)
    x1 = max(1, cx - 3*foveaSearchRadius);
    x2 = max(1, cx - round(0.5*seg.odRadius));
else
    % OS: Disc is left -> Fovea is to the right (temporal)
    x1 = min(sz(2), cx + round(0.5*seg.odRadius));
    x2 = min(sz(2), cx + 3*foveaSearchRadius);
end
y1 = max(1, cy - foveaSearchRadius);
y2 = min(sz(1), cy + foveaSearchRadius);

if x1 < x2 && y1 < y2
    searchPatch = gD(y1:y2, x1:x2);
    smoothPatch = imgaussfilt(searchPatch, 8);
    [~, idx]    = min(smoothPatch(:));
    [fy, fx]    = ind2sub(size(smoothPatch), idx);
    seg.foveaCenter = [x1+fx-1, y1+fy-1];
else
    if isRightEye
        seg.foveaCenter = [cx - round(2.5*seg.odRadius), cy];
    else
        seg.foveaCenter = [cx + round(2.5*seg.odRadius), cy];
    end
end

%% --- Glaucoma Screening: Optic Cup & Vertical CDR ---
% Within the localized Optic Disc, segment the pale physiological cup
[X_grid, Y_grid] = meshgrid(1:sz(2), 1:sz(1));
distOD = sqrt((X_grid - cx).^2 + (Y_grid - cy).^2);
odMask = distOD <= seg.odRadius;

% The cup is the brightest pallor core inside the disc
odLuminance = gD;
odLuminance(~odMask) = 0;
cupThresh = prctile(odLuminance(odMask), 75); % top quartile inside OD
cupCandidate = (odLuminance > cupThresh) & odMask;
cupCandidate = imfill(bwareafilt(cupCandidate, 1), 'holes');
cupProps = regionprops(cupCandidate, 'Centroid','MajorAxisLength','MinorAxisLength','BoundingBox');

if ~isempty(cupProps)
    seg.glaucoma.cupCenter = cupProps(1).Centroid;
    vCupDiam = cupProps(1).MajorAxisLength;
    hCupDiam = cupProps(1).MinorAxisLength;
    seg.glaucoma.cupRadius = vCupDiam / 2;
else
    seg.glaucoma.cupCenter = seg.odCenter;
    vCupDiam = seg.odRadius * 0.70;
    hCupDiam = seg.odRadius * 0.65;
    seg.glaucoma.cupRadius = vCupDiam / 2;
end

discDiam = max(20, seg.odRadius * 2);
seg.glaucoma.vCDR = min(0.98, max(0.15, vCupDiam / discDiam));
seg.glaucoma.hCDR = min(0.98, max(0.15, hCupDiam / discDiam));

% Neuroretinal Rim & ISNT Rule Check (Inferior >= Superior >= Nasal >= Temporal)
% Measure distance from cup boundary to disc boundary
cupCY = seg.glaucoma.cupCenter(2);
discCY = seg.odCenter(2);
rimInferior = max(2, (discCY + seg.odRadius) - (cupCY + seg.glaucoma.cupRadius));
rimSuperior = max(2, (cupCY - seg.glaucoma.cupRadius) - (discCY - seg.odRadius));
seg.glaucoma.isntViolated = (rimInferior < rimSuperior * 0.85);

if seg.glaucoma.vCDR >= cfg.glaucoma.cdrSuspectThresh || (seg.glaucoma.vCDR >= 0.55 && seg.glaucoma.isntViolated)
    seg.glaucoma.isSuspect = true;
    seg.glaucoma.status = sprintf('Glaucoma Suspect (vCDR=%.2f)', seg.glaucoma.vCDR);
elseif seg.glaucoma.vCDR >= cfg.glaucoma.cdrBorderlineThresh
    seg.glaucoma.isSuspect = false;
    seg.glaucoma.status = sprintf('Borderline CDR (vCDR=%.2f)', seg.glaucoma.vCDR);
else
    seg.glaucoma.isSuspect = false;
    seg.glaucoma.status = sprintf('Normal Cup-to-Disc (vCDR=%.2f)', seg.glaucoma.vCDR);
end

%% --- Blood Vessel Segmentation (Frangi Multi-scale) ---
greenGray        = imgD(:,:,2);
greenGray        = imadjust(greenGray);
seg.vessels      = frangi_filter(greenGray, cfg.vessel);

%% --- Hypertensive Retinopathy: Arteriolar-to-Venular Ratio (AVR) ---
% Sample vessels in peripapillary region: 1.2 to 2.5 OD radii
periRing = (distOD >= 1.2 * seg.odRadius) & (distOD <= 2.5 * seg.odRadius);
vesselsInRing = (seg.vessels > cfg.vessel.threshold) & periRing;

if any(vesselsInRing(:))
    % Arterioles have higher red-to-green ratio and brighter central reflex
    rgRatio = red ./ (green + eps);
    vesselRG = rgRatio(vesselsInRing);
    medianRG = median(vesselRG);
    
    arteriolePixels = vesselsInRing & (rgRatio >= medianRG);
    venulePixels    = vesselsInRing & (rgRatio < medianRG);
    
    arterioleCalibre = sum(arteriolePixels(:));
    venuleCalibre    = sum(venulePixels(:));
    rawAVR = arterioleCalibre / (venuleCalibre + eps);
    % Map to standard physiological clinical AVR range [0.45 - 0.78]
    avrCalibrated = min(0.78, max(0.46, 0.50 + 0.20 * rawAVR));
else
    avrCalibrated = 0.68; % normal default
end

seg.hypertension.avr = round(avrCalibrated, 2);
if seg.hypertension.avr < 0.58
    seg.hypertension.isNarrowed = true;
    seg.hypertension.grade = 2;
    seg.hypertension.status = sprintf('Arteriolar Narrowing (AVR=%.2f - HTN Risk)', seg.hypertension.avr);
elseif seg.hypertension.avr < 0.65
    seg.hypertension.isNarrowed = true;
    seg.hypertension.grade = 1;
    seg.hypertension.status = sprintf('Borderline Narrowing (AVR=%.2f)', seg.hypertension.avr);
else
    seg.hypertension.isNarrowed = false;
    seg.hypertension.grade = 0;
    seg.hypertension.status = sprintf('Normal Calibre (AVR=%.2f)', seg.hypertension.avr);
end

%% --- Microaneurysm Detection ---
greenCh  = imgD(:,:,2);
se_disk  = strel('disk', 3);
tophatG  = imtophat(1 - greenCh, se_disk);
threshMA = prctile(tophatG(:), 99.2);
maSeed   = tophatG > threshMA;
maSeed   = maSeed & ~odMask & ~(seg.vessels > cfg.vessel.threshold);

maStats = regionprops(maSeed, 'Area','Eccentricity');
maClean = false(size(maSeed));
cc_ma   = bwconncomp(maSeed);
for k = 1:numel(maStats)
    if maStats(k).Area >= cfg.ma.minArea && ...
       maStats(k).Area <= cfg.ma.maxArea && ...
       maStats(k).Eccentricity < cfg.ma.eccentricity
        maClean(cc_ma.PixelIdxList{k}) = true;
    end
end
seg.ma.mask     = maClean;
seg.ma.count    = numel(regionprops(maClean, 'Area'));
seg.ma.area_px2 = sum(maClean(:));

%% --- Hard Exudate Detection ---
brightLesions = greenCh > cfg.exudate.brightThresh;
brightLesions = brightLesions & ~odMask;
brightLesions = bwareaopen(brightLesions, cfg.exudate.minArea);
seg.exudates.mask      = brightLesions;
seg.exudates.area_frac = sum(brightLesions(:)) / numel(brightLesions);

%% --- AMD Screening: Macular Drusen Profiling ---
% Macular zone within 1.5 OD radii of foveal center
fx = seg.foveaCenter(1); fy = seg.foveaCenter(2);
distFovea = sqrt((X_grid - fx).^2 + (Y_grid - fy).^2);
maculaMask = distFovea <= (1.5 * seg.odRadius);

% Drusen: soft yellowish lesions on red/green channels outside OD and vessels
drusenScore = (red + green)/2 - blue;
drusenScore(~maculaMask) = 0;
drusenCand = (drusenScore > 0.18) & maculaMask & ~(seg.vessels > cfg.vessel.threshold) & ~seg.exudates.mask;
drusenCand = bwareaopen(drusenCand, cfg.amd.minDrusenArea);
drusenProps = regionprops(drusenCand, 'Area');

drusenCount = numel(drusenProps);
drusenAreaTotal = sum([drusenProps.Area]);
maculaArea = max(1, sum(maculaMask(:)));
drusenAreaFrac = drusenAreaTotal / maculaArea;

seg.amd.drusenMask     = drusenCand;
seg.amd.drusenCount    = drusenCount;
seg.amd.drusenAreaFrac = drusenAreaFrac;

if drusenAreaFrac >= cfg.amd.intermDrusenAreaThresh
    seg.amd.amdStage  = 2;
    seg.amd.isSuspect = true;
    seg.amd.status    = sprintf('Intermediate/Late AMD (Drusen Area=%.1f%%)', drusenAreaFrac*100);
elseif drusenCount >= cfg.amd.earlyDrusenCountThresh
    seg.amd.amdStage  = 1;
    seg.amd.isSuspect = false;
    seg.amd.status    = sprintf('Early Dry AMD (%d Drusen)', drusenCount);
else
    seg.amd.amdStage  = 0;
    seg.amd.isSuspect = false;
    seg.amd.status    = 'No AMD (Macula Clear)';
end

%% --- Haemorrhage Detection ---
retinaMask = gD > 0.05;
darkMap = (greenCh < cfg.haem.darkThresh) ...
        & (gD > 0.03) ...
        & retinaMask ...
        & ~(seg.vessels > cfg.vessel.threshold) ...
        & ~odMask;

darkMap = bwareaopen(darkMap, 35);
darkMap = darkMap & ~imdilate(seg.ma.mask, strel('disk', 4));

hemStats = regionprops(darkMap, 'Area','Eccentricity','Solidity');
hemClean = false(size(darkMap));
cc_hem   = bwconncomp(darkMap);
for k = 1:numel(hemStats)
    if hemStats(k).Area >= 35  && ...
       hemStats(k).Eccentricity < 0.90 && ...
       hemStats(k).Solidity > 0.60  && ...
       k <= cc_hem.NumObjects
        hemClean(cc_hem.PixelIdxList{k}) = true;
    end
end
seg.haem.mask  = hemClean;
seg.haem.count = numel(regionprops(hemClean, 'Area'));

%% --- Neovascularization Detection ---
vesselBin    = seg.vessels > cfg.vessel.threshold;
sz2          = size(vesselBin);
[rr2,cc2_g]  = meshgrid(1:sz2(2), 1:sz2(1));
nearOD       = (rr2-seg.odCenter(1)).^2 + (cc2_g-seg.odCenter(2)).^2 < (seg.odRadius*2)^2;
nvdDensity   = sum(vesselBin(nearOD)) / sum(nearOD(:));
overallDensity       = sum(vesselBin(:)) / numel(vesselBin);
seg.neovasc.density  = nvdDensity;
seg.neovasc.detected = nvdDensity > 0.25 || overallDensity > 0.18;

%% --- Diabetic Macular Edema (DME / CSME) Risk Assessment ---
[rows_ex, cols_ex] = find(seg.exudates.mask);
if ~isempty(rows_ex)
    distExToFovea = sqrt((cols_ex - fx).^2 + (rows_ex - fy).^2);
    minDistPx = min(distExToFovea);
    distInDD = minDistPx / discDiam;
    seg.dme.foveaDistPx = minDistPx;

    if distInDD <= cfg.dme.csmeDistanceDD
        seg.dme.riskGrade = 2;
        seg.dme.riskLabel = 'High Risk (CSME)';
        seg.dme.hasCSME   = true;
    elseif distInDD <= cfg.dme.modDistanceDD
        seg.dme.riskGrade = 1;
        seg.dme.riskLabel = 'Moderate DME Risk';
        seg.dme.hasCSME   = false;
    else
        seg.dme.riskGrade = 0;
        seg.dme.riskLabel = 'Low / Peripheral Only';
        seg.dme.hasCSME   = false;
    end
else
    seg.dme.riskGrade = 0;
    seg.dme.riskLabel = 'No DME Risk (Clear)';
    seg.dme.hasCSME   = false;
    seg.dme.foveaDistPx = NaN;
end
end

% =========================================================================
function V = frangi_filter(I, params)
% FRANGI_FILTER Multi-scale Hessian vesselness filter
V     = zeros(size(I));
beta1 = params.beta1;
beta2 = params.beta2;

for sigma = params.sigmas
    Ixx = imgaussfilt(I, sigma, 'FilterDomain','frequency');
    Ixx = imfilter(Ixx, fspecial('laplacian'));
    h   = sigma^2;
    Hxx = imfilter(imgaussfilt(I,sigma), [1 -2 1] * h);
    Hyy = imfilter(imgaussfilt(I,sigma), [1 -2 1]' * h);
    Hxy = imfilter(imgaussfilt(I,sigma), [1 0 -1; 0 0 0; -1 0 1] * h/4);

    tmp       = sqrt((Hxx - Hyy).^2 + 4*Hxy.^2);
    lambda1   = (Hxx + Hyy + tmp) / 2;
    lambda2   = (Hxx + Hyy - tmp) / 2;

    swap      = abs(lambda1) > abs(lambda2);
    [l1, l2]  = deal(lambda1, lambda2);
    l1(swap)  = lambda2(swap);
    l2(swap)  = lambda1(swap);

    RB   = l1 ./ (l2 + eps);
    S2   = l1.^2 + l2.^2;
    Vscale = exp(-RB.^2 / (2*beta1^2)) .* (1 - exp(-S2 / (2*beta2^2)));
    Vscale(l2 >= 0) = 0;
    V = max(V, Vscale);
end
V = V / (max(V(:)) + eps);
end
