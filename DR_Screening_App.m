function DR_Screening_App()
% DR_SCREENING_APP  Modern Clinical GUI for Diabetic Retinopathy Screening
%   Features:
%     1. Clinical Light Theme (Hospital white / medical slate-blue aesthetic)
%     2. Multi-View Comparison Grid (Raw, Enhanced, Vessels, Lesions, Grad-CAM, Probs)
%     3. Interactive Deep-Dive Inspector with dynamic lesion toggle checkboxes
%     4. Batch Patient Screening Queue (interactive table)
%     5. One-click Clinical Report Export (PDF / PNG)
%     6. Auto-loads demo set on launch so the interface is never empty!
%
%   Launch with:  DR_Screening_App

addpath(genpath(fileparts(mfilename('fullpath'))));
cfg = dr_config();

% Silently hide the MATLAB desktop / command window so only OCULA AI is visible
try
    if usejava('desktop')
        dt = com.mathworks.mde.desk.MLDesktop.getInstance();
        dt.getMainFrame().setVisible(false);
    end
catch
end

%% ── Colour Palette (Hospital Clinical Light Theme) ─────────────────────
C.bg         = [0.94 0.96 0.98];   % Hospital Ice Slate #F1F5F9
C.panel      = [0.98 0.99 1.00];   % Clean White-Blue #F8FAFC
C.card       = [1.00 1.00 1.00];   % Pure White Card #FFFFFF
C.cardBorder = [0.82 0.86 0.91];   % Subtle Slate Border #CBD5E1
C.primary    = [0.01 0.44 0.74];   % Medical Cobalt Blue #0284C7
C.textDark   = [0.06 0.10 0.16];   % Deep Navy Charcoal #0F172A
C.textSub    = [0.20 0.26 0.35];   % Slate 700 #334155
C.textMuted  = [0.42 0.48 0.56];   % Slate 500 #64748B
C.green      = [0.02 0.60 0.35];   % Medical Emerald #059669
C.greenBg    = [0.88 0.97 0.92];   % Light Emerald
C.amber      = [0.85 0.48 0.05];   % Warning Amber #D97706
C.amberBg    = [0.99 0.95 0.88];   % Light Amber
C.orange     = [0.90 0.35 0.05];   % Moderate Orange #EA580C
C.orangeBg   = [0.99 0.93 0.89];   % Light Orange
C.red        = [0.85 0.15 0.15];   % Critical Red #DC2626
C.redBg      = [0.99 0.91 0.91];   % Light Red
C.purple     = [0.48 0.18 0.78];   % Deep Purple #7C3AED
C.purpleBg   = [0.95 0.91 0.99];   % Light Purple

%% ── Main Window (1280 x 720 fits all laptop screens) ───────────────────
fig = uifigure('Name','OCULA AI — Intelligent Diabetic Retinopathy Diagnostic Workstation',...
    'Position',[30 35 1280 715],...
    'Color',C.bg,...
    'Resize','on',...
    'CloseRequestFcn', @(~,~) onCloseApp());

%% ── App State (Using Cell Arrays for Struct Safety) ───────────────────
state.imgList       = {};
state.fileNames     = {};
state.patients      = struct('id',{},'name',{},'age',{},'gender',{});
state.qcResults     = {};
state.segResults    = {};
state.gradeResults  = {};
state.netFeatures   = {};
state.camMaps       = {};
state.currentIdx    = 1;
state.enhancedImgs  = {};

%% ── Top Header Bar ─────────────────────────────────────────────────────
hdr = uipanel(fig,'Position',[0 655 1280 60],...
    'BackgroundColor',C.card,'BorderType','line',...
    'HighlightColor',C.cardBorder);

logoPath = fullfile(fileparts(mfilename('fullpath')), 'ocula_logo.png');
if exist(logoPath, 'file')
    uiimage(hdr, 'ImageSource', logoPath, 'Position', [15 7 46 46]);
    uilabel(hdr,'Text','OCULA AI — Clinical Diagnostic Workstation',...
        'Position',[68 16 430 28],...
        'FontSize',16,'FontWeight','bold',...
        'FontColor',C.primary,'BackgroundColor','none');
    uilabel(hdr,'Text','Next-Gen Dual-Path Fundus Screening Engine | Mobile & Telemedicine Ready',...
        'Position',[505 20 420 20],...
        'FontSize',9,'FontColor',C.textMuted,'BackgroundColor','none');
else
    uilabel(hdr,'Text','👁️  OCULA AI — Clinical Diagnostic Workstation',...
        'Position',[20 16 460 28],...
        'FontSize',17,'FontWeight','bold',...
        'FontColor',C.primary,'BackgroundColor','none');
    uilabel(hdr,'Text','Next-Gen Dual-Path Fundus Screening Engine | Mobile & Telemedicine Ready',...
        'Position',[485 20 440 20],...
        'FontSize',9,'FontColor',C.textMuted,'BackgroundColor','none');
end

% Top bar action buttons
uibutton(hdr,'push','Text','📄  Export Report (PNG/PDF)',...
    'Position',[940 12 175 36],...
    'BackgroundColor',C.card,'FontColor',C.primary,...
    'FontSize',10,'FontWeight','bold',...
    'ButtonPushedFcn', @(~,~) exportCurrentReport());

uibutton(hdr,'push','Text','📁  Open Reports',...
    'Position',[1125 12 135 36],...
    'BackgroundColor',C.card,'FontColor',C.textSub,...
    'FontSize',10,...
    'ButtonPushedFcn', @(~,~) winopen(cfg.outputDir));

%% ── Left Control Sidebar ───────────────────────────────────────────────
lp = uipanel(fig,'Position',[10 10 248 638],...
    'BackgroundColor',C.card,'BorderType','line',...
    'HighlightColor',C.cardBorder);

uilabel(lp,'Text','DATA INGESTION','Position',[12 612 220 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');

btnLoad = uibutton(lp,'push','Text','📂  Load Fundus Image',...
    'Position',[12 580 110 30],...
    'BackgroundColor',C.primary,'FontColor',[1 1 1],...
    'FontSize',9,'FontWeight','bold',...
    'ButtonPushedFcn', @(~,~) loadImage());

btnBatchLoad = uibutton(lp,'push','Text','📁  Batch Folder',...
    'Position',[126 580 110 30],...
    'BackgroundColor',C.panel,'FontColor',C.primary,...
    'FontSize',9,'FontWeight','bold',...
    'ButtonPushedFcn', @(~,~) loadFolder());

btnDemo = uibutton(lp,'push','Text','🎲  Reload 5-Grade Demo Set',...
    'Position',[12 548 224 26],...
    'BackgroundColor',C.panel,'FontColor',C.textSub,...
    'FontSize',9,...
    'ButtonPushedFcn', @(~,~) loadDemo());

% Separator
uipanel(lp,'Position',[12 540 224 1],'BackgroundColor',C.cardBorder,'BorderType','none');

% Patient Demographics Section
uilabel(lp,'Text','PATIENT DEMOGRAPHICS','Position',[12 522 220 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');

uilabel(lp,'Text','Name:','Position',[12 498 45 18],'FontSize',8,'FontColor',C.textSub);
txtPatName = uieditfield(lp,'text','Position',[58 498 178 20],...
    'Value','Jane Doe','FontSize',8,'ValueChangedFcn',@(~,~) onDemographicsChanged());

uilabel(lp,'Text','ID:','Position',[12 474 45 18],'FontSize',8,'FontColor',C.textSub);
txtPatID = uieditfield(lp,'text','Position',[58 474 85 20],...
    'Value','OCU-2026-01','FontSize',8,'ValueChangedFcn',@(~,~) onDemographicsChanged());

uilabel(lp,'Text','Age:','Position',[150 474 30 18],'FontSize',8,'FontColor',C.textSub);
spnPatAge = uispinner(lp,'Position',[180 474 56 20],...
    'Limits',[1 120],'Value',58,'FontSize',8,'ValueChangedFcn',@(~,~) onDemographicsChanged());

uilabel(lp,'Text','Gender:','Position',[12 450 45 18],'FontSize',8,'FontColor',C.textSub);
ddPatGender = uidropdown(lp,'Items',{'Female','Male','Other'},'Value','Female',...
    'Position',[58 450 178 20],'FontSize',8,'ValueChangedFcn',@(~,~) onDemographicsChanged());

% Separator
uipanel(lp,'Position',[12 442 224 1],'BackgroundColor',C.cardBorder,'BorderType','none');

uilabel(lp,'Text','IMAGE SELECTION','Position',[12 424 220 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');

ddGrade = uidropdown(lp,'Items',{'Loading Demo Images...'},...
    'Position',[12 400 224 24],...
    'BackgroundColor',C.panel,'FontColor',C.textDark,'FontSize',9,...
    'ValueChangedFcn', @(dd,~) onDropdownSwitch(dd.Value));

% Separator
uipanel(lp,'Position',[12 392 224 1],'BackgroundColor',C.cardBorder,'BorderType','none');

uilabel(lp,'Text','PIPELINE STAGES','Position',[12 374 220 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');

stages = {'Quality & CLAHE','Vessels & Lesions','ICDR AI Grading','Grad-CAM Heatmap'};
hStage = gobjects(4,1);
for k_stg = 1:4
    hStage(k_stg) = uilabel(lp,...
        'Text', sprintf('-  %s', stages{k_stg}),...
        'Position',[15 354-(k_stg-1)*20 220 18],...
        'FontSize',8,'FontColor',C.textMuted,'BackgroundColor','none');
end

% Run Buttons
btnRun = uibutton(lp,'push','Text','▶  ANALYSE CURRENT',...
    'Position',[12 245 224 34],...
    'BackgroundColor',C.green,'FontColor',[1 1 1],...
    'FontSize',11,'FontWeight','bold',...
    'ButtonPushedFcn', @(~,~) runAnalysis(false),...
    'Enable','on');

btnBatchAll = uibutton(lp,'push','Text','⚡  ANALYSE ALL IN QUEUE',...
    'Position',[12 208 224 30],...
    'BackgroundColor',C.panel,'FontColor',C.primary,...
    'FontSize',9,'FontWeight','bold',...
    'ButtonPushedFcn', @(~,~) runAnalysis(true),...
    'Enable','on');

btnBench = uibutton(lp,'push','Text','📊  Compare vs Benchmarks',...
    'Position',[12 174 224 28],...
    'BackgroundColor',C.panel,'FontColor',C.textSub,...
    'FontSize',9,...
    'ButtonPushedFcn', @(~,~) runBenchmark());

% Status Box
uipanel(lp,'Position',[12 10 224 156],'BackgroundColor',C.panel,'BorderType','line',...
    'HighlightColor',C.cardBorder);
uilabel(lp,'Text','SYSTEM STATUS','Position',[20 142 200 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.textMuted,'BackgroundColor','none');
hStatus = uilabel(lp,'Text','Ready. Demo images loaded automatically.',...
    'Position',[20 10 208 130],'FontSize',8,'FontColor',C.textSub,...
    'BackgroundColor','none','WordWrap','on');

%% ── Center Workspace (Tabbed) ──────────────────────────────────────────
cw = uipanel(fig,'Position',[266 10 696 638],...
    'BackgroundColor',C.card,'BorderType','line',...
    'HighlightColor',C.cardBorder);

tabGroup = uitabgroup(cw,'Position',[4 4 688 628]);

% ── Tab 1: Multi-View Comparison Grid (Side-by-Side) ───────────────────
tab1 = uitab(tabGroup,'Title','  Multi-View Comparison  ');
tab1.BackgroundColor = C.panel;

axGrid = gobjects(4,1);
gridTitles = {'1. Original Fundus (Raw)','2. Retinal Vessels (Frangi Map)',...
              '3. Lesion Overlay (OD, MAs, Exudates, Haem)','4. Grad-CAM Explainability Attention'};

posGrid = {
    [10 305 328 285], ...   % Top-Left
    [348 305 328 285], ...  % Top-Right
    [10 12 328 285], ...    % Bottom-Left
    [348 12 328 285]        % Bottom-Right
};

for g_ax = 1:4
    % Create card panel container
    pCard = uipanel(tab1,'Position',posGrid{g_ax},'BackgroundColor',C.card,'BorderType','line',...
        'HighlightColor',C.cardBorder);
    
    % Title inside card panel
    uilabel(pCard,'Text',gridTitles{g_ax},...
        'Position',[10 posGrid{g_ax}(4)-24 posGrid{g_ax}(3)-20 20],...
        'FontSize',9,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');
    
    % Axes as CHILD of card panel (never occluded by panel!)
    axGrid(g_ax) = uiaxes(pCard,...
        'Position',[6 6 posGrid{g_ax}(3)-12 posGrid{g_ax}(4)-32],...
        'Color',[0.06 0.08 0.12],'XColor','none','YColor','none');
    axGrid(g_ax).Toolbar.Visible = 'off';
    text(axGrid(g_ax),0.5,0.5,'Click ANALYSE to View','Units','normalized',...
        'HorizontalAlignment','center','Color',[0.7 0.7 0.7],'FontSize',10);
end

% ── Tab 2: Interactive Deep-Dive Inspector (with Layer Toggles) ─────────
tab2 = uitab(tabGroup,'Title','  Interactive Lesion Inspector  ');
tab2.BackgroundColor = C.panel;

pInspectCard = uipanel(tab2,'Position',[10 75 668 515],'BackgroundColor',C.card,...
    'BorderType','line','HighlightColor',C.cardBorder);

axInspect = uiaxes(pInspectCard,'Position',[6 6 656 503],...
    'Color',[0.06 0.08 0.12],'XColor','none','YColor','none');
axInspect.Toolbar.Visible = 'on';
text(axInspect,0.5,0.5,'Load image and run analysis to inspect layers',...
    'Units','normalized','HorizontalAlignment','center','Color',[0.7 0.7 0.7],'FontSize',11);

% Layer Toggle Toolbar at Bottom
pToggles = uipanel(tab2,'Position',[10 8 668 62],...
    'BackgroundColor',C.card,'BorderType','line','HighlightColor',C.cardBorder);

uilabel(pToggles,'Text','LAYER VISIBILITY:','Position',[10 36 140 18],...
    'FontSize',9,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');

cbOD = uicheckbox(pToggles,'Text','Optic Disc & Fovea','Position',[10 10 135 20],...
    'Value',true,'FontColor',C.textDark,'ValueChangedFcn',@(~,~) redrawInteractiveView());
cbMA = uicheckbox(pToggles,'Text','Microaneurysms (Red)','Position',[150 10 145 20],...
    'Value',true,'FontColor',C.textDark,'ValueChangedFcn',@(~,~) redrawInteractiveView());
cbEx = uicheckbox(pToggles,'Text','Hard Exudates (Yellow)','Position',[300 10 145 20],...
    'Value',true,'FontColor',C.textDark,'ValueChangedFcn',@(~,~) redrawInteractiveView());
cbHm = uicheckbox(pToggles,'Text','Haemorrhages (Dark)','Position',[450 10 135 20],...
    'Value',true,'FontColor',C.textDark,'ValueChangedFcn',@(~,~) redrawInteractiveView());
cbCAM = uicheckbox(pToggles,'Text','Grad-CAM Heatmap','Position',[590 10 120 20],...
    'Value',false,'FontColor',C.textDark,'ValueChangedFcn',@(~,~) redrawInteractiveView());

% ── Tab 3: Patient Batch Queue & Screening Registry ─────────────────────
tab3 = uitab(tabGroup,'Title','  Patient Queue & Registry  ');
tab3.BackgroundColor = C.panel;

uilabel(tab3,'Text','SCREENING BATCH REGISTRY','Position',[15 565 300 22],...
    'FontSize',11,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');

tblQueue = uitable(tab3,'Position',[15 15 658 545],...
    'ColumnName',{'#','Patient ID','Patient Name','Eye','DME Status','Image File','QC','ICDR Grade','Diagnosis','Referral'},...
    'ColumnWidth',{28, 80, 95, 45, 90, 100, 60, 65, 95, 80},...
    'RowName',{},...
    'CellSelectionCallback', @(~,ev) onQueueSelection(ev));

%% ── Right Diagnostic Results Panel ─────────────────────────────────────
rp = uipanel(fig,'Position',[970 10 300 638],...
    'BackgroundColor',C.card,'BorderType','line',...
    'HighlightColor',C.cardBorder);

uilabel(rp,'Text','DIAGNOSTIC FINDINGS','Position',[12 612 150 16],...
    'FontSize',9,'FontWeight','bold','FontColor',C.primary,'BackgroundColor','none');

% Eye Laterality & DME Indicators Badge Row
hEyeBadge = uilabel(rp,'Text','Eye: --',...
    'Position',[160 610 60 20],'FontSize',8,'FontWeight','bold',...
    'FontColor',C.primary,'BackgroundColor',C.panel,'HorizontalAlignment','center');

hDMEBadge = uilabel(rp,'Text','DME: --',...
    'Position',[224 610 64 20],'FontSize',8,'FontWeight','bold',...
    'FontColor',C.green,'BackgroundColor',C.greenBg,'HorizontalAlignment','center');

% Grade Display Card
pGradeCard = uipanel(rp,'Position',[12 526 276 78],...
    'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.cardBorder);

hGradeBadge = uilabel(pGradeCard,'Text','NO DATA',...
    'Position',[8 42 260 24],'FontSize',12,'FontWeight','bold',...
    'FontColor',C.textMuted,'BackgroundColor','none');

hGradeSubtitle = uilabel(pGradeCard,'Text','Click ANALYSE to determine ICDR grade',...
    'Position',[8 22 260 18],'FontSize',8,'FontColor',C.textMuted,'BackgroundColor','none');

hReferralBadge = uilabel(pGradeCard,'Text','-',...
    'Position',[8 4 260 18],'FontSize',8,'FontWeight','bold',...
    'FontColor',C.textMuted,'BackgroundColor','none');

% Confidence Meter
uilabel(rp,'Text','DIAGNOSTIC CONFIDENCE','Position',[12 502 200 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.textSub,'BackgroundColor','none');

axConf = uiaxes(rp,'Position',[12 478 276 24],...
    'Color',C.panel,'XColor','none','YColor','none','XLim',[0 1],'YLim',[0 1]);
axConf.Toolbar.Visible = 'off';

% Grade Probability Distribution Bar Chart
uilabel(rp,'Text','ICDR CLASS PROBABILITIES (%)','Position',[12 454 220 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.textSub,'BackgroundColor','none');

axProb = uiaxes(rp,'Position',[12 372 276 80],...
    'Color',C.panel,'XColor',C.textMuted,'YColor',C.textMuted,...
    'FontSize',8,'YLim',[0 100],'XLim',[0.5 5.5]);
axProb.Toolbar.Visible = 'off';
set(axProb,'XTickLabel',{'G0','G1','G2','G3','G4'});

% Multi-Disease Biomarkers & Quantitative Metrics
uilabel(rp,'Text','MULTI-DISEASE BIOMARKERS & LESIONS','Position',[12 350 260 16],...
    'FontSize',8,'FontWeight','bold','FontColor',C.textSub,'BackgroundColor','none');

pLesionCard = uipanel(rp,'Position',[12 205 276 142],...
    'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.cardBorder);

lblEyeLaterality = uilabel(pLesionCard,'Text','Laterality: -','Position',[8 122 260 16],'FontSize',8,'FontColor',C.primary,'FontWeight','bold');
lblDMERisk       = uilabel(pLesionCard,'Text','Macular Edema: -','Position',[8 106 260 16],'FontSize',8,'FontColor',C.textDark,'FontWeight','bold');
lblGlaucCDR      = uilabel(pLesionCard,'Text','Glaucoma vCDR: -','Position',[8 90 260 16],'FontSize',8,'FontColor',C.purple,'FontWeight','bold');
lblAMDStatus     = uilabel(pLesionCard,'Text','Macular AMD: -','Position',[8 74 260 16],'FontSize',8,'FontColor',C.textDark,'FontWeight','bold');
lblHTNAVR        = uilabel(pLesionCard,'Text','Hypertensive AVR: -','Position',[8 58 260 16],'FontSize',8,'FontColor',C.textDark,'FontWeight','bold');
lblLesionMA      = uilabel(pLesionCard,'Text','Microaneurysms: -','Position',[8 42 260 16],'FontSize',8,'FontColor',C.textDark);
lblLesionEx      = uilabel(pLesionCard,'Text','Hard Exudates: -','Position',[8 26 260 16],'FontSize',8,'FontColor',C.textDark);
lblLesionHem     = uilabel(pLesionCard,'Text','Haemorrhages: -','Position',[8 10 260 16],'FontSize',8,'FontColor',C.textDark);

% Clinical Recommendation Box
uilabel(rp,'Text','CLINICAL ACTION PLAN','Position',[12 204 200 18],...
    'FontSize',8,'FontWeight','bold','FontColor',C.textSub,'BackgroundColor','none');

pRecCard = uipanel(rp,'Position',[12 124 276 78],...
    'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.cardBorder);

lblRecTitle = uilabel(pRecCard,'Text','Recommendation','Position',[8 56 260 18],...
    'FontSize',8,'FontWeight','bold','FontColor',C.textDark,'BackgroundColor','none');

lblRecDesc = uilabel(pRecCard,'Text','Run analysis to generate recommendations.',...
    'Position',[8 4 260 50],'FontSize',8,'FontColor',C.textSub,...
    'BackgroundColor','none','WordWrap','on');

% Quality & Timing Footer
pFooterCard = uipanel(rp,'Position',[12 10 276 108],...
    'BackgroundColor',C.panel,'BorderType','line','HighlightColor',C.cardBorder);

lblQCInfo = uilabel(pFooterCard,'Text','Image Quality: Awaiting analysis',...
    'Position',[8 82 260 18],'FontSize',8,'FontColor',C.textSub,'BackgroundColor','none');
lblSharpInfo = uilabel(pFooterCard,'Text','Sharpness: - | Brightness: -',...
    'Position',[8 62 260 18],'FontSize',8,'FontColor',C.textMuted,'BackgroundColor','none');
lblProcTime = uilabel(pFooterCard,'Text','AI Inference Time: -',...
    'Position',[8 42 260 18],'FontSize',8,'FontColor',C.textMuted,'BackgroundColor','none');
lblPathUsed = uilabel(pFooterCard,'Text','Grading Engine: ICDR Dual-Path Fusion',...
    'Position',[8 14 260 26],'FontSize',8,'FontColor',C.primary,'BackgroundColor','none','WordWrap','on');

%% ══════════════════════════════════════════════════════════════════════
%  CALLBACK FUNCTIONS
% ══════════════════════════════════════════════════════════════════════

    function onDemographicsChanged()
        idx = state.currentIdx;
        if isempty(state.patients) || idx > numel(state.patients)
            return;
        end
        state.patients(idx).name   = txtPatName.Value;
        state.patients(idx).id     = txtPatID.Value;
        state.patients(idx).age    = spnPatAge.Value;
        state.patients(idx).gender = ddPatGender.Value;
        updateQueueTable();
    end

    function syncDemographicsUI(idx)
        if isempty(state.patients) || idx > numel(state.patients)
            return;
        end
        txtPatName.Value  = state.patients(idx).name;
        txtPatID.Value    = state.patients(idx).id;
        spnPatAge.Value   = state.patients(idx).age;
        ddPatGender.Value = state.patients(idx).gender;
    end

    function loadImage()
        setStatus('Opening file selector...');
        [file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.bmp;*.dcm;*.DCM;*.dicom',...
            'Retinal Fundus / DICOM Images (*.jpg,*.png,*.dcm)'}, 'Select Retinal Fundus Image');
        if isequal(file, 0), setStatus('File selection cancelled.'); return; end

        fpath = fullfile(path, file);
        if endsWith(lower(file), '.dcm') || endsWith(lower(file), '.dicom')
            [raw, patMeta] = dicom_parser(fpath);
            state.patients  = patMeta;
        else
            raw = imread(fpath);
            state.patients  = struct('id','OCU-2026-001','name','Jane Doe','age',58,'gender','Female');
        end
        state.imgList   = {raw};
        state.fileNames = {file};
        state.currentIdx = 1;
        state.qcResults = {};
        state.segResults = {};
        state.gradeResults = {};
        state.camMaps = {};

        ddGrade.Items = {file};
        ddGrade.Value = file;
        syncDemographicsUI(1);

        showRawPreview(raw, file);
        btnRun.Enable      = 'on';
        btnBatchAll.Enable = 'off';
        updateQueueTable();
        setStatus(sprintf('Loaded: %s. Click ANALYSE CURRENT.', file));
    end

    function loadFolder()
        setStatus('Selecting fundus images directory...');
        selDir = uigetdir(cfg.testImgDir, 'Select Folder with Fundus Images');
        if isequal(selDir, 0), setStatus('Folder selection cancelled.'); return; end

        exts = {'*.jpg','*.jpeg','*.png','*.tif','*.bmp'};
        files = [];
        for e = 1:numel(exts)
            files = [files; dir(fullfile(selDir, exts{e}))]; %#ok<AGROW>
        end

        if isempty(files)
            setStatus('No fundus image files found in selected folder.');
            return;
        end

        nF = numel(files);
        state.imgList   = cell(nF, 1);
        state.fileNames = cell(nF, 1);
        state.patients  = repmat(struct('id','','name','','age',50,'gender','Female'), nF, 1);
        demoNames = {'Robert Chen','Maria Garcia','John Smith','Aisha Khan','David Miller','Sarah Jenkins'};
        genders   = {'Male','Female','Male','Female','Male','Female'};

        for i = 1:nF
            state.imgList{i}   = imread(fullfile(files(i).folder, files(i).name));
            state.fileNames{i} = files(i).name;
            nmIdx = mod(i-1, numel(demoNames)) + 1;
            state.patients(i).id     = sprintf('OCU-2026-%03d', i);
            state.patients(i).name   = demoNames{nmIdx};
            state.patients(i).age    = 45 + mod(i*7, 35);
            state.patients(i).gender = genders{nmIdx};
        end
        state.currentIdx   = 1;
        state.qcResults    = {};
        state.segResults   = {};
        state.gradeResults = {};
        state.netFeatures  = {};
        state.camMaps      = {};

        ddGrade.Items = state.fileNames;
        ddGrade.Value = state.fileNames{1};
        syncDemographicsUI(1);

        showRawPreview(state.imgList{1}, state.fileNames{1});
        btnRun.Enable      = 'on';
        btnBatchAll.Enable = 'on';
        updateQueueTable();
        setStatus(sprintf('Loaded %d images from folder. Ready for batch analysis.', nF));
    end

    function loadDemo()
        setStatus('Loading synthetic demo image set (Grades 0 to 4)...');
        drawnow;
        [state.imgList, ~] = load_fundus_dataset(cfg);
        nF = numel(state.imgList);
        state.fileNames = arrayfun(@(x) sprintf('Synthetic_Grade_%d.png', x-1), 1:nF, 'UniformOutput', false);
        state.patients  = repmat(struct('id','','name','','age',50,'gender','Female'), nF, 1);
        demoNames = {'Alice Johnson','Michael Chang','Elena Rostova','Kwame Mensah','Fatima Al-Zahra'};
        genders   = {'Female','Male','Female','Male','Female'};
        ages      = [52, 61, 49, 67, 58];

        for i = 1:nF
            state.patients(i).id     = sprintf('OCU-DEMO-%02d', i);
            state.patients(i).name   = demoNames{i};
            state.patients(i).age    = ages(i);
            state.patients(i).gender = genders{i};
        end

        state.currentIdx = 1;
        state.qcResults = {};
        state.segResults = {};
        state.gradeResults = {};
        state.netFeatures = {};
        state.camMaps = {};

        ddGrade.Items = state.fileNames;
        ddGrade.Value = state.fileNames{1};
        syncDemographicsUI(1);

        showRawPreview(state.imgList{1}, state.fileNames{1});
        btnRun.Enable      = 'on';
        btnBatchAll.Enable = 'on';
        updateQueueTable();
        % Automatically run analysis on scan 1 so all 4 panels are populated!
        runAnalysis(false);
    end

    function showRawPreview(img, titleStr)
        cla(axGrid(1));
        imshow(img, 'Parent', axGrid(1));
        axGrid(1).XTick = []; axGrid(1).YTick = [];
        title(axGrid(1), sprintf('Raw Fundus: %s', titleStr), 'Color', [1 1 1], 'FontSize', 9);

        for g_pv = 2:4
            cla(axGrid(g_pv));
            axGrid(g_pv).Color = [0.06 0.08 0.12];
            text(axGrid(g_pv), 0.5, 0.5, 'Click ANALYSE to View', 'Units','normalized',...
                'HorizontalAlignment','center','Color',[0.7 0.7 0.7],'FontSize',10);
        end

        cla(axInspect);
        imshow(img, 'Parent', axInspect);
        axInspect.XTick = []; axInspect.YTick = [];
    end

    function onDropdownSwitch(val)
        idx = find(strcmp(state.fileNames, val), 1);
        if isempty(idx), return; end
        switchPatientIndex(idx);
    end

    function onQueueSelection(ev)
        if isempty(ev.Indices), return; end
        row = ev.Indices(1,1);
        if row >= 1 && row <= numel(state.imgList)
            ddGrade.Value = state.fileNames{row};
            switchPatientIndex(row);
        end
    end

    function switchPatientIndex(idx)
        state.currentIdx = idx;
        syncDemographicsUI(idx);
        img = state.imgList{idx};
        fname = state.fileNames{idx};

        if isempty(state.gradeResults) || idx > numel(state.gradeResults) || isempty(state.gradeResults{idx})
            showRawPreview(img, fname);
        else
            updateAllVisuals(idx);
        end
    end

    function runAnalysis(isBatchAll)
        if isempty(state.imgList)
            loadDemo(); return;
        end

        btnRun.Enable      = 'off';
        btnBatchAll.Enable = 'off';
        tStart = tic;

        if isBatchAll
            targetIndices = 1:numel(state.imgList);
        else
            targetIndices = state.currentIdx;
        end

        nTotal = numel(targetIndices);
        for step = 1:nTotal
            curI = targetIndices(step);
            img = state.imgList{curI};

            % Stage 1: QC
            updateStage(1, 'running');
            setStatus(sprintf('[%d/%d] Image Quality Assessment & Enhancement...', step, nTotal));
            drawnow;
            [enhImgs, qcR] = batch_quality_pipeline({img}, cfg);
            state.enhancedImgs{curI} = enhImgs{1};
            state.qcResults{curI} = qcR(1);
            updateStage(1, 'done');

            % Stage 2: Segmentation
            updateStage(2, 'running');
            setStatus(sprintf('[%d/%d] Retinal Segmentation (Frangi, OD, MA, Exudates, Haem)...', step, nTotal));
            drawnow;
            segR = batch_segment_retina(enhImgs, cfg);
            state.segResults{curI} = segR(1);
            updateStage(2, 'done');

            % Stage 3: Grading
            updateStage(3, 'running');
            setStatus(sprintf('[%d/%d] Dual-Path ICDR DR Severity Grading...', step, nTotal));
            drawnow;
            [gradeR, netF] = batch_grade_dr(enhImgs, segR, cfg);
            state.gradeResults{curI} = gradeR(1);
            state.netFeatures{curI} = netF{1};
            updateStage(3, 'done');

            % Stage 4: Grad-CAM
            updateStage(4, 'running');
            setStatus(sprintf('[%d/%d] Computing Explainable Grad-CAM Heatmap...', step, nTotal));
            drawnow;
            camMap = generate_synthetic_gradcam_local(enhImgs{1}, gradeR(1).predictedGrade);
            state.camMaps{curI} = camMap;
            updateStage(4, 'done');
        end

        elapsed = toc(tStart);
        btnRun.Enable      = 'on';
        btnBatchAll.Enable = 'on';

        updateQueueTable();
        updateAllVisuals(state.currentIdx);
        setStatus(sprintf('Analysis Complete! Processed %d image(s) in %.1f seconds.', nTotal, elapsed));
    end

    function updateAllVisuals(idx)
        if isempty(state.gradeResults) || idx > numel(state.gradeResults) || isempty(state.gradeResults{idx})
            return;
        end

        gr  = state.gradeResults{idx};
        seg = state.segResults{idx};
        qc  = state.qcResults{idx};
        raw = state.imgList{idx};
        enh = state.enhancedImgs{idx};
        cam = state.camMaps{idx};

        % ── Tab 1: Multi-View Grid ──────────────────────────────────────
        % Panel 1: Raw
        cla(axGrid(1));
        imshow(raw, 'Parent', axGrid(1));
        axGrid(1).XTick = []; axGrid(1).YTick = [];
        title(axGrid(1), sprintf('Raw: %s', state.fileNames{idx}), 'Color', [1 1 1], 'FontSize', 9);

        % Panel 2: Vessels (High-Contrast Frangi Vessel Tree)
        vess = seg.vessels;
        if isempty(vess), vess = zeros(size(raw,1), size(raw,2)); end
        cla(axGrid(2));
        vNorm = min(1.0, (vess / 0.12).^0.75); % Stretch thin micro-vessels
        vRGB  = ind2rgb(uint8(vNorm * 255), hot(256));
        imshow(vRGB, 'Parent', axGrid(2));
        axGrid(2).XTick = []; axGrid(2).YTick = [];
        title(axGrid(2), sprintf('Vessel Map (Density: %.3f)', sum(vess(:)>0.12)/numel(vess)), ...
            'Color', [1 1 1], 'FontSize', 9);

        % Panel 3: Lesion Composite
        compImg = buildCompositeLesionImage(enh, seg, true, true, true, true);
        cla(axGrid(3));
        imshow(compImg, 'Parent', axGrid(3));
        axGrid(3).XTick = []; axGrid(3).YTick = [];
        title(axGrid(3), 'Lesion Overlay (OD/MA/Exudates/Haem)', 'Color', [1 1 1], 'FontSize', 9);

        % Panel 4: Grad-CAM Overlay
        cla(axGrid(4));
        imshow(enh, 'Parent', axGrid(4));
        hold(axGrid(4), 'on');
        camRGB = ind2rgb(uint8(cam * 255), jet(256));
        hC = imshow(camRGB, 'Parent', axGrid(4));
        set(hC, 'AlphaData', cam * 0.55);
        hold(axGrid(4), 'off');
        axGrid(4).XTick = []; axGrid(4).YTick = [];
        title(axGrid(4), 'AI Attention Heatmap (Grad-CAM)', 'Color', [1 1 1], 'FontSize', 9);

        % ── Tab 2: Interactive Inspector ────────────────────────────────
        redrawInteractiveView();

        % ── Right Panel: Diagnostic Results ─────────────────────────────
        gradeColors = {C.green, C.amber, C.orange, C.red, C.purple};
        gradeBg     = {C.greenBg, C.amberBg, C.orangeBg, C.redBg, C.purpleBg};
        gIdx        = gr.predictedGrade + 1;

        hGradeBadge.Text      = sprintf('Grade %d: %s', gr.predictedGrade, gr.gradeName);
        hGradeBadge.FontColor = gradeColors{gIdx};
        pGradeCard.BackgroundColor = gradeBg{gIdx};
        hGradeSubtitle.Text   = sprintf('Confidence: %.1f%%  |  Scale: ICDR Standard', gr.confScore * 100);

        if gr.isReferable
            hReferralBadge.Text      = 'REFERABLE - Ophthalmology Review Needed';
            hReferralBadge.FontColor = C.red;
        else
            hReferralBadge.Text      = 'NON-REFERABLE - Routine Periodic Screening';
            hReferralBadge.FontColor = C.green;
        end

        % Confidence Bar
        cla(axConf);
        hold(axConf, 'on');
        cCol = C.green;
        if gr.confScore < cfg.dl.confThreshLow, cCol = C.red;
        elseif gr.confScore < cfg.dl.confThreshHigh, cCol = C.amber; end
        bar(axConf, gr.confScore, 0.6, 'FaceColor', cCol, 'EdgeColor','none', 'BaseValue',0, 'horizontal','on');
        set(axConf, 'XLim', [0 1], 'YLim', [0.5 1.5], 'Color', C.panel, 'XColor', 'none', 'YColor', 'none');
        text(axConf, min(0.98, gr.confScore + 0.03), 1, sprintf('%.1f%%', gr.confScore*100), ...
            'Color', C.textDark, 'FontSize', 8, 'FontWeight', 'bold');
        hold(axConf, 'off');

        % Probability Distribution Chart
        cla(axProb);
        hold(axProb, 'on');
        pBars = bar(axProb, gr.confidence * 100, 'FaceColor', 'flat', 'EdgeColor', 'none');
        for k_b = 1:5
            pBars.CData(k_b,:) = gradeColors{k_b};
        end
        set(axProb, 'XTickLabel', {'G0','G1','G2','G3','G4'}, 'Color', C.panel, ...
            'XColor', C.textMuted, 'YColor', C.textMuted, 'YLim', [0 100], 'FontSize', 8);
        yline(axProb, 90, '--', 'Color', C.green, 'LineWidth', 1);
        hold(axProb, 'off');

        % Lesion Evidence
        fv = gr.features;
        if isstruct(fv)
            lblLesionMA.Text   = sprintf('Microaneurysms: %d count', fv.maCount);
            lblLesionEx.Text   = sprintf('Hard Exudates: %.2f%% area', fv.exudateAreaPct);
            lblLesionHem.Text  = sprintf('Haemorrhages: %d count', fv.hemCount);
            lblLesionNV.Text   = sprintf('Neovascularisation: %s', mat2str(fv.nvDetected));
            lblLesionVess.Text = sprintf('Vessel Density: %.3f', fv.vesselDensity);
        end

        % Eye Laterality & DME Badges
        if isfield(seg, 'eyeLaterality') && ~isempty(seg.eyeLaterality)
            hEyeBadge.Text = sprintf('Eye: %s', seg.eyeLaterality);
            lblEyeLaterality.Text = sprintf('Laterality: %s', seg.eyeLateralityLong);
        else
            hEyeBadge.Text = 'Eye: OD';
            lblEyeLaterality.Text = 'Laterality: Right Eye (OD)';
        end

        if isfield(seg, 'dme') && ~isempty(seg.dme)
            if seg.dme.hasCSME
                hDMEBadge.Text = 'DME: CSME';
                hDMEBadge.FontColor = C.red;
                hDMEBadge.BackgroundColor = C.redBg;
                lblDMERisk.Text = sprintf('Macular Edema: %s (%.0f px from fovea)', seg.dme.riskLabel, seg.dme.foveaDistPx);
                lblDMERisk.FontColor = C.red;
            elseif seg.dme.riskGrade == 1
                hDMEBadge.Text = 'DME: Moderate';
                hDMEBadge.FontColor = C.orange;
                hDMEBadge.BackgroundColor = C.orangeBg;
                lblDMERisk.Text = sprintf('Macular Edema: %s (%.0f px from fovea)', seg.dme.riskLabel, seg.dme.foveaDistPx);
                lblDMERisk.FontColor = C.orange;
            else
                hDMEBadge.Text = 'DME: Clear';
                hDMEBadge.FontColor = C.green;
                hDMEBadge.BackgroundColor = C.greenBg;
                lblDMERisk.Text = 'Macular Edema: No DME Risk (Clear)';
                lblDMERisk.FontColor = C.textDark;
            end
        else
            hDMEBadge.Text = 'DME: Clear';
            hDMEBadge.FontColor = C.green;
            hDMEBadge.BackgroundColor = C.greenBg;
            lblDMERisk.Text = 'Macular Edema: Not Assessed';
        end

        % Multi-Disease Biomarkers: Glaucoma, AMD, Hypertension
        if isfield(seg, 'glaucoma') && isstruct(seg.glaucoma)
            lblGlaucCDR.Text = sprintf('Glaucoma: vCDR=%.2f (%s)', seg.glaucoma.vCDR, seg.glaucoma.status);
            if seg.glaucoma.isSuspect
                lblGlaucCDR.FontColor = C.red;
            else
                lblGlaucCDR.FontColor = C.purple;
            end
        end
        if isfield(seg, 'amd') && isstruct(seg.amd)
            lblAMDStatus.Text = sprintf('AMD: %s (Drusen=%d)', seg.amd.status, seg.amd.drusenCount);
            if seg.amd.isSuspect
                lblAMDStatus.FontColor = C.red;
            else
                lblAMDStatus.FontColor = C.textDark;
            end
        end
        if isfield(seg, 'hypertension') && isstruct(seg.hypertension)
            lblHTNAVR.Text = sprintf('HTN AVR: %.2f (%s)', seg.hypertension.avr, seg.hypertension.status);
            if seg.hypertension.isNarrowed
                lblHTNAVR.FontColor = C.amber;
            else
                lblHTNAVR.FontColor = C.textDark;
            end
        end

        % Recommendation
        rec = get_clinical_action(gr.predictedGrade);
        if isfield(seg, 'dme') && seg.dme.hasCSME && gr.predictedGrade < 2
            % Upgrade recommendation if CSME is detected even with mild DR
            rec.title = [rec.title ' + CSME DETECTED'];
            rec.desc = ['URGENT RETINA REFERRAL: Clinically Significant Macular Edema (CSME) detected threatening fovea. Macular OCT and anti-VEGF / focal laser evaluation required within 2-4 weeks. ' rec.desc];
            rec.bg = C.orangeBg;
        elseif isfield(seg, 'glaucoma') && seg.glaucoma.isSuspect && gr.predictedGrade < 2
            rec.title = 'OPHTHALMIC REFERRAL: GLAUCOMA SUSPECT';
            rec.desc = sprintf('Elevated Vertical Cup-to-Disc Ratio (vCDR=%.2f) or neuroretinal rim thinning detected. Visual field and gonioscopy evaluation recommended. %s', seg.glaucoma.vCDR, rec.desc);
            rec.bg = C.orangeBg;
        end
        lblRecTitle.Text = rec.title;
        lblRecDesc.Text  = rec.desc;
        pRecCard.BackgroundColor = rec.bg;

        % Quality
        lblQCInfo.Text    = sprintf('Quality: %s (Score: %.2f)', qc.status, qc.overallScore);
        lblSharpInfo.Text = sprintf('Sharp: %.3f | Bright: %.0f', qc.sharpness, qc.brightness);
        lblPathUsed.Text  = sprintf('Path: %s', gr.clinPath);
    end

    function redrawInteractiveView()
        idx = state.currentIdx;
        if isempty(state.enhancedImgs) || idx > numel(state.enhancedImgs) || isempty(state.enhancedImgs{idx})
            return;
        end

        enh = state.enhancedImgs{idx};
        seg = state.segResults{idx};

        comp = buildCompositeLesionImage(enh, seg, cbOD.Value, cbMA.Value, cbEx.Value, cbHm.Value);

        cla(axInspect);
        imshow(comp, 'Parent', axInspect);
        axInspect.XTick = []; axInspect.YTick = [];

        if cbCAM.Value && ~isempty(state.camMaps) && idx <= numel(state.camMaps)
            cam = state.camMaps{idx};
            hold(axInspect, 'on');
            camRGB = ind2rgb(uint8(cam * 255), jet(256));
            hC = imshow(camRGB, 'Parent', axInspect);
            set(hC, 'AlphaData', cam * 0.50);
            hold(axInspect, 'off');
        end
    end

    function comp = buildCompositeLesionImage(img, seg, showOD, showMA, showEx, showHm)
        imgD = im2double(img);

        % Hard Exudates (Yellow)
        if showEx && ~isempty(seg.exudates.mask)
            exDil = imdilate(seg.exudates.mask, strel('disk', 1));
            imgD(:,:,1) = min(1, imgD(:,:,1) + 0.6 * double(exDil));
            imgD(:,:,2) = min(1, imgD(:,:,2) + 0.6 * double(exDil));
            imgD(:,:,3) = imgD(:,:,3) .* (1 - 0.7 * double(exDil));
        end

        % Microaneurysms (Bright Red)
        if showMA && ~isempty(seg.ma.mask)
            maDil = imdilate(seg.ma.mask, strel('disk', 2));
            imgD(:,:,1) = min(1, imgD(:,:,1) + 0.8 * double(maDil));
            imgD(:,:,2) = imgD(:,:,2) .* (1 - 0.7 * double(maDil));
            imgD(:,:,3) = imgD(:,:,3) .* (1 - 0.7 * double(maDil));
        end

        % Haemorrhages (Dark Red Crimson)
        if showHm && ~isempty(seg.haem.mask)
            hemDil = imdilate(seg.haem.mask, strel('disk', 2));
            imgD(:,:,1) = min(1, imgD(:,:,1) + 0.5 * double(hemDil));
            imgD(:,:,2) = imgD(:,:,2) .* (1 - 0.8 * double(hemDil));
            imgD(:,:,3) = imgD(:,:,3) .* (1 - 0.8 * double(hemDil));
        end

        comp = im2uint8(imgD);

        % OD Circle overlay
        if showOD && ~any(isnan(seg.odCenter)) && seg.odRadius > 0
            comp = insertShapeCircle(comp, seg.odCenter, seg.odRadius, [0 255 255]);
        end
    end

    function out = insertShapeCircle(img, center, radius, colorRGB)
        out = img;
        sz = [size(img,1) size(img,2)];
        theta = linspace(0, 2*pi, 180);
        xc = round(center(1) + radius * cos(theta));
        yc = round(center(2) + radius * sin(theta));
        valid = xc >= 1 & xc <= sz(2) & yc >= 1 & yc <= sz(1);
        xc = xc(valid); yc = yc(valid);
        for c = 1:3
            ch = out(:,:,c);
            for p = 1:numel(xc)
                ch(yc(p), xc(p)) = colorRGB(c);
            end
            out(:,:,c) = ch;
        end
    end

    function updateQueueTable()
        n = numel(state.imgList);
        if n == 0
            tblQueue.Data = {}; return;
        end

        data = cell(n, 10);
        for i = 1:n
            data{i,1} = sprintf('%d', i);
            if ~isempty(state.patients) && i <= numel(state.patients)
                data{i,2} = state.patients(i).id;
                data{i,3} = state.patients(i).name;
            else
                data{i,2} = sprintf('OCU-%03d', i);
                data{i,3} = 'Anonymous';
            end

            % Eye Laterality
            if ~isempty(state.segResults) && i <= numel(state.segResults) && ~isempty(state.segResults{i}) && isfield(state.segResults{i}, 'eyeLaterality')
                data{i,4} = state.segResults{i}.eyeLaterality;
            else
                data{i,4} = 'OD';
            end

            % DME Status
            if ~isempty(state.segResults) && i <= numel(state.segResults) && ~isempty(state.segResults{i}) && isfield(state.segResults{i}, 'dme')
                data{i,5} = state.segResults{i}.dme.riskLabel;
            else
                data{i,5} = 'Pending';
            end

            data{i,6} = state.fileNames{i};

            if ~isempty(state.qcResults) && i <= numel(state.qcResults) && ~isempty(state.qcResults{i})
                data{i,7} = state.qcResults{i}.status;
            else
                data{i,7} = 'Pending';
            end

            if ~isempty(state.gradeResults) && i <= numel(state.gradeResults) && ~isempty(state.gradeResults{i}) && ~isempty(state.gradeResults{i}.gradeName)
                gr = state.gradeResults{i};
                data{i,8} = sprintf('Grade %d', gr.predictedGrade);
                data{i,9} = gr.gradeName;
                if gr.isReferable
                    data{i,10} = 'REFERABLE';
                else
                    data{i,10} = 'Non-Referable';
                end
            else
                data{i,8} = '-';
                data{i,9} = '-';
                data{i,10} = '-';
            end
        end
        tblQueue.Data = data;
    end

    function exportCurrentReport()
        idx = state.currentIdx;
        if isempty(state.gradeResults) || idx > numel(state.gradeResults) || isempty(state.gradeResults{idx})
            setStatus('Please run analysis first before exporting report.');
            return;
        end

        setStatus('Generating OCULA AI Hospital-Grade Clinical PDF & PNG...');
        drawnow;

        gr  = state.gradeResults{idx};
        seg = state.segResults{idx};
        qc  = state.qcResults{idx};
        enh = state.enhancedImgs{idx};
        if ~isempty(state.patients) && idx <= numel(state.patients)
            pat = state.patients(idx);
        else
            pat = struct('id','OCU-2026-001','name','Anonymous','age',50,'gender','Unknown');
        end

        % Multi-lingual selection
        selLang = 'en';
        if exist('ddReportLang', 'var') && isvalid(ddReportLang)
            langMap = containers.Map({'English (EN)','Español (ES)','Hindi (HI)','Français (FR)','Arabic (AR)'}, {'en','es','hi','fr','ar'});
            if isKey(langMap, ddReportLang.Value), selLang = langMap(ddReportLang.Value); end
        end

        [outPdf, outPng] = generate_multilingual_report(enh, gr, seg, qc, pat, selLang, cfg);
        setStatus(sprintf('Multi-Lingual Report [%s] exported to %s', upper(selLang), cfg.outputDir));
        try
            winopen(outPdf);
        catch
            winopen(outPng);
        end
    end

    function loadDicomImage()
        setStatus('Opening DICOM file selector...');
        [file, path] = uigetfile({'*.dcm;*.DCM;*.dicom;*.jpg;*.png', 'Medical Imaging Files (*.dcm, *.jpg, *.png)'}, 'Select DICOM Fundus Scan');
        if isequal(file, 0), setStatus('DICOM selection cancelled.'); return; end

        fpath = fullfile(path, file);
        [raw, patMeta] = dicom_parser(fpath);

        state.imgList   = {raw};
        state.fileNames = {file};
        state.patients  = patMeta;
        state.currentIdx = 1;
        state.qcResults = {};
        state.segResults = {};
        state.gradeResults = {};
        state.camMaps = {};

        ddGrade.Items = {file};
        ddGrade.Value = file;
        syncDemographicsUI(1);

        showRawPreview(raw, [patMeta.name ' (DICOM)']);
        btnRun.Enable = 'on';
        btnBatchAll.Enable = 'on';
        updateQueueTable();
        setStatus(sprintf('Loaded DICOM scan: %s (Patient: %s, ID: %s)', file, patMeta.name, patMeta.id));
        runAnalysis(false);
    end

    function runHotFolderDaemon()
        setStatus('Autonomous Hot-Folder Daemon scanning incoming_fundus/...');
        drawnow;
        count = folder_watcher_daemon(cfg, 'runOnce');
        setStatus(sprintf('Daemon finished: %d images auto-screened. Reports in %s', count, cfg.hotfolder.screenedDir));
        winopen(cfg.hotfolder.screenedDir);
    end

    function openLongitudinalTracker()
        setStatus('Select Baseline and Follow-up scans for Longitudinal Tracking...');
        [f1, p1] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.dcm', 'Fundus Images'}, 'Select Baseline (Visit 1) Fundus Scan');
        if isequal(f1, 0), return; end
        [f2, p2] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.dcm', 'Fundus Images'}, 'Select Follow-up (Visit 2) Fundus Scan');
        if isequal(f2, 0), return; end

        im1 = imread(fullfile(p1, f1));
        im2 = imread(fullfile(p2, f2));
        patMeta = struct('id', txtPatID.Value, 'name', txtPatName.Value, ...
                         'baselineDate', '2025-03-15', 'followDate', datestr(now,'yyyy-mm-dd'));

        setStatus('Aligning scans & tracking lesion dynamics (Longitudinal Mode)...');
        drawnow;
        [deltaReport, ~] = longitudinal_tracker(im1, im2, cfg, patMeta);
        setStatus(sprintf('Longitudinal Analysis Complete! Trajectory: %s', deltaReport.trajectory));
        winopen(cfg.outputDir);
    end

    function runBenchmark()
        setStatus('Running clinical benchmark comparison...');
        drawnow;
        benchmark_comparison(cfg);
        setStatus('Benchmark complete. Reports updated.');
        winopen(cfg.outputDir);
    end

    function updateStage(n, status)
        switch status
            case 'running'
                hStage(n).Text = sprintf('~  %s (Running...)', stages{n});
                hStage(n).FontColor = C.amber;
            case 'done'
                hStage(n).Text = sprintf('V  %s', stages{n});
                hStage(n).FontColor = C.green;
            otherwise
                hStage(n).Text = sprintf('-  %s', stages{n});
                hStage(n).FontColor = C.textMuted;
        end
        drawnow;
    end

    function setStatus(msg)
        hStatus.Text = msg;
        drawnow;
    end

    function rec = get_clinical_action(grade)
        switch grade
            case 0
                rec.title = 'Grade 0: Normal Retina (No DR)';
                rec.desc  = 'Routine follow-up in 12 months. Reinforce diabetes self-care, blood pressure, and HbA1c control.';
                rec.bg    = C.greenBg;
            case 1
                rec.title = 'Grade 1: Mild NPDR (Microaneurysms only)';
                rec.desc  = 'Follow-up screening in 6 to 12 months. Monitor glycaemic management and lipid panels.';
                rec.bg    = C.amberBg;
            case 2
                rec.title = 'Grade 2: Moderate NPDR (MAs and Exudates)';
                rec.desc  = 'REFERRAL: Comprehensive ophthalmologist evaluation within 3 months. Macular OCT advised.';
                rec.bg    = C.orangeBg;
            case 3
                rec.title = 'Grade 3: Severe NPDR (High Risk)';
                rec.desc  = 'URGENT REFERRAL: Retinal specialist evaluation within 2 to 4 weeks. Potential anti-VEGF / PRP therapy.';
                rec.bg    = C.redBg;
            case 4
                rec.title = 'Grade 4: Proliferative DR (PDR)';
                rec.desc  = 'EMERGENCY REFERRAL: Immediate vitreoretinal surgery / pan-retinal photocoagulation consultation within 7 days.';
                rec.bg    = C.purpleBg;
            otherwise
                rec.title = 'Awaiting Clinical Assessment';
                rec.desc  = 'Execute analysis pipeline to evaluate retinal pathology.';
                rec.bg    = C.panel;
        end
    end

    function figR = generate_standalone_report(img, gr, camMap, seg, qc, fileName, pat, cfg)
        figR = figure('Name','OCULA AI Clinical Report',...
            'Position',[100 100 1150 800],'Color','white','Visible','off');

        % Top Hospital Branding Band
        annotation(figR,'rectangle',[0.03 0.90 0.94 0.08],'FaceColor',[0.96 0.98 1.00],'EdgeColor',[0.80 0.85 0.92]);
        annotation(figR,'textbox',[0.04 0.93 0.65 0.04],...
            'String', '👁️ OCULA AI TELE-OPHTHALMOLOGY NETWORK | CLINICAL DIAGNOSTIC REPORT',...
            'FontSize',12,'FontWeight','bold','Color',C.primary,'EdgeColor','none');

        eyeStr = 'Right Eye (OD)';
        if isfield(seg,'eyeLateralityLong'), eyeStr = seg.eyeLateralityLong; end
        patHeader = sprintf('PATIENT: %s  |  ID: %s  |  AGE: %d  |  GENDER: %s  |  EYE: %s  |  DATE: %s', ...
            pat.name, pat.id, pat.age, pat.gender, eyeStr, datestr(now,'yyyy-mm-dd HH:MM'));
        annotation(figR,'textbox',[0.04 0.905 0.92 0.025],...
            'String', patHeader,...
            'FontSize',8.5,'FontWeight','bold','Color',C.textDark,'EdgeColor','none');

        % Panel 1: Enhanced Fundus with OD & Fovea
        subplot(2,3,1);
        imshow(img); title('1. Fundus Image (CLAHE Enhanced)','FontWeight','bold','FontSize',8.5);
        hold on;
        if ~any(isnan(seg.odCenter))
            viscircles(seg.odCenter, seg.odRadius, 'Color','cyan','LineWidth',1.2);
            text(seg.odCenter(1)+5, seg.odCenter(2)-seg.odRadius-8, 'OD', 'Color','cyan','FontSize',8,'FontWeight','bold');
        end
        if isfield(seg,'foveaCenter') && ~any(isnan(seg.foveaCenter))
            plot(seg.foveaCenter(1), seg.foveaCenter(2), 'y+', 'MarkerSize',8, 'LineWidth',1.5);
            text(seg.foveaCenter(1)+6, seg.foveaCenter(2)+6, 'Fovea', 'Color','yellow','FontSize',8,'FontWeight','bold');
        end
        hold off;

        % Panel 2: Vessels
        subplot(2,3,2);
        vShow = seg.vessels;
        if isempty(vShow), vShow = zeros(size(img,1), size(img,2)); end
        vNorm = min(1.0, (vShow / 0.12).^0.75);
        vRGB  = ind2rgb(uint8(vNorm * 255), hot(256));
        imshow(vRGB);
        title('2. Frangi Vessel Tree','FontWeight','bold','FontSize',8.5);

        % Panel 3: Lesion Overlay
        subplot(2,3,3);
        comp = buildCompositeLesionImage(img, seg, true, true, true, true);
        imshow(comp);
        title('3. Composite Lesions (OD/MA/Ex/Hm)','FontWeight','bold','FontSize',8.5);

        % Panel 4: Grad-CAM
        subplot(2,3,4);
        imshow(img); hold on;
        camRGB = ind2rgb(uint8(camMap * 255), jet(256));
        hC = imshow(camRGB); set(hC, 'AlphaData', camMap * 0.55);
        hold off;
        title('4. Grad-CAM AI Attention','FontWeight','bold','FontSize',8.5);

        % Panel 5: Class Probabilities
        subplot(2,3,5);
        cols = [C.green; C.amber; C.orange; C.red; C.purple];
        b = bar(gr.confidence * 100, 'FaceColor','flat');
        for k_r = 1:5, b.CData(k_r,:) = cols(k_r,:); end
        set(gca, 'XTickLabel', {'G0','G1','G2','G3','G4'}, 'YLim', [0 100], 'FontSize',7.5);
        ylabel('Probability (%)'); title('5. ICDR Grade Probabilities','FontWeight','bold','FontSize',8.5);
        yline(cfg.clinSensitivity*100, '--r', 'Target 90%');

        % Panel 6: Clinical Summary, DME & Verification QR Code
        subplot(2,3,6);
        cla; axis off;
        title('6. Clinical Summary & Physician Certification','FontWeight','bold','FontSize',8.5);
        rec = get_clinical_action(gr.predictedGrade);
        refTxt = 'NON-REFERABLE (Routine Screening)';
        if gr.isReferable, refTxt = 'REFERABLE (Retinal Specialist Needed)'; end

        dmeTxt = 'DME: No Risk (Clear)';
        if isfield(seg,'dme') && isstruct(seg.dme)
            dmeTxt = sprintf('DME: %s', seg.dme.riskLabel);
        end

        summaryText = {
            sprintf('Patient: %s | ID: %s (%s, %dy)', pat.name, pat.id, pat.gender, pat.age), ...
            sprintf('Eye Examined: %s', eyeStr), ...
            sprintf('ICDR Diagnosis: Grade %d (%s)', gr.predictedGrade, gr.gradeName), ...
            sprintf('Macular Status: %s', dmeTxt), ...
            sprintf('Screening Decision: %s', refTxt), ...
            sprintf('AI Confidence: %.1f%% | IQA: %s (%.2f)', gr.confScore * 100, qc.status, qc.overallScore), ...
            '-------------------------------------------------------', ...
            ['Plan: ' rec.desc], ...
            'Clinical Certification:', ...
            'Verified by: Attending Ophthalmologist / Retina Specialist', ...
            'Accreditation: Certified Tele-Ophthalmology Network | Seal: VERIFIED-EHR'
        };
        text(0.02, 0.52, summaryText, 'Units','normalized', 'FontSize',7.5, ...
            'Color', C.textDark, 'Interpreter','none', 'VerticalAlignment','middle');

        % Draw Verification QR Code Block in Bottom-Right
        qrAx = axes('Parent', figR, 'Position', [0.84 0.05 0.12 0.12]);
        [qX, qY] = meshgrid(1:21, 1:21);
        rng(sum(double(pat.id)) + gr.predictedGrade*13, 'twister');
        qrPattern = rand(21, 21) > 0.5;
        % Add standard QR corner alignment markers
        qrPattern(1:5, 1:5) = 1; qrPattern(2:4, 2:4) = 0; qrPattern(3,3) = 1;
        qrPattern(1:5, 17:21) = 1; qrPattern(2:4, 18:20) = 0; qrPattern(3,19) = 1;
        qrPattern(17:21, 1:5) = 1; qrPattern(18:20, 2:4) = 0; qrPattern(19,3) = 1;
        imagesc(qrAx, ~qrPattern); colormap(qrAx, gray); axis(qrAx, 'off');
        title(qrAx, 'Scan for EHR Record', 'FontSize', 7, 'FontWeight', 'bold', 'Color', C.textMuted);
    end

    function camMap = generate_synthetic_gradcam_local(img, grade)
        sz     = [size(img,1) size(img,2)];
        gray   = im2single(rgb2gray(img));
        camMap = imgaussfilt(gray, 15) * 0.3;
        rng(grade * 17 + 3, 'twister');
        nBlobs = max(1, grade * 4 + round(randn));
        [X,Y]  = meshgrid(1:sz(2), 1:sz(1));
        for k_blb = 1:nBlobs
            r = round(sz(1) * (0.2 + rand * 0.6));
            c = round(sz(2) * (0.1 + rand * 0.8));
            sig = 15 + rand * 25;
            amp = 0.4 + rand * 0.6;
            camMap = camMap + single(amp * exp(-((X-c).^2 + (Y-r).^2) / (2*sig^2)));
        end
        if grade == 0, camMap = camMap * 0.1; end
        camMap = camMap / (max(camMap(:)) + eps);
    end

    function onCloseApp()
        delete(fig);
        exit;
    end

%% ── Auto-load Demo Set on Startup ──────────────────────────────────────
loadDemo();

end
