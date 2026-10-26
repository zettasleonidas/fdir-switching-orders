function fig = FDIR_Dialog_GUI(excel_filename)
% =========================================================================
% FUNCTION: FDIR_Dialog_GUI
% -------------------------------------------------------------------------
% Διαδραστικό παράθυρο (uifigure, ΟΧΙ App Designer .mlapp) που:
%   1) Αφήνει τον χρήστη να διαλέξει target_line από dropdown (11 επιλογές)
%      και εμφανίζει την οπτική αλυσίδα της γραμμής. Μετά την 1η
%      επιβεβαίωση, το dropdown/κουμπί γραμμής κλειδώνουν (μία γραμμή ανά
%      "συνεδρία" GUI).
%   2) Δύο συμπαγείς γραμμές, ΙΔΙΟΥ layout/ύψους, με dropdown(s) που
%      περιέχουν ΜΟΝΟ τα Segment-τύπου στοιχεία της γραμμής:
%        - "Μεμονωμένο σφάλμα (X)": ένα dropdown + κουμπί προσθήκης.
%        - "Σύνθετο σφάλμα (X-Y)": δύο dropdowns (Από/Έως, υποχρεωτικά
%          διαφορετικά) + κουμπί προσθήκης.
%      Οι καταχωρήσεις είναι ΣΩΡΕΥΤΙΚΕΣ (raw_input_faults) - το κουμπί
%      "Καθαρισμός όλων" (κάτω και από τα δύο) τις αδειάζει όλες μαζί.
%   3) Checkbox "verbose".
%   4) Κουμπί "Start" -> καλεί main(target_line, raw_input_faults, verbose)
%      και ανοίγει το πλήρες output σε ΞΕΧΩΡΙΣΤΟ παράθυρο (όχι στο ίδιο log).
%
% ΕΙΣΟΔΟΣ:
%   excel_filename : ΠΡΟΑΙΡΕΤΙΚΟ, default 'Database/Elements_Data.xlsx'
%
% ΕΞΟΔΟΣ:
%   fig : handle του uifigure
% =========================================================================

    if nargin < 1 || isempty(excel_filename)
        excel_filename = fullfile('Database', 'Elements_Data.xlsx');
    end

    topology_data = readtable(excel_filename, 'Sheet', 1);
    network_elements = readtable(excel_filename, 'Sheet', 2);
    var_names = topology_data.Properties.VariableNames;
    line_cols = var_names(startsWith(var_names, 'Line_'));

    % --- Κύριο παράθυρο (φόντο ίδιο με το προεπιλεγμένο του MATLAB) ---
    fig = uifigure('Name', 'FDIR - Διάλογος Χρήστη', 'Position', [100 30 780 780], ...
        'Color', [0.94 0.94 0.94]);

    setappdata(fig, 'excel_filename', excel_filename);
    setappdata(fig, 'topology_data', topology_data);
    setappdata(fig, 'network_elements', network_elements);
    setappdata(fig, 'line_cols', line_cols);
    setappdata(fig, 'target_line', '');
    setappdata(fig, 'raw_input_faults', {});
    setappdata(fig, 'verbose', false);

    % ================= ΕΝΟΤΗΤΑ 1: ΕΠΙΛΟΓΗ ΓΡΑΜΜΗΣ =================
    uilabel(fig, 'Text', '====== ΟΠΤΙΚΗ ΑΠΕΙΚΟΝΙΣΗ ΤΟΠΟΛΟΓΙΑΣ ======', ...
        'FontWeight', 'bold', 'FontColor', 'k', 'Position', [20 740 740 22], ...
        'HorizontalAlignment', 'center');

    uilabel(fig, 'Text', 'Ποια γραμμή θέλετε να εξετάσετε;', 'FontColor', 'k', ...
        'Position', [20 705 220 22]);

    dd = uidropdown(fig, 'Items', line_cols, 'Value', line_cols{1}, ...
        'Position', [250 705 150 22]);
    setappdata(fig, 'lineDropdown', dd);

    confirmBtn = uibutton(fig, 'Text', 'Επιβεβαίωση', 'Position', [410 705 130 22], ...
        'ButtonPushedFcn', @(btn, event) onConfirmLine(fig, dd));
    setappdata(fig, 'confirmBtn', confirmBtn);

    topoArea = uitextarea(fig, 'Position', [20 590 740 105], 'Editable', 'off', ...
        'FontColor', 'k', 'BackgroundColor', [1 1 1], 'FontName', 'Consolas');
    setappdata(fig, 'topoArea', topoArea);

    % ================= ΕΝΟΤΗΤΑ 2: ΕΠΙΛΟΓΗ ΣΦΑΛΜΑΤΩΝ (SEGMENTS ΜΟΝΟ) =====
    uilabel(fig, 'Text', '====== ΣΥΣΤΗΜΑ ΔΙΑΧΕΙΡΙΣΗΣ ΣΦΑΛΜΑΤΩΝ ======', ...
        'FontWeight', 'bold', 'FontColor', 'k', 'Position', [20 555 740 22], ...
        'HorizontalAlignment', 'center');

    % --- Μεμονωμένο σφάλμα (X): μία συμπαγής γραμμή - ίδιο layout/ύψος
    %     με τη γραμμή του σύνθετου σφάλματος από κάτω ---
    uilabel(fig, 'Text', 'Μεμονωμένο σφάλμα (X):', 'FontColor', 'k', ...
        'Position', [20 515 220 20]);

    uilabel(fig, 'Text', 'Στοιχείο:', 'FontColor', [0 0.35 0.7], 'Position', [20 490 60 20]);
    ddSingle = uidropdown(fig, 'Items', {}, 'Position', [80 486 180 24]);
    setappdata(fig, 'ddSingle', ddSingle);

    uibutton(fig, 'Text', '+ Μεμονωμένο σφάλμα', 'Position', [490 485 260 26], ...
        'ButtonPushedFcn', @(btn, event) onAddSingle(fig));

    % --- Σύνθετο σφάλμα (X-Y): ίδιο layout/ύψος με το μεμονωμένο ---
    uilabel(fig, 'Text', 'Σύνθετο σφάλμα (εύρος X-Y):', 'FontColor', 'k', ...
        'Position', [20 445 220 20]);

    uilabel(fig, 'Text', 'Από:', 'FontColor', [0 0.35 0.7], 'Position', [20 420 40 20]);
    ddFrom = uidropdown(fig, 'Items', {}, 'Position', [60 416 180 24]);
    setappdata(fig, 'ddFrom', ddFrom);

    uilabel(fig, 'Text', 'Έως:', 'FontColor', [0 0.35 0.7], 'Position', [255 420 40 20]);
    ddTo = uidropdown(fig, 'Items', {}, 'Position', [295 416 180 24]);
    setappdata(fig, 'ddTo', ddTo);

    uibutton(fig, 'Text', '+ Σύνθετο σφάλμα (X-Y)', 'Position', [490 415 260 26], ...
        'ButtonPushedFcn', @(btn, event) onAddRange(fig));

    % --- Καθαρισμός: ΚΑΤΩ και από τα δύο είδη καταχώρησης ---
    uibutton(fig, 'Text', 'Καθαρισμός όλων', 'Position', [290 375 200 26], ...
        'BackgroundColor', [0.75 0.25 0.25], 'FontColor', 'w', ...
        'ButtonPushedFcn', @(btn, event) onClearFaults(fig));

    uilabel(fig, 'Text', 'Καταχωρημένα σφάλματα (raw_input_faults):', ...
        'FontColor', [0.6 0.4 0], 'Position', [20 345 400 20]);

    faultSummaryArea = uitextarea(fig, 'Position', [20 285 740 55], 'Editable', 'off', ...
        'FontColor', 'k', 'BackgroundColor', [1 1 1]);
    setappdata(fig, 'faultSummaryArea', faultSummaryArea);
    faultSummaryArea.Value = {'(καμία καταχώρηση ακόμα)'};

    % ================= ΕΝΟΤΗΤΑ 3: ΚΑΤΑΓΡΑΦΗ / LOG =================
    uilabel(fig, 'Text', 'Καταγραφή:', 'FontColor', 'k', 'Position', [20 255 300 20]);

    outputArea = uitextarea(fig, 'Position', [20 90 740 155], 'Editable', 'off', ...
        'FontColor', 'k', 'BackgroundColor', [1 1 1], 'FontName', 'Consolas');
    setappdata(fig, 'outputArea', outputArea);

    % ================= ΕΝΟΤΗΤΑ 4: VERBOSE + START (κάτω γραμμή) =========
    verboseCB = uicheckbox(fig, 'Text', 'Λεπτομερής προβολή (verbose)', ...
        'FontColor', 'k', 'Position', [20 30 260 22], ...
        'ValueChangedFcn', @(cb, event) onVerboseChanged(fig, cb));
    setappdata(fig, 'verboseCB', verboseCB);

    uibutton(fig, 'Text', 'Καθαρισμός / Νέα Γραμμή', 'Position', [310 18 260 34], ...
        'BackgroundColor', [0.5 0.5 0.5], 'FontColor', 'w', 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @(btn, event) onReset(fig));

    uibutton(fig, 'Text', char(9654) + " Εκτέλεση (Start)", 'Position', [590 20 170 36], ...
        'BackgroundColor', [0.15 0.55 0.2], 'FontColor', 'w', 'FontWeight', 'bold', ...
        'FontSize', 13, 'ButtonPushedFcn', @(btn, event) onStart(fig));

    appendLog(fig, 'Καλωσήρθες. Επίλεξε γραμμή από το dropdown και πάτησε "Επιβεβαίωση".');
end

% =========================================================================
function onReset(fig)
    % Καθαρίζει ΟΛΗ την κατάσταση του GUI και ξεκλειδώνει την επιλογή
    % γραμμής, ώστε ο χρήστης να μπορεί να τρέξει νέο σενάριο χωρίς να
    % κλείσει το παράθυρο. Επαναδιαβάζει το ΑΡΧΙΚΟ, ανέπαφο Excel από την
    % αρχή (το πρόγραμμα δεν γράφει ποτέ πίσω σε αυτό, οπότε αυτό απλά
    % εξασφαλίζει μια εντελώς φρέσκια, καθαρή αφετηρία).
    excel_filename = getappdata(fig, 'excel_filename');
    topology_data = readtable(excel_filename, 'Sheet', 1);
    network_elements = readtable(excel_filename, 'Sheet', 2);
    setappdata(fig, 'topology_data', topology_data);
    setappdata(fig, 'network_elements', network_elements);

    setappdata(fig, 'target_line', '');
    setappdata(fig, 'raw_input_faults', {});

    line_cols = getappdata(fig, 'line_cols');
    dd = getappdata(fig, 'lineDropdown');
    dd.Value = line_cols{1};
    dd.Enable = 'on';

    confirmBtn = getappdata(fig, 'confirmBtn');
    confirmBtn.Enable = 'on';

    topoArea = getappdata(fig, 'topoArea');
    topoArea.Value = {''};

    ddSingle = getappdata(fig, 'ddSingle');
    ddFrom = getappdata(fig, 'ddFrom');
    ddTo = getappdata(fig, 'ddTo');
    ddSingle.Items = {};
    ddFrom.Items = {};
    ddTo.Items = {};

    faultSummaryArea = getappdata(fig, 'faultSummaryArea');
    faultSummaryArea.Value = {'(καμία καταχώρηση ακόμα)'};

    outputArea = getappdata(fig, 'outputArea');
    outputArea.Value = {'Έγινε καθαρισμός (φρέσκια ανάγνωση του αρχικού Excel). Επίλεξε γραμμή και πάτησε "Επιβεβαίωση".'};
end

% =========================================================================
function onConfirmLine(fig, dd)
    line_name = dd.Value;
    setappdata(fig, 'target_line', line_name);

    topology_data = getappdata(fig, 'topology_data');
    network_elements = getappdata(fig, 'network_elements');
    topoArea = getappdata(fig, 'topoArea');

    col_data = topology_data.(line_name);
    elems = {};
    for r = 1:height(topology_data)
        v = col_data{r};
        if iscell(v), v = v{1}; end
        s = strtrim(char(string(v)));
        if ~isempty(s) && ~strcmpi(s, "missing") && ~strcmpi(s, "NaN")
            elems{end+1} = s; %#ok<AGROW>
        end
    end

    chain = strjoin([{'[Υποσταθμός]'}, elems, {'[Τέλος / Ζυγός]'}], ' -> ');

    lines = {
        '======================================================';
        sprintf('[OK] ΕΠΙΒΕΒΑΙΩΣΗ: Η γραμμή "%s" βρέθηκε.', line_name);
        sprintf('Οπτική Αναπαράσταση: %s', line_name);
        '------------------------------------------------------';
        chain;
        '======================================================';
    };
    topoArea.Value = lines;

    % --- Φιλτράρισμα ΜΟΝΟ Segment-τύπου στοιχείων για το fault-list ---
    seg_elems = {};
    for i = 1:numel(elems)
        elem = elems{i};
        row = network_elements(strcmp(network_elements.Element, elem), :);
        if height(row) > 1, row = row(1, :); end
        if isempty(row), continue; end
        tv = row.Type;
        if iscell(tv), tv = tv{1}; end
        type_val = strtrim(char(string(tv)));
        if strcmpi(type_val, 'Segment')
            seg_elems{end+1} = elem; %#ok<AGROW>
        end
    end

    ddSingle = getappdata(fig, 'ddSingle');
    ddFrom = getappdata(fig, 'ddFrom');
    ddTo = getappdata(fig, 'ddTo');
    if isempty(seg_elems)
        ddSingle.Items = {};
        ddFrom.Items = {};
        ddTo.Items = {};
    else
        ddSingle.Items = seg_elems;
        ddSingle.Value = seg_elems{1};
        ddFrom.Items = seg_elems;
        ddFrom.Value = seg_elems{1};
        ddTo.Items = seg_elems;
        ddTo.Value = seg_elems{min(2, numel(seg_elems))};
    end

    % Νέα γραμμή -> ξεκινάμε τα σφάλματα από την αρχή
    setappdata(fig, 'raw_input_faults', {});
    faultSummaryArea = getappdata(fig, 'faultSummaryArea');
    faultSummaryArea.Value = {'(καμία καταχώρηση ακόμα)'};

    % --- Κλείδωμα επιλογής γραμμής: μία γραμμή ανά "συνεδρία" GUI ---
    dd.Enable = 'off';
    confirmBtn = getappdata(fig, 'confirmBtn');
    confirmBtn.Enable = 'off';

    if isempty(seg_elems)
        appendLog(fig, sprintf('Γραμμή "%s" επιβεβαιώθηκε, αλλά δεν βρέθηκαν Segment-τύπου στοιχεία.', line_name));
    else
        appendLog(fig, sprintf('Γραμμή "%s" επιβεβαιώθηκε (%d segments διαθέσιμα).', line_name, numel(seg_elems)));
    end
end

% =========================================================================
function onAddSingle(fig)
    ddSingle = getappdata(fig, 'ddSingle');
    if isempty(ddSingle.Items)
        appendLog(fig, '[!] Δεν υπάρχουν διαθέσιμα segments (επιβεβαίωσε πρώτα γραμμή).');
        return;
    end

    elem = ddSingle.Value;
    faults = getappdata(fig, 'raw_input_faults');
    faults{end+1} = elem;
    setappdata(fig, 'raw_input_faults', faults);
    refreshFaultSummary(fig);

    appendLog(fig, sprintf('[OK] Προστέθηκε μεμονωμένο σφάλμα: %s', elem));
end

% =========================================================================
function onAddRange(fig)
    ddFrom = getappdata(fig, 'ddFrom');
    ddTo = getappdata(fig, 'ddTo');

    if isempty(ddFrom.Items) || isempty(ddTo.Items)
        appendLog(fig, '[!] Δεν υπάρχουν διαθέσιμα segments (επιβεβαίωσε πρώτα γραμμή).');
        return;
    end

    from_elem = ddFrom.Value;
    to_elem = ddTo.Value;

    if strcmp(from_elem, to_elem)
        appendLog(fig, '[!] Το "Από" και το "Έως" πρέπει να είναι ΔΙΑΦΟΡΕΤΙΚΑ στοιχεία.');
        return;
    end

    combo = sprintf('%s-%s', from_elem, to_elem);
    faults = getappdata(fig, 'raw_input_faults');
    faults{end+1} = combo;
    setappdata(fig, 'raw_input_faults', faults);
    refreshFaultSummary(fig);

    appendLog(fig, sprintf('[OK] Προστέθηκε σύνθετο σφάλμα: %s', combo));
end

% =========================================================================
function onClearFaults(fig)
    setappdata(fig, 'raw_input_faults', {});
    refreshFaultSummary(fig);
    appendLog(fig, 'Όλα τα καταχωρημένα σφάλματα διαγράφηκαν.');
end

% =========================================================================
function refreshFaultSummary(fig)
    faults = getappdata(fig, 'raw_input_faults');
    faultSummaryArea = getappdata(fig, 'faultSummaryArea');
    if isempty(faults)
        faultSummaryArea.Value = {'(καμία καταχώρηση ακόμα)'};
    else
        faultSummaryArea.Value = {strjoin(faults, ', ')};
    end
end

% =========================================================================
function onVerboseChanged(fig, cb)
    setappdata(fig, 'verbose', cb.Value);
    if cb.Value
        appendLog(fig, 'verbose = TRUE - θα εμφανίζονται όλες οι ενδιάμεσες πληροφορίες.');
    else
        appendLog(fig, 'verbose = FALSE - θα εμφανίζεται μόνο το τελικό Operation Note.');
    end
end

% =========================================================================
function onStart(fig)
    target_line = getappdata(fig, 'target_line');
    raw_input_faults = getappdata(fig, 'raw_input_faults');
    verbose = getappdata(fig, 'verbose');

    if isempty(target_line)
        appendLog(fig, '[!] Δεν έχεις επιβεβαιώσει γραμμή ακόμα.');
        return;
    end
    if isempty(raw_input_faults)
        appendLog(fig, '[!] Δεν έχεις καταχωρήσει κανένα σφάλμα ακόμα.');
        return;
    end

    appendLog(fig, '------------------------------------------------------');
    appendLog(fig, sprintf('Εκτέλεση main("%s", {%s}, verbose=%d) ...', ...
        target_line, strjoin(raw_input_faults, ', '), verbose));
% evalc(): τρέχει το main() ΚΑΙ ταυτόχρονα "πιάνει" όλο το printed
% output του σαν string (αντί να πάει στο Command Window), ώστε να
% εμφανιστεί σε ξεχωριστό, καθαρό παράθυρο 
    try
        captured = evalc('main(target_line, raw_input_faults, verbose)');
    catch ME
        appendLog(fig, sprintf('[ERROR] %s', ME.message));
        return;
    end

    appendLog(fig, 'Ολοκληρώθηκε. Το πλήρες αποτέλεσμα άνοιξε σε νέο παράθυρο.');
    openOutputWindow(target_line, captured);
end

% =========================================================================
function openOutputWindow(target_line, captured)
    outFig = uifigure('Name', sprintf('Operation Note - %s', target_line), ...
        'Position', [150 80 900 700], 'Color', [0.94 0.94 0.94]);

    uilabel(outFig, 'Text', sprintf('Αποτέλεσμα εκτέλεσης: %s', target_line), ...
        'FontWeight', 'bold', 'FontColor', 'k', 'FontSize', 14, ...
        'Position', [20 660 860 24]);

    ta = uitextarea(outFig, 'Position', [20 60 860 590], 'Editable', 'off', ...
        'FontColor', 'k', 'BackgroundColor', [1 1 1], 'FontName', 'Consolas', ...
        'FontSize', 12);

    if isempty(strtrim(captured))
        ta.Value = {'(το main.m έτρεξε χωρίς κανένα printed output)'};
    else
        ta.Value = strsplit(captured, newline);
    end

    uibutton(outFig, 'Text', 'Κλείσιμο', 'Position', [770 15 110 30], ...
        'ButtonPushedFcn', @(btn, event) close(outFig));
end

% =========================================================================
function appendLog(fig, msg)
    outputArea = getappdata(fig, 'outputArea');
    existing = outputArea.Value;
    if ischar(existing)
        existing = {existing};
    end
    outputArea.Value = [existing; {msg}];
    drawnow;
    try
        scroll(outputArea, 'bottom');
    catch
        % παλαιότερες εκδόσεις MATLAB δεν έχουν scroll() για uitextarea -
        % αγνόησέ το, δεν είναι κρίσιμο.
    end
end
