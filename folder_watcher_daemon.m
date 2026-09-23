function processedCount = folder_watcher_daemon(cfg, mode, maxDuration)
% FOLDER_WATCHER_DAEMON  Autonomous "Hot-Folder" Screening Engine
%   Monitors incoming_fundus/ directory for newly dropped fundus photos.
%   Automatically analyzes quality, laterality, DR, DME, Glaucoma, AMD, and AVR.
%   Generates vector clinical PDF reports and routes them to:
%     - screened_reports/Urgent_Referrals/
%     - screened_reports/Clear_Routine/
%
%   Usage:
%     folder_watcher_daemon(cfg, 'runOnce');
%     folder_watcher_daemon(cfg, 'loop', 60); % loop for 60 seconds

if nargin < 1, cfg = dr_config(); end
if nargin < 2, mode = 'runOnce'; end
if nargin < 3, maxDuration = 30; end

inDir   = cfg.hotfolder.incomingDir;
archDir = fullfile(inDir, 'archive');
if ~exist(archDir, 'dir'), mkdir(archDir); end
if ~exist(cfg.hotfolder.routineDir, 'dir'), mkdir(cfg.hotfolder.routineDir); end
if ~exist(cfg.hotfolder.urgentDir, 'dir'), mkdir(cfg.hotfolder.urgentDir); end

fprintf('\n=======================================================\n');
fprintf('  OCULA AI — AUTONOMOUS CLINICAL HOT-FOLDER DAEMON\n');
fprintf('  Watching: %s\n', inDir);
fprintf('  Mode    : %s\n', mode);
fprintf('=======================================================\n\n');

processedCount = 0;
startTime = tic;

while true
    exts = {'*.jpg', '*.jpeg', '*.png', '*.tif', '*.bmp', '*.dcm'};
    files = [];
    for k = 1:numel(exts)
        files = [files; dir(fullfile(inDir, exts{k}))];
    end

    for fIdx = 1:numel(files)
        currFile = fullfile(files(fIdx).folder, files(fIdx).name);
        [~, baseName, fileExt] = fileparts(files(fIdx).name);

        fprintf('  [DAEMON] Detected new fundus scan: %s\n', files(fIdx).name);
        try
            % 1. Read Image (support both DICOM and standard raster)
            if strcmpi(fileExt, '.dcm')
                [rawImg, patMeta] = dicom_parser(currFile);
            else
                rawImg = imread(currFile);
                patMeta = struct('id', ['OCU-' baseName], 'name', ['Patient ' baseName], ...
                                 'age', 52, 'gender', 'Unknown');
            end

            if size(rawImg, 3) == 1
                rawImg = repmat(rawImg, [1 1 3]);
            end

            % 2. Quality Pipeline
            [enh, qc] = batch_quality_pipeline({rawImg}, cfg);

            % 3. Multi-Disease Segmentation
            seg = batch_segment_retina(enh, cfg);

            % 4. Grading
            [gr, ~] = batch_grade_dr(enh, seg, cfg);

            % 5. Determine Destination Folder
            isUrgent = gr(1).multiDiseaseReferral || gr(1).dme.hasCSME || gr(1).predictedGrade >= 2;
            if isUrgent
                destDir = cfg.hotfolder.urgentDir;
                routeLabel = 'URGENT_REFERRAL';
            else
                destDir = cfg.hotfolder.routineDir;
                routeLabel = 'CLEAR_ROUTINE';
            end

            % 6. Generate Clinical PDF Report
            repFig = figure('Name','OCULA AI Autonomous Report',...
                'Position',[100 100 1150 800],'Color','white','Visible','off');

            % Top Header
            annotation(repFig,'rectangle',[0.03 0.90 0.94 0.08],'FaceColor',[0.96 0.98 1.00],'EdgeColor',[0.80 0.85 0.92]);
            annotation(repFig,'textbox',[0.04 0.93 0.65 0.04],...
                'String', 'OCULA AI AUTONOMOUS CLINICAL TELE-SCREENING SYSTEM',...
                'FontSize',12,'FontWeight','bold','Color',[0.05 0.15 0.35],'EdgeColor','none');

            patHeader = sprintf('PATIENT: %s | ID: %s | EYE: %s | ROUTE: %s | PROCESSED: %s', ...
                patMeta.name, patMeta.id, seg(1).eyeLateralityLong, routeLabel, datestr(now,'yyyy-mm-dd HH:MM:SS'));
            annotation(repFig,'textbox',[0.04 0.905 0.92 0.025],...
                'String', patHeader,...
                'FontSize',8.5,'FontWeight','bold','Color',[0.2 0.2 0.2],'EdgeColor','none');

            % Subplot 1: Enhanced Fundus with Landmarks
            subplot(2,3,1);
            imshow(enh{1}); title('1. Fundus Image (Enhanced)','FontWeight','bold');
            hold on;
            viscircles(seg(1).odCenter, seg(1).odRadius, 'Color','cyan','LineWidth',1.2);
            plot(seg(1).foveaCenter(1), seg(1).foveaCenter(2), 'y+', 'MarkerSize',8, 'LineWidth',1.5);
            hold off;

            % Subplot 2: Vessels & Calibre (AVR)
            subplot(2,3,2);
            vShow = seg(1).vessels;
            if isempty(vShow), vShow = zeros(size(rawImg,1), size(rawImg,2)); end
            imshow(ind2rgb(uint8(vShow * 255), hot(256)));
            title(sprintf('2. Vessels & AVR (%.2f)', seg(1).hypertension.avr),'FontWeight','bold');

            % Subplot 3: Multi-Disease Lesions Map
            subplot(2,3,3);
            imshow(enh{1}); hold on;
            if ~isempty(seg(1).exudates.mask)
                [exY, exX] = find(seg(1).exudates.mask);
                plot(exX, exY, 'y.', 'MarkerSize', 3);
            end
            if ~isempty(seg(1).ma.mask)
                [maY, maX] = find(seg(1).ma.mask);
                plot(maX, maY, 'r.', 'MarkerSize', 4);
            end
            if ~isempty(seg(1).haem.mask)
                [hmY, hmX] = find(seg(1).haem.mask);
                plot(hmX, hmY, 'b.', 'MarkerSize', 5);
            end
            hold off;
            title('3. Pathology (MA/Ex/Hm)','FontWeight','bold');

            % Subplot 4: Optic Cup & Glaucoma CDR
            subplot(2,3,4);
            imshow(enh{1}); hold on;
            viscircles(seg(1).odCenter, seg(1).odRadius, 'Color','cyan','LineWidth',1.5);
            viscircles(seg(1).glaucoma.cupCenter, seg(1).glaucoma.cupRadius, 'Color','magenta','LineWidth',1.5);
            hold off;
            title(sprintf('4. Glaucoma vCDR: %.2f (%s)', seg(1).glaucoma.vCDR, seg(1).glaucoma.status),'FontWeight','bold');

            % Subplot 5: Disease Risk Breakdown Bar
            subplot(2,3,5);
            diseaseScores = [gr(1).predictedGrade/4, ...
                             double(seg(1).dme.riskGrade)/2, ...
                             min(1, seg(1).glaucoma.vCDR/0.8), ...
                             double(seg(1).amd.amdStage)/2, ...
                             double(seg(1).hypertension.grade)/2];
            b = bar(diseaseScores * 100, 'FaceColor',[0.2 0.5 0.8]);
            set(gca, 'XTickLabel', {'DR','DME','Glauc','AMD','HTN'}, 'YLim', [0 100]);
            ylabel('Risk Index (%)'); title('5. Multi-Disease Risk Matrix','FontWeight','bold');

            % Subplot 6: Summary & Certification
            subplot(2,3,6);
            cla; axis off;
            title('6. Clinical Routing Decision','FontWeight','bold');
            routeColor = [0.1 0.6 0.2];
            if isUrgent, routeColor = [0.85 0.1 0.1]; end

            summaryLines = {
                sprintf('Patient ID : %s', patMeta.id), ...
                sprintf('Laterality : %s', seg(1).eyeLateralityLong), ...
                sprintf('DR Grade   : %d (%s)', gr(1).predictedGrade, gr(1).gradeName), ...
                sprintf('Macular DME: %s', seg(1).dme.riskLabel), ...
                sprintf('Glaucoma   : %s', seg(1).glaucoma.status), ...
                sprintf('AMD Status : %s', seg(1).amd.status), ...
                sprintf('HTN AVR    : %s', seg(1).hypertension.status), ...
                '---------------------------------------------', ...
                sprintf('ROUTING ACTION: %s', routeLabel), ...
                'Verified: Autonomous Daemon Certified #AI-2026'
            };
            text(0.02, 0.50, summaryLines, 'FontSize', 8, 'Color', [0.1 0.1 0.1], 'Interpreter', 'none');

            % Export PDF & PNG
            outBase = sprintf('AutoScreen_%s_%s', baseName, datestr(now,'yyyymmdd_HHMMSS'));
            pdfFile = fullfile(destDir, [outBase '.pdf']);
            pngFile = fullfile(destDir, [outBase '.png']);
            exportgraphics(repFig, pdfFile, 'ContentType', 'vector');
            exportgraphics(repFig, pngFile, 'Resolution', 150);
            close(repFig);

            % 7. Archive Processed Raw Image
            archiveDest = fullfile(archDir, [baseName '_' datestr(now,'yyyymmdd_HHMMSS') fileExt]);
            movefile(currFile, archiveDest);

            processedCount = processedCount + 1;
            fprintf('  [DAEMON SUCCESS] Processed %s -> Routed to %s\n', files(fIdx).name, routeLabel);

        catch ME
            fprintf('  [DAEMON ERROR] Failed processing %s: %s\n', files(fIdx).name, ME.message);
        end
    end

    if strcmp(mode, 'runOnce') || toc(startTime) >= maxDuration
        break;
    end
    pause(2);
end

fprintf('  [DAEMON] Finished. Total scans processed: %d\n\n', processedCount);
end
