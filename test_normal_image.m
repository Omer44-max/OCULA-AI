fid = fopen('C:/Users/ASUS/.gemini/antigravity/scratch/DR_Screening_System/result.txt', 'w');
try
    cfg = dr_config();
    img = imread('C:/Users/ASUS/Downloads/Normal-fundus-LRG.jpg');
    [enh, qc] = batch_quality_pipeline({img}, cfg);
    seg = batch_segment_retina(enh, cfg);
    [gr, nf] = batch_grade_dr(enh, seg, cfg);
    fprintf(fid, 'E2E_RESULT: Grade=%d (%s), Conf=%.1f%%, Referable=%d, Eye=%s (%s), DME=%s, ExudateArea=%.2f%%, MA=%d, Hem=%d\n', ...
        gr.predictedGrade, gr.gradeName, gr.confScore*100, gr.isReferable, ...
        seg.eyeLaterality, seg.eyeLateralityLong, seg.dme.riskLabel, ...
        seg.exudates.area_frac*100, seg.ma.count, seg.haem.count);
catch ME
    fprintf(fid, 'ERROR: %s\n', ME.message);
    for k = 1:length(ME.stack)
        fprintf(fid, '  in %s at line %d\n', ME.stack(k).file, ME.stack(k).line);
    end
end
fclose(fid);
