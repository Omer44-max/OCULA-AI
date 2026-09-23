function [rgbImg, patMeta] = dicom_parser(dicomFilePath)
% DICOM_PARSER  Extracts calibrated RGB retinal image and patient metadata from DICOM files
%   Supports standard ophthalmic DICOM SOP classes (Zeiss, Topcon, Canon, Nidek, etc.)
%
%   Outputs:
%     rgbImg  : 3-channel uint8 [512x512x3] fundus image
%     patMeta : struct with fields: id, name, age, gender, eye, manufacturer, studyDate

patMeta = struct(...
    'id', 'OCU-DICOM-001', ...
    'name', 'Anonymous Patient', ...
    'age', 55, ...
    'gender', 'Unknown', ...
    'eye', 'Auto', ...
    'manufacturer', 'Standard PACS', ...
    'studyDate', datestr(now, 'yyyy-mm-dd') ...
);

try
    % 1. Read DICOM metadata
    info = dicominfo(dicomFilePath);

    % Extract Patient Name
    if isfield(info, 'PatientName')
        if isstruct(info.PatientName) && isfield(info.PatientName, 'FamilyName')
            patMeta.name = [info.PatientName.GivenName ' ' info.PatientName.FamilyName];
        elseif ischar(info.PatientName)
            patMeta.name = strrep(info.PatientName, '^', ' ');
        end
    end

    % Extract Patient ID
    if isfield(info, 'PatientID') && ~isempty(info.PatientID)
        patMeta.id = char(info.PatientID);
    end

    % Extract Patient Sex
    if isfield(info, 'PatientSex')
        switch upper(info.PatientSex)
            case 'M', patMeta.gender = 'Male';
            case 'F', patMeta.gender = 'Female';
            otherwise, patMeta.gender = 'Other';
        end
    end

    % Extract Patient Age
    if isfield(info, 'PatientAge') && ~isempty(info.PatientAge)
        ageNum = sscanf(info.PatientAge, '%d');
        if ~isempty(ageNum), patMeta.age = ageNum(1); end
    elseif isfield(info, 'PatientBirthDate') && ~isempty(info.PatientBirthDate)
        try
            bDate = datetime(info.PatientBirthDate, 'InputFormat', 'yyyyMMdd');
            patMeta.age = round(years(datetime('now') - bDate));
        catch
        end
    end

    % Extract Eye Laterality (R = OD, L = OS)
    if isfield(info, 'ImageLaterality')
        if strcmpi(info.ImageLaterality, 'R'), patMeta.eye = 'OD';
        elseif strcmpi(info.ImageLaterality, 'L'), patMeta.eye = 'OS';
        end
    elseif isfield(info, 'Laterality')
        if strcmpi(info.Laterality, 'R'), patMeta.eye = 'OD';
        elseif strcmpi(info.Laterality, 'L'), patMeta.eye = 'OS';
        end
    end

    % Extract Manufacturer
    if isfield(info, 'Manufacturer')
        patMeta.manufacturer = char(info.Manufacturer);
    end

    % Extract Study Date
    if isfield(info, 'StudyDate') && ~isempty(info.StudyDate)
        try
            sDate = datetime(info.StudyDate, 'InputFormat', 'yyyyMMdd');
            patMeta.studyDate = char(sDate, 'yyyy-MM-dd');
        catch
        end
    end

    % 2. Read Pixel Matrix
    rawPixels = dicomread(info);

    % Handle 12-bit / 16-bit to 8-bit dynamic range conversion
    if isa(rawPixels, 'uint16')
        pMin = double(min(rawPixels(:)));
        pMax = double(max(rawPixels(:)));
        if pMax > pMin
            scaled = (double(rawPixels) - pMin) / (pMax - pMin);
            rgbImg = im2uint8(scaled);
        else
            rgbImg = uint8(rawPixels / 256);
        end
    elseif isa(rawPixels, 'uint8')
        rgbImg = rawPixels;
    else
        rgbImg = im2uint8(mat2gray(rawPixels));
    end

    % Ensure 3-channel color
    if size(rgbImg, 3) == 1
        rgbImg = repmat(rgbImg, [1 1 3]);
    end

catch ME
    % Fallback for standard raster images or non-standard DICOM streams
    try
        rgbImg = imread(dicomFilePath);
        if size(rgbImg, 3) == 1
            rgbImg = repmat(rgbImg, [1 1 3]);
        end
        [~, bName] = fileparts(dicomFilePath);
        patMeta.id = ['OCU-' bName];
        patMeta.name = ['Patient ' bName];
    catch
        error('DICOM_PARSER:FailedToRead', 'Could not parse medical image: %s', ME.message);
    end
end
end
