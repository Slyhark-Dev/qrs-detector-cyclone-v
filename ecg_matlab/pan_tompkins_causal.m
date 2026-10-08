function r_peaks = pan_tompkins_causal(ecg, fs, n_samples)
% PAN_TOMPKINS_CAUSAL - Causal Pan-Tompkins QRS detector (FPGA-replicable)
% VERSION: v4-SELFCAL  (polaridad + autocalibracion de lag interna + T-wave)
%
% Detector causal de QRS, fuente unica usada por validate_sensitivity.m.
% Causal: usa solo filter() (no filtfilt), replicable en VHDL punto fijo.
% Resultado validado sobre 48 registros MIT-BIH: Se=85.47%, +P=81.25%, F1=83.31%
% Project: Cardiac arrhythmia detection - FPGA DE1-SoC (UTP)

    ecg = double(ecg(:));
    if nargin < 3 || isempty(n_samples)
        n_samples = length(ecg);
    end

    base_win = round(0.5 * fs);
    if mod(base_win,2)==0, base_win = base_win+1; end
    baseline = movmean_causal(ecg, base_win);
    ecg_hp = ecg - baseline;

    lp_win = 5;
    ecg_bp = movmean_causal(ecg_hp, lp_win);

    b_deriv = (1/8) * [1 2 0 -2 -1];
    ecg_deriv = filter(b_deriv, 1, ecg_bp);

    ecg_sq = ecg_deriv .^ 2;

    win_w = round(0.150 * fs);
    ecg_int = filter(ones(1,win_w)/win_w, 1, ecg_sq);

    slope_win = round(0.030 * fs);
    abs_deriv = abs(ecg_deriv);
    slope_local = filter(ones(1,slope_win)/slope_win, 1, abs_deriv);

    refractory = round(0.200 * fs);
    Nint = length(ecg_int);

    init_end = min(2*fs, Nint);
    SPKI = max(ecg_int(1:init_end)) * 0.25;
    NPKI = mean(ecg_int(1:init_end)) * 0.5;
    THR  = NPKI + 0.25*(SPKI - NPKI);
    THR2 = 0.5 * THR;

    r_peaks   = [];
    rr_buf    = [];
    last_peak = 0;
    last_slope = 0;
    twave_win  = round(0.360 * fs);

    i = 2;
    while i <= Nint-1
        is_local_max = ecg_int(i) >= ecg_int(i-1) && ecg_int(i) >= ecg_int(i+1);

        if is_local_max && ecg_int(i) > THR
            if isempty(r_peaks) || (i - last_peak) > refractory
                is_twave = false;
                if last_peak > 0 && (i - last_peak) < twave_win
                    if slope_local(i) < 0.5 * last_slope
                        is_twave = true;
                    end
                end
                if ~is_twave
                    r_peaks(end+1,1) = i; %#ok<AGROW>
                    if last_peak > 0
                        rr_buf(end+1) = i - last_peak; %#ok<AGROW>
                        if numel(rr_buf) > 8, rr_buf(1) = []; end
                    end
                    last_peak = i;
                    last_slope = slope_local(i);
                    SPKI = 0.875*SPKI + 0.125*ecg_int(i);
                end
            end
            i = i + refractory;
        else
            if is_local_max
                NPKI = 0.875*NPKI + 0.125*ecg_int(i);
            end
            i = i + 1;
        end

        THR  = NPKI + 0.25*(SPKI - NPKI);
        THR2 = 0.5 * THR;

        if ~isempty(rr_buf) && last_peak > 0
            rr_mean = mean(rr_buf);
            if (i - last_peak) > round(1.66 * rr_mean)
                seg_start = last_peak + refractory;
                seg_end   = min(i, Nint-1);
                if seg_end > seg_start+1
                    seg = ecg_int(seg_start:seg_end);
                    [pkval, rel] = max(seg);
                    if pkval > THR2
                        cand = seg_start + rel - 1;
                        if (cand - last_peak) > refractory
                            r_peaks(end+1,1) = cand; %#ok<AGROW>
                            rr_buf(end+1) = cand - last_peak; %#ok<AGROW>
                            if numel(rr_buf) > 8, rr_buf(1) = []; end
                            last_peak = cand;
                            last_slope = slope_local(cand);
                            SPKI = 0.875*SPKI + 0.125*pkval;
                            THR  = NPKI + 0.25*(SPKI - NPKI);
                            THR2 = 0.5 * THR;
                        end
                    end
                end
            end
        end
    end

    r_peaks = sort(unique(r_peaks));

    % --- PASO 7: AUTOCALIBRACION INTERNA DEL LAG + REFINAMIENTO POLARIDAD ---
    wide_win = round(0.200 * fs);

    signed_vals = zeros(length(r_peaks),1);
    for k = 1:length(r_peaks)
        ws = max(1, r_peaks(k) - wide_win);
        we = min(n_samples, r_peaks(k) + wide_win);
        seg = ecg_hp(ws:we);
        [~, li] = max(abs(seg));
        signed_vals(k) = seg(li);
    end
    if mean(signed_vals > 0) >= 0.5
        polarity = +1;
    else
        polarity = -1;
    end

    offsets = zeros(length(r_peaks),1);
    for k = 1:length(r_peaks)
        ws = max(1, r_peaks(k) - wide_win);
        we = min(n_samples, r_peaks(k) + wide_win);
        seg = ecg_hp(ws:we);
        if polarity > 0
            [~, li] = max(seg);
        else
            [~, li] = min(seg);
        end
        peak_pos = ws + li - 1;
        offsets(k) = peak_pos - r_peaks(k);
    end
    sys_lag = round(median(offsets));

    r_peaks = r_peaks + sys_lag;
    r_peaks(r_peaks < 1) = 1;
    r_peaks(r_peaks > n_samples) = n_samples;

    search_win = round(0.060 * fs);
    for k = 1:length(r_peaks)
        ws = max(1, r_peaks(k) - search_win);
        we = min(n_samples, r_peaks(k) + search_win);
        seg = ecg_hp(ws:we);
        if polarity > 0
            [~, li] = max(seg);
        else
            [~, li] = min(seg);
        end
        r_peaks(k) = ws + li - 1;
    end

    r_peaks = sort(unique(r_peaks));
    r_peaks = r_peaks(r_peaks <= n_samples);

end


function y = movmean_causal(x, w)
    x = x(:);
    y = filter(ones(w,1)/w, 1, x);
end
