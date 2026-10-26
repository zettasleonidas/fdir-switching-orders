function [orphan_groups, fault_element_indices] = find_faulty_isolation_zones( ...
        target_line, line_elements, network_elements, raw_input_faults, ...
        first_line_elem, last_line_elem, verbose)
% =========================================================================
% FUNCTION: find_faulty_isolation_zones
% -------------------------------------------------------------------------
% Κατηγοριοποιεί τα σφάλματα εισόδου και εντοπίζει τα ορφανά
% segments μιας γραμμής (stem), ομαδοποιημένα σε συνεχόμενα διαστήματα.
% Πλήρως δυναμική: δουλεύει για οποιαδήποτε γραμμή και οποιοδήποτε
% σενάριο σφάλματος (μεμονωμένα 'X' ή σύνθετα 'X-Y', σε οποιαδήποτε θέση).
%
% Εοισήμανση νο1: (Βήμα Β' - σάρωση συνέχειας):
%   Σταματάμε (μπλοκάρουμε, "δεν υπάρχει ρεύμα από αυτή την πλευρά") ΜΟΝΟ
%   όταν συναντήσουμε fault_element_index ή στοιχείο με State=0. Ένα
%   ενδιάμεσο στοιχείο με State=1 δεν αποδεικνύει τίποτα από μόνο του·
%   απλώς η αγωγιμότητα συνεχίζει. Δηλώνουμε "έχει ρεύμα" ΜΟΝΟ αν
%   φτάσουμε καθαρά μέχρι την άκρη της γραμμής χωρίς να έχουμε σκοντάψει.
%
% Επισήμανση νο2: (Βήμα Γ' - ομαδοποίηση):
%   Δύο ορφανά segments ενώνονται σε μία ομάδα ΑΝ ΚΑΙ ΜΟΝΟ ΑΝ ανάμεσά
%   τους ΔΕΝ υπάρχει κανένα στοιχείο σφάλματος (fault_element_indices).
%   Ενδιάμεσα CBs/άλλα μη-segment στοιχεία δεν εμποδίζουν την ένωση.
%   Αν όμως ανάμεσά τους υπάρχει πραγματικό σφάλμα, οι ομάδες ΔΕΝ
%   ενώνονται (π.χ. "Al1-Al2" και "Al6-Al7" παραμένουν ξεχωριστά αν
%   ανάμεσά τους υπάρχει το σφάλμα Al3-Al5).
%
% ΕΙΣΟΔΟΙ:
%   target_line      : string/char, π.χ. 'Line_1'
%   line_elements     : string array με την τοπολογία της γραμμής (σε σειρά)
%   network_elements  : table (Sheet2) με Type, State, Load, Capacity, Link
%   raw_input_faults  : cell array από strings, π.χ. {'Al3-Al5','Al8-Al13'}
%   first_line_elem   : line_elements(1)
%   last_line_elem    : line_elements(end)
%
% ΕΞΟΔΟΙ:
%   orphan_groups         : string array με τα ομαδοποιημένα ορφανά segments
%   fault_element_indices : θέσεις (indices) των στοιχείων σφάλματος
% =========================================================================

    if nargin < 7
        verbose = true; % προεπιλογή: ίδια συμπεριφορά με πριν
    end

    if verbose
        fprintf('\n--- 1. ΑΝΑΛΥΣΗ ΚΑΤΗΓΟΡΙΟΠΟΙΗΣΗΣ ΣΦΑΛΜΑΤΩΝ ---\n');
    end

    isolated_indices = false(size(line_elements));
    fault_element_indices = [];
    valid_fault_counter = 0;

    for f = 1:numel(raw_input_faults)
        element_block = string(raw_input_faults{f});

        if contains(element_block, "-")
            limits = split(element_block, "-");
            startElem = strtrim(limits(1));
            endElem   = strtrim(limits(2));

            idxStart = find(line_elements == startElem, 1);
            idxEnd   = find(line_elements == endElem, 1);

            if isempty(idxStart) || isempty(idxEnd)
                fprintf('[ΠΡΟΣΟΧΗ] [Προσοχή]: Το σύνθετο σφάλμα [%s] αγνοείται διότι δεν ανήκει πλήρως ή εν μέρει στη γραμμή %s.\n', element_block, target_line);
                continue;
            end
            if idxStart > idxEnd
                [idxStart, idxEnd] = deal(idxEnd, idxStart);
            end

            valid_fault_counter = valid_fault_counter + 1;
            if verbose
                if line_elements(idxStart) == first_line_elem && line_elements(idxEnd) == last_line_elem
                    fprintf('%do σφάλμα [%s] -> 4. Ολική αποκοπή γραμμής από την αρχή έως το τέλος\n', valid_fault_counter, element_block);
                elseif line_elements(idxStart) == first_line_elem
                    fprintf('%do σφάλμα [%s] -> 5. Σφάλμα από το πρώτο στοιχείο έως ενδιάμεσο στοιχείο\n', valid_fault_counter, element_block);
                elseif line_elements(idxEnd) == last_line_elem
                    fprintf('%do σφάλμα [%s] -> 6. Σφάλμα από ενδιάμεσο στοιχείο έως το τελευταίο στοιχείο\n', valid_fault_counter, element_block);
                else
                    fprintf('%do σφάλμα [%s] -> 7. Καθαρά ενδιάμεσο σύνθετο σφάλμα (Block)\n', valid_fault_counter, element_block);
                end
            end

            isolated_indices(idxStart:idxEnd) = true;
            fault_element_indices = [fault_element_indices, idxStart:idxEnd]; %#ok<AGROW>

            if idxStart > 1
                isolated_indices(idxStart - 1) = true;
            end
            if idxEnd < numel(line_elements)
                isolated_indices(idxEnd + 1) = true;
            end

        else
            startElem = element_block;
            idxStart = find(line_elements == startElem, 1);

            if isempty(idxStart)
                fprintf('[ΠΡΟΣΟΧΗ] [Προσοχή]: Το σφάλμα [%s] δεν λογίζεται σαν σφάλμα διότι δεν υπάρχει στη γραμμή %s.\n', element_block, target_line);
                continue;
            end

            valid_fault_counter = valid_fault_counter + 1;
            if verbose
                if startElem == first_line_elem
                    fprintf('%do σφάλμα [%s] -> 1. Μεμονωμένο σφάλμα στο 1ο στοιχείο της γραμμής (στην αρχή)\n', valid_fault_counter, element_block);
                elseif startElem == last_line_elem
                    fprintf('%do σφάλμα [%s] -> 2. Μεμονωμένο σφάλμα στο τελευταίο στοιχείο της γραμμής (στο τέλος)\n', valid_fault_counter, element_block);
                else
                    fprintf('%do σφάλμα [%s] -> 3. Καθαρά ενδιάμεσο μεμονωμένο σφάλμα (Single)\n', valid_fault_counter, element_block);
                end
            end

            isolated_indices(idxStart) = true;
            fault_element_indices = [fault_element_indices, idxStart]; %#ok<AGROW>

            if idxStart > 1
                isolated_indices(idxStart - 1) = true;
            end
            if idxStart < numel(line_elements)
                isolated_indices(idxStart + 1) = true;
            end
        end
    end
    if verbose
        fprintf('---------------------------------------------------------\n\n');
    end

    % --- ΒΗΜΑ Α': ΕΝΤΟΠΙΣΜΟΣ ΜΟΝΟ ΤΩΝ SEGMENTS ΕΚΤΟΣ ΣΦΑΛΜΑΤΟΣ ---
    unpowered_candidates = find(~isolated_indices);
    segment_indices = [];

    for c = 1:numel(unpowered_candidates)
        idx = unpowered_candidates(c);
        curr_elem = line_elements(idx);

        match_row = network_elements(strcmp(string(network_elements.Element), char(curr_elem)), :);
        if height(match_row) > 1
            match_row = match_row(1, :); % ασφάλεια: κοινά segments (π.χ. BClx) μπορεί να έχουν διπλή εγγραφή
        end
        is_seg = false;
        if ~isempty(match_row) && ismember('Type', match_row.Properties.VariableNames)
            if contains(lower(string(match_row.Type)), 'segment')
                is_seg = true;
            end
        end

        if is_seg
            segment_indices(end+1) = idx; %#ok<AGROW>
        end
    end

    if verbose
        fprintf('--- ΕΚΤΥΠΩΣΗ SEGMENTS ΕΚΤΟΣ ΣΦΑΛΜΑΤΟΣ ---\n');
        for s_i = 1:numel(segment_indices)
            fprintf(' Segment εκτός σφάλματος: %s (Θέση: %d)\n', line_elements(segment_indices(s_i)), segment_indices(s_i));
        end
        if isempty(segment_indices)
            fprintf(' (Κανένα segment εκτός σφάλματος)\n');
        end
    end
    if isempty(segment_indices)
        fprintf('[ΠΡΟΣΟΧΗ] [Πόρισμα]: Το σφάλμα καλύπτει ολόκληρη τη γραμμή "%s" -> ΟΛΗ η γραμμή τίθεται εκτός λειτουργίας.\n', target_line);
    end
    if verbose
        fprintf('---------------------------------------------------------\n\n');
    end

    % --- ΒΗΜΑ Β': ΕΛΕΓΧΟΣ ΣΑΡΩΣΗΣ ΣΥΝΕΧΕΙΑΣ (ΑΡΙΣΤΕΡΑ & ΔΕΞΙΑ) ΓΙΑ ΚΑΘΕ SEGMENT ---
    valid_orphan_indices = [];

    for s_i = 1:numel(segment_indices)
        idx = segment_indices(s_i);
        curr_name = line_elements(idx);

        % Αριστερός έλεγχος (προς την αρχή της γραμμής)
        left_has_power = false;
        for l_idx = idx-1 : -1 : 1
            if ismember(l_idx, fault_element_indices)
                break; % Κόβεται από σφάλμα
            end
            l_elem = line_elements(l_idx);
            l_row = network_elements(strcmp(string(network_elements.Element), char(l_elem)), :);
            if height(l_row) > 1
                l_row = l_row(1, :);
            end
            if ~isempty(l_row) && ismember('State', l_row.Properties.VariableNames)
                val_state = l_row.State;
                if isnumeric(val_state), st = val_state; else, st = str2double(string(val_state)); end
                if st == 0
                    break; % Ανοιχτός διακόπτης κόβει την τροφοδοσία
                end
                % st == 1 -> απλή συνέχεια αγωγιμότητας, συνεχίζουμε
            end
            if l_idx == 1
                left_has_power = true; % Φτάσαμε καθαρά μέχρι την αρχή/πηγή
            end
        end

        % Δεξιός έλεγχος (προς το τέλος της γραμμής)
        right_has_power = false;
        for r_idx = idx+1 : numel(line_elements)
            if ismember(r_idx, fault_element_indices)
                break;
            end
            r_elem = line_elements(r_idx);
            r_row = network_elements(strcmp(string(network_elements.Element), char(r_elem)), :);
            if height(r_row) > 1
                r_row = r_row(1, :);
            end
            if ~isempty(r_row) && ismember('State', r_row.Properties.VariableNames)
                val_state = r_row.State;
                if isnumeric(val_state), st = val_state; else, st = str2double(string(val_state)); end
                if st == 0
                    break;
                end
            end
            if r_idx == numel(line_elements)
                right_has_power = true;
            end
        end

        if verbose
            fprintf('   [Check] Segment %s (Θέση %d) -> Left Power: %d | Right Power: %d\n', ...
                curr_name, idx, left_has_power, right_has_power);
        end

        if ~left_has_power && ~right_has_power
            valid_orphan_indices(end+1) = idx;                  %#ok<AGROW>
        end
    end

    % --- ΒΗΜΑ Γ': ΟΜΑΔΟΠΟΙΗΣΗ ΟΡΦΑΝΩΝ (ΔΙΟΡΘΩΜΕΝΗ) ---
    orphan_groups = string([]);
    if ~isempty(valid_orphan_indices)
        start_idx = valid_orphan_indices(1);
        prev_idx = start_idx;

        for k = 2:numel(valid_orphan_indices)
            curr = valid_orphan_indices(k);
            between = (prev_idx+1):(curr-1);
            has_fault_between = ~isempty(between) && any(ismember(between, fault_element_indices));

            if ~has_fault_between
                prev_idx = curr;
            else
                orphan_groups = add_group(orphan_groups, line_elements, start_idx, prev_idx);
                start_idx = curr;
                prev_idx = start_idx;
            end
        end
        orphan_groups = add_group(orphan_groups, line_elements, start_idx, prev_idx);
    end

    fprintf('\n=> Orphan groups:\n');
    if isempty(orphan_groups)
        disp("    (Κανένα ορφανό τμήμα)");
    else
        disp(orphan_groups);
    end

end % --- ΤΕΛΟΣ ΚΥΡΙΑΣ ΣΥΝΑΡΤΗΣΗΣ ---


% --- ΒΟΗΘΗΤΙΚΗ ΣΥΝΑΡΤΗΣΗ ΟΜΑΔΟΠΟΙΗΣΗΣ ---
function groups = add_group(groups, thesi_array, s_idx, e_idx)
    if s_idx == e_idx
        groups(end+1) = thesi_array(s_idx);
    else
        groups(end+1) = thesi_array(s_idx) + "-" + thesi_array(e_idx);
    end
end
