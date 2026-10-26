function [opened_switches, opened_positions] = Branch_Switch(target_line, line_elements, raw_input_faults, network_elements, feed_direction)
    % =========================================================================
    % ΣΥΝΑΡΤΗΣΗ: Branch_Switch (Υποστηρίζει δυναμικά LTR & RTL)
    % -------------------------------------------------------------------------
    % Κανονικά: ανοίγει ΕΝΑΝ και μόνο διακόπτη (το πλησιέστερο Type=CB προς
    % την πηγή) αρκεί από μόνο του για την απομόνωση όλων των σφαλμάτων
    % του κλάδου.
    %
    % Αν υπάρχει όμως Type=T (τριπολικός αποζεύκτης) το πολύ 2 θέσεις μετά
    % το πλησιέστερο-στην-πηγή σφάλμα (προς την κατεύθυνση της πηγής), ΤΟΤΕ
    % ΚΑΙ ΜΟΝΟ ΤΟΤΕ ανοίγουν 3 διακόπτες αντί για 1.  Πρώτα οι δύο CB που
    % γειτονεύουν με το T (και στις δύο πλευρές του) και ΤΕΛΕΥΤΑΙΟ το ίδιο
    % το T (οπτική επιβεβαίωση απομόνωσης, αφού πρώτα έχει ήδη κοπεί κάθε
    % πιθανή τροφοδοσία γύρω του μέσω των δύο CB).
    %
    % ΕΞΟΔΟΙ:
    %   opened_switches  : cellstr με τα ονόματα των διακοπτών που ανοίγουν
    %                      (1 στοιχείο στην απλή περίπτωση, 3 αν υπάρχει T)
    %   opened_positions : αντίστοιχος αριθμητικός πίνακας με τις θέσεις
    %                      τους μέσα στη line_elements (ίδιο μήκος με το
    %                      opened_switches)  χρησιμοποιείται από τον
    %                      καλούντα (main.m) για να υπολογίσει ποιο τμήμα
    %                      της γραμμής μένει χωρίς ρεύμα (Affected_Consumers).
    % =========================================================================

    fprintf('==> Εξέταση γραμμής: %s (Κατεύθυνση: %s)\n', target_line, feed_direction);
    fprintf('Είσοδος σφαλμάτων από χρήστη: %s\n\n', strjoin(raw_input_faults, ', '));

    opened_switches = {};
    opened_positions = [];

    % --- ΜΕΤΑΦΡΑΣΗ & ΕΥΡΩΣΗ ΤΩΝ ΔΕΙΚΤΩΝ ΣΦΑΛΜΑΤΩΝ ---
    all_fault_indices = [];
    for f = 1:length(raw_input_faults)
        current_fault = strtrim(raw_input_faults{f});
        
        if contains(current_fault, '-')
            parts = split(current_fault, '-');
            elem1 = strtrim(parts{1});
            elem2 = strtrim(parts{2});
            idx1 = find(strcmp(line_elements, elem1));
            idx2 = find(strcmp(line_elements, elem2));
            if ~isempty(idx1) && ~isempty(idx2)
                range_idx = min(idx1, idx2) : max(idx1, idx2);
                all_fault_indices = [all_fault_indices, range_idx];
            end
        else
            idx = find(strcmp(line_elements, current_fault));
            if ~isempty(idx)
                all_fault_indices = [all_fault_indices, idx];
            end
        end
    end
    
    all_fault_indices = unique(all_fault_indices);
    if isempty(all_fault_indices)
        error('[FAIL] Κανένα από τα δηλωμένα σφάλματα δεν βρέθηκε στη γραμμή %s!', target_line);
    end
    
    % --- ΕΠΙΛΟΓΗ ΠΙΟ ΚΟΝΤΙΝΟΥ ΣΦΑΛΜΑΤΟΣ ΣΤΗΝ ΠΗΓΗ ---
    if strcmpi(feed_direction, 'RTL')
        % Στο RTL η πηγή είναι δεξιά, οπότε το "κοντινότερο" σφάλμα στην πηγή είναι το μεγαλύτερο index (max)
        target_fault_idx = max(all_fault_indices);
        step = 1;
    else
        % Στο LTR η πηγή είναι αριστερά, οπότε το κοντινότερο σφάλμα είναι το μικρότερο index (min)
        target_fault_idx = min(all_fault_indices);
        step = -1;
    end
    
    target_fault_name = line_elements{target_fault_idx};
    fprintf('[INFO] [Branch Logic]: Εντοπίστηκαν πολλαπλά σφάλματα. Το πιο κοντινό στην πηγή είναι το "%s" στη θέση %d.\n', ...
        target_fault_name, target_fault_idx);
    
    % --- ΑΝΑΖΗΣΤΗΣΗ CB ΠΡΟΣ ΤΗΝ ΚΑΤΕΥΘΥΝΣΗ ΤΗΣ ΠΗΓΗΣ ---
    disp('--- Εκτέλεση Ρουτίνας Branch Switch (Αναζήτηση CB ανάντη προς την πηγή) ---');
    
    found_cb = false;
    upstream_cb_name = '';
    upstream_cb_type = '';
    upstream_cb_pos = [];
    
    if strcmpi(feed_direction, 'RTL')
        % RTL: Η πηγή είναι προς τα δεξιά, άρα σαρώνουμε προς τα ΜΕΓΑΛΥΤΕΡΑ indices ((target_fault_idx + 1) έως τέλος)
        search_range = (target_fault_idx + 1) : 1 : length(line_elements);
    else
        % LTR: Η πηγή είναι προς τα αριστερά, άρα σαρώνουμε προς τα ΜΙΚΡΟΤΕΡΑ indices ((target_fault_idx - 1) έως 1)
        search_range = (target_fault_idx - 1) : -1 : 1;
    end
    
    for i = search_range
        curr_elem = line_elements{i};
        match_row = network_elements(strcmp(network_elements.Element, curr_elem), :);
        
        if ~isempty(match_row) && ismember('Type', match_row.Properties.VariableNames)
            elem_type = strtrim(string(match_row.Type));
            if is_openable_switch(elem_type)
                upstream_cb_name = curr_elem;
                upstream_cb_type = char(elem_type);
                upstream_cb_pos = i;
                found_cb = true;
                break;
            end
        end
    end

    % ---ΕΛΕΓΧΟΣ: ΥΠΑΡΧΕΙ Τ ΤΟ ΠΟΛΥ 2 ΘΕΣΕΙΣ ΜΕΤΑ ΤΟ ΣΦΑΛΜΑ, ΠΡΟΣ ΤΗΝ ΠΗΓΗ; ---
    t_pos = [];
    N = numel(line_elements);
    for k = 1:2
        p = target_fault_idx + k * step;
        if p < 1 || p > N
            break;
        end
        elem = line_elements{p};
        row = network_elements(strcmp(network_elements.Element, elem), :);
        if ~isempty(row) && ismember('Type', row.Properties.VariableNames)
            et = strtrim(string(row.Type));
            if strcmpi(et, 'T')
                t_pos = p;
                break;
            end
        end
    end

    % --- OPERATION NOTE (προετοιμασία λίστας διακοπτών) ---
    if ~isempty(t_pos)
        % --- ΠΕΡΙΠΤΩΣΗ Τ: 3 διακόπτες, ΑΝΤΙ για τον έναν ---
        t_name = line_elements{t_pos};
        [near_cb, near_pos] = find_nearest_cb(t_pos, -step, line_elements, network_elements); % προς το σφάλμα
        [far_cb, far_pos]   = find_nearest_cb(t_pos,  step, line_elements, network_elements); % προς την πηγή

        fprintf('[INFO] [Οπτική Απομόνωση]: Εντοπίστηκε τριπολικός αποζεύκτης "%s" κοντά στο σφάλμα "%s" - ακολουθείται η διαδικασία των 3 διακοπτών.\n', ...
            t_name, target_fault_name);

        if ~isempty(near_cb)
            fprintf('[INFO] OPERATION NOTE: Δίνεται εντολή ανοίγματος στον διακόπτη %s.\n', near_cb);
            opened_switches{end+1} = near_cb; %#ok<AGROW>
            opened_positions(end+1) = near_pos; %#ok<AGROW>
        end
        if ~isempty(far_cb)
            fprintf('[INFO] OPERATION NOTE: Δίνεται εντολή ανοίγματος στον διακόπτη %s.\n', far_cb);
            opened_switches{end+1} = far_cb; %#ok<AGROW>
            opened_positions(end+1) = far_pos; %#ok<AGROW>
        end
        fprintf('[INFO] OPERATION NOTE: Δίνεται εντολή ανοίγματος στον τριπολικό αποζεύκτη %s (οπτική επιβεβαίωση απομόνωσης, ΤΕΛΕΥΤΑΙΟ βήμα).\n', t_name);
        opened_switches{end+1} = t_name; %#ok<AGROW>
        opened_positions(end+1) = t_pos; %#ok<AGROW>

    elseif found_cb
        % --- ΚΑΝΟΝΙΚΗ ΠΕΡΙΠΤΩΣΗ: ένας μόνο διακόπτης ---
        fprintf('[OK] Εντοπίστηκε μέσο προστασίας προς την πηγή: "%s" (Type: %s)\n', upstream_cb_name, upstream_cb_type);
        fprintf('[INFO] OPERATION NOTE: Δίνεται εντολή ανοίγματος στον διακόπτη %s για την απομόνωση της βλάβης (Κατεύθυνση: %s).\n', ...
            upstream_cb_name, feed_direction);
        opened_switches{end+1} = upstream_cb_name;
        opened_positions(end+1) = upstream_cb_pos;
    else
        fprintf('[ΠΡΟΣΟΧΗ] Δεν βρέθηκε κατάλληλος διακόπτης προς την κατεύθυνση της πηγής για το σφάλμα "%s".\n', target_fault_name);
    end
end

function tf = is_openable_switch(elem_type)
    % Στοιχεία που επιτρέπεται να ανοίξουν = οτιδήποτε ΔΕΝ είναι Segment (καλώδιο,
    % όχι διακόπτης) ΚΑΙ ΔΕΝ είναι Type=T (χρειάζεται ξεχωριστό, ειδικό
    % χειρισμό - δεν ανοίγει απευθείας εδώ). Καλύπτεται από CB, αλλά και
    % Busbar-τύπου όρια γραμμής (π.χ. "(70)T648 Pl.2") που είναι εξίσου
    % έγκυρα σημεία απομόνωσης, ακριβώς όπως ήδη κάναμε παντού αλλού στο
    % πρόγραμμα (π.χ. open_switches_list στη main, find_bridge_partner_cb).
    et = lower(strtrim(string(elem_type)));
    tf = ~contains(et, 'segment') && ~strcmp(et, 't');
end

function [cb_name, cb_pos] = find_nearest_cb(start_pos, step, line_elements, network_elements)
    % Σαρώνει από start_pos+step προς την κατεύθυνση step, βρίσκει το
    % πρώτο ανοίξιμο στοιχείο (όχι Segment, όχι T), και επιστρέφει το
    % όνομα ΚΑΙ τη θέση του ή ('', []) αν δεν βρεθεί μέχρι την άκρη.
    cb_name = '';
    cb_pos = [];
    N = numel(line_elements);
    p = start_pos + step;
    while p >= 1 && p <= N
        elem = line_elements{p};
        row = network_elements(strcmp(network_elements.Element, elem), :);
        if ~isempty(row) && ismember('Type', row.Properties.VariableNames)
            et = strtrim(string(row.Type));
            if is_openable_switch(et)
                cb_name = elem;
                cb_pos = p;
                return;
            end
        end
        p = p + step;
    end
end
