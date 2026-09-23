function [imgList, labelList] = load_fundus_dataset(cfg)
% LOAD_FUNDUS_DATASET  Load fundus images from test_images directory
%   Supports: jpg, jpeg, png, tif, bmp
%   Labels parsed from filename pattern: imgNNN_gradeX.jpg

imgDir = cfg.testImgDir;
exts   = {'*.jpg','*.jpeg','*.png','*.tif','*.bmp'};
files  = [];
for e = 1:numel(exts)
    files = [files; dir(fullfile(imgDir, exts{e}))];
end

if isempty(files)
    warning('No images found in %s. Creating synthetic demo images.', imgDir);
    imgList   = create_synthetic_demo(cfg);
    labelList = [];
    return;
end

imgList   = cell(numel(files), 1);
labelList = zeros(numel(files), 1);

for i = 1:numel(files)
    fpath       = fullfile(files(i).folder, files(i).name);
    img         = imread(fpath);
    imgList{i}  = img;
    
    % Parse grade from filename e.g. "patient001_grade2.jpg"
    tok = regexp(files(i).name, 'grade(\d)', 'tokens');
    if ~isempty(tok)
        labelList(i) = str2double(tok{1}{1});
    else
        labelList(i) = NaN;
    end
    
    if cfg.verbosity >= 2
        fprintf('  Loaded: %s\n', files(i).name);
    end
end

fprintf('  Loaded %d image(s) from dataset.\n', numel(imgList));
end

% ─────────────────────────────────────────────────────────────────────────
function imgList = create_synthetic_demo(cfg)
% Generates 5 synthetic fundus-like images (one per DR grade) for demo
    nGrades = 5;
    imgList = cell(nGrades, 1);
    sz      = cfg.targetSize;
    
    for g = 1:nGrades
        grade = g - 1;  % 0-4
        img   = synthesize_fundus(sz, grade);
        fname = fullfile(cfg.testImgDir, sprintf('synthetic_grade%d.png', grade));
        imwrite(img, fname);
        imgList{g} = img;
        fprintf('  Created synthetic Grade-%d image: %s\n', grade, fname);
    end
end

function img = synthesize_fundus(sz, grade)
% Simulate a fundus image with grade-appropriate lesions
    [X,Y] = meshgrid(linspace(-1,1,sz(2)), linspace(-1,1,sz(1)));
    R     = sqrt(X.^2 + Y.^2);
    
    % Retinal background - reddish gradient
    bg_r  = uint8(180 .* (R < 0.95) .* max(0, 1-0.3*R));
    bg_g  = uint8(80  .* (R < 0.95) .* max(0, 1-0.4*R));
    bg_b  = uint8(40  .* (R < 0.95) .* max(0, 1-0.5*R));
    
    img   = cat(3, bg_r, bg_g, bg_b);
    img   = imnoise(img, 'gaussian', 0, 0.002);
    
    % Optic disc (bright circle)
    od_mask = ((X-0.3).^2 + Y.^2) < 0.04^2*25;
    img(:,:,1) = img(:,:,1) + uint8(220 * od_mask);
    img(:,:,2) = img(:,:,2) + uint8(200 * od_mask);
    img(:,:,3) = img(:,:,3) + uint8(150 * od_mask);
    
    % Add vessels (dark lines)
    vessel = uint8(30 * (abs(X - 0.05*sin(5*Y)) < 0.01));
    img(:,:,1) = img(:,:,1) - min(img(:,:,1), vessel);
    img(:,:,2) = img(:,:,2) - min(img(:,:,2), vessel);
    
    % Add lesions based on grade
    rng(grade + 42);
    switch grade
        case 0  % No DR
            % no lesions
        case 1  % Mild NPDR - few MA
            img = add_microaneurysms(img, 3, X, Y);
        case 2  % Moderate NPDR
            img = add_microaneurysms(img, 10, X, Y);
            img = add_exudates(img, 5, X, Y);
        case 3  % Severe NPDR
            img = add_microaneurysms(img, 25, X, Y);
            img = add_exudates(img, 15, X, Y);
            img = add_haemorrhages(img, 8, X, Y);
        case 4  % Proliferative DR
            img = add_microaneurysms(img, 40, X, Y);
            img = add_exudates(img, 25, X, Y);
            img = add_haemorrhages(img, 20, X, Y);
            img = add_neovascularization(img, X, Y);
    end
    img = im2uint8(img);
end

function img = add_microaneurysms(img, n, X, Y)
% MAs: small dark-red dots — detectable by green-channel bottom-hat filter
% Placed only inside the retinal disc (R < 0.75), avoid OD area
    for i = 1:n
        % Random position inside retinal disc, away from OD (near X=0.3)
        while true
            cx = rand*1.2 - 0.6;
            cy = rand*1.2 - 0.6;
            if sqrt(cx^2+cy^2) < 0.72 && ~((cx-0.3)^2+cy^2 < 0.08)
                break;
            end
        end
        r    = 0.012 + rand*0.010;   % radius 0.012-0.022 (6-11px at 512px)
        mask = (X-cx).^2 + (Y-cy).^2 < r^2;
        % Darken green & blue strongly → dark-red dot (detectable by tophat)
        img(:,:,1) = img(:,:,1) + uint8(30  * double(mask));  % slight red
        img(:,:,2) = img(:,:,2) - min(img(:,:,2), uint8(60 * double(mask)));
        img(:,:,3) = img(:,:,3) - min(img(:,:,3), uint8(50 * double(mask)));
    end
end

function img = add_exudates(img, n, X, Y)
% Exudates: bright yellow-white patches inside retinal disc
    for i = 1:n
        cx = rand*1.0 - 0.5;
        cy = rand*1.0 - 0.5;
        if sqrt(cx^2+cy^2) > 0.70, continue; end
        r    = 0.025 + rand*0.045;
        mask = (X-cx).^2 + (Y-cy).^2 < r^2;
        img(:,:,1) = img(:,:,1) + uint8(200 * double(mask));
        img(:,:,2) = img(:,:,2) + uint8(200 * double(mask));
        img(:,:,3) = img(:,:,3) + uint8(100 * double(mask));
    end
end

function img = add_haemorrhages(img, n, X, Y)
% Haemorrhages: dark-red solid blobs, INSIDE retina only (R<0.70)
% Red channel raised, green+blue strongly lowered → dark-red appearance
    for i = 1:n
        while true
            cx = rand*1.0 - 0.5;
            cy = rand*1.0 - 0.5;
            if sqrt(cx^2+cy^2) < 0.65, break; end
        end
        r    = 0.020 + rand*0.030;   % 10-22px radius → detectable blob
        mask = double((X-cx).^2 + (Y-cy).^2 < r^2);
        img(:,:,1) = img(:,:,1) + uint8(90  * mask);  % raise red
        img(:,:,2) = img(:,:,2) - min(img(:,:,2), uint8(70 * mask));  % kill green
        img(:,:,3) = img(:,:,3) - min(img(:,:,3), uint8(60 * mask));  % kill blue
    end
end

function img = add_neovascularization(img, X, Y)
% NV: dense chaotic vessel network near OD — detectable by Frangi+density check
% Creates thick bright vessel-like structures with high local density
    cx = 0.28; cy = 0.0;   % near OD location
    for k = 1:8             % 8 radiating branches
        theta0 = k * pi/4;
        for r = 0.02:0.005:0.18
            xp = cx + r*cos(theta0 + 0.3*sin(r*15));
            yp = cy + r*sin(theta0 + 0.3*cos(r*15));
            mask = double((X-xp).^2 + (Y-yp).^2 < 0.007^2);
            img(:,:,1) = img(:,:,1) + uint8(160 * mask);
            img(:,:,2) = img(:,:,2) + uint8(80  * mask);
            img(:,:,3) = img(:,:,3) + uint8(80  * mask);
        end
    end
    % Also add surrounding tortuous vessels for density
    for k = 1:5
        theta0 = k*pi/2.5 + 0.5;
        for r = 0.05:0.003:0.12
            xp = cx + r*cos(theta0 + sin(r*20)*0.4);
            yp = cy + r*sin(theta0 + cos(r*20)*0.4);
            mask = double((X-xp).^2 + (Y-yp).^2 < 0.005^2);
            img(:,:,1) = img(:,:,1) + uint8(140 * mask);
            img(:,:,2) = img(:,:,2) + uint8(60  * mask);
        end
    end
end

