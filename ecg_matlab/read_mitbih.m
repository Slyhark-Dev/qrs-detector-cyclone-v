function [signal, fs, gain, baseline, n_samples] = read_mitbih(record)
% READ_MITBIH - Reads MIT-BIH files in format 212 (12-bit packed)
%
% Usage:
%   [signal, fs, gain, baseline, n_samples] = read_mitbih('100')
%
% Input:
%   record - string with record number (e.g., '100', '207')
%
% Outputs:
%   signal    - matrix [n_samples x n_channels] with ECG signal in mV
%   fs        - sampling frequency (Hz)
%   gain      - ADC gain (units/mV)
%   baseline  - ADC baseline
%   n_samples - total number of samples per channel
%
% Project: Cardiac arrhythmia detection system - FPGA DE1-SoC
% Universidad Tecnologica del Peru (UTP)
% Format: MIT-BIH uses format 212 (2 samples in 3 bytes, 12 bits each)

    %% 1. Read header file (.hea)
    hea_file = [record '.hea'];
    fid = fopen(hea_file, 'r');
    if fid == -1
        error('File not found: %s', hea_file);
    end

    % First line: name n_channels fs n_samples
    line1 = fgetl(fid);
    parts = strsplit(line1);
    n_channels = str2double(parts{2});
    fs = str2double(parts{3});
    n_samples = str2double(parts{4});

    % Read channel info
    gain = zeros(1, n_channels);
    baseline = zeros(1, n_channels);

    for ch = 1:n_channels
        ch_line = fgetl(fid);
        ch_parts = strsplit(ch_line);
        % Field 3: gain (format may be "200(0)/mV" or just "200")
        gain_field = ch_parts{3};
        nums = regexp(gain_field, '^(\d+)', 'tokens');
        if ~isempty(nums)
            gain(ch) = str2double(nums{1}{1});
        else
            gain(ch) = 200; % MIT-BIH default
        end
        % Field 5: baseline
        if length(ch_parts) >= 5
            baseline(ch) = str2double(ch_parts{5});
        else
            baseline(ch) = 0;
        end
    end
    fclose(fid);

    %% 2. Read data file (.dat) in format 212
    dat_file = [record '.dat'];
    fid = fopen(dat_file, 'r');
    if fid == -1
        error('File not found: %s', dat_file);
    end

    bytes = fread(fid, inf, 'uint8');
    fclose(fid);

    % Format 212: every 3 bytes contain 2 samples of 12 bits
    % Byte0: bits 0-7 of sample1
    % Byte1: bits 8-11 of sample1 (low nibble) + bits 8-11 of sample2 (high nibble)
    % Byte2: bits 0-7 of sample2
    n_bytes = length(bytes);
    n_pairs = floor(n_bytes / 3);

    raw_data = zeros(n_pairs * 2, 1);

    for i = 1:n_pairs
        idx = (i-1)*3;
        b0 = bytes(idx + 1);
        b1 = bytes(idx + 2);
        b2 = bytes(idx + 3);

        % Sample 1: full byte0 + low nibble of byte1
        s1 = b0 + bitand(b1, 15) * 256;
        % Sample 2: high nibble of byte1 + full byte2
        s2 = b2 + bitshift(bitand(b1, 240), 4);

        % Convert from unsigned 12-bit to signed (two's complement)
        if s1 >= 2048
            s1 = s1 - 4096;
        end
        if s2 >= 2048
            s2 = s2 - 4096;
        end

        raw_data((i-1)*2 + 1) = s1;
        raw_data((i-1)*2 + 2) = s2;
    end

    %% 3. Reshape into channels and convert to mV
    samples_per_channel = floor(length(raw_data) / n_channels);
    if n_samples > 0
        samples_per_channel = min(samples_per_channel, n_samples);
    end

    signal = zeros(samples_per_channel, n_channels);
    for ch = 1:n_channels
        raw_ch = raw_data(ch:n_channels:n_channels*samples_per_channel);
        signal(:, ch) = (raw_ch - baseline(ch)) / gain(ch);
    end

    n_samples = samples_per_channel;

    %% 4. Display info
    fprintf('Record: %s\n', record);
    fprintf('Sampling frequency: %d Hz\n', fs);
    fprintf('Channels: %d\n', n_channels);
    fprintf('Samples per channel: %d\n', n_samples);
    fprintf('Duration: %.1f seconds (%.1f minutes)\n', ...
            n_samples/fs, n_samples/fs/60);
    fprintf('Gain: %d units/mV\n', gain(1));

end
