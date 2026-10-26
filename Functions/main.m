function main(target_line, raw_input_faults, verbose)
% =========================================================================
% FUNCTION: main  (Τροχονόμος)
% -------------------------------------------------------------------------
%
% ΕΙΣΟΔΟΣ (όλα ΠΡΟΑΙΡΕΤΙΚΑ  αν παραλειφθούν, χρησιμοποιούνται τα ίδια
% default σενάρια δοκιμής που είχε το script πριν το μετατρέψουμε σε συνάρτηση):
%   target_line      : π.χ. 'Line_5' (default: 'Line_5')
%   raw_input_faults : cellstr με σφάλματα, μεμονωμένα 'X' ή σύνθετα 'X-Y'
%                       (default: {'El1', 'El4-El5'})
%   verbose           : true = πλήρες, αναλυτικό output (debugging) |
%                       false = μόνο τα ουσιώδη (default: true)
%
% ΧΡΗΣΗ:
%   main();                                    % ίδιο σενάριο δοκιμής όπως πριν
%   main('Line_7', {'T25a'}, false);           % custom κλήση (π.χ. από GUI)
% =========================================================================

    if nargin < 1 || isempty(target_line)
        target_line = 'Line_5';
    end
    if nargin < 2 || isempty(raw_input_faults)
        raw_input_faults = {'El1', 'El4-El5'};
    end
    if nargin < 3 || isempty(verbose)
        verbose = true;
    end

    clc;
    tic;

    % --- 1. ΑΝΑΓΝΩΣΗ ΔΕΔΟΜΕΝΩΝ ---
    excel_filename = fullfile('Database', 'Elements_Data.xlsx');
    topology_data = readtable(excel_filename, 'Sheet', 1);
    network_elements = readtable(excel_filename, 'Sheet', 2);

    fprintf('=========================================================\n');
    fprintf('==> ΤΡΟΧΟΝΟΜΟΣ FDIR: ΕΞΕΤΑΣΗ ΓΡΑΜΜΗΣ: %s\n', target_line);
    fprintf('=========================================================\n\n');

    line_elements = rmmissing(topology_data.(target_line));

    % Παράλληλη string-array εκδοχή, ειδικά για τις find_faulty_isolation_zones /
    % find_rescue_candidates / compare_loads (περιμένουν string array). Το
    % αρχικό cell-array line_elements ΔΕΝ πειράζεται - το χρησιμοποιούν ήδη
    % κανονικά το Branch_Switch, το Reverse_Current και οι έλεγχοι busbar/άκρων.
    line_elements_str = string(line_elements);
    first_line_elem = line_elements_str(1);
    last_line_elem  = line_elements_str(end);

    % --- 2. ΕΚΤΕΛΕΣΗ CHECK_BUSBARS (ΠΡΙΝ ΑΠΟ ΟΛΑ) ---
    fprintf('==> Τσεκάρω τα busbars πριν προχωρήσω στην ανάλυση...\n');
    busbar_summary = Check_Busbars(excel_filename, verbose);
    fprintf('---------------------------------------------------------\n');

    % --- 3. ΔΥΝΑΜΙΚΟΣ ΕΛΕΓΧΟΣ ΑΚΡΩΝ & BUSBARS ΑΠΟ ΤΟ SHEET 1 ---
    first_elem = char(strtrim(string(line_elements{1})));
    last_elem = char(strtrim(string(line_elements{end})));

    busbar_col1 = string(topology_data.Busbar_1);
    busbar_col2 = string(topology_data.Busbar_2);

    is_first_in_b1 = any(busbar_col1 == first_elem);
    is_first_in_b2 = any(busbar_col2 == first_elem);
    is_first_busbar = is_first_in_b1 || is_first_in_b2;

    is_last_in_b1 = any(busbar_col1 == last_elem);
    is_last_in_b2 = any(busbar_col2 == last_elem);
    is_last_busbar = is_last_in_b1 || is_last_in_b2;

    % Εκτύπωση πληροφοριών για τα άκρα και τα busbars
    if is_first_in_b1
        fprintf('   - Το πρώτο άκρο της %s είναι το %s και ανήκει στον Busbar_1 (T24)\n', target_line, first_elem);
    elseif is_first_in_b2
        fprintf('   - Το πρώτο άκρο της %s είναι το %s και ανήκει στον Busbar_2 (T648)\n', target_line, first_elem);
    else
        fprintf('   - Το πρώτο άκρο της %s είναι το %s και είναι τυπικό στοιχείο.\n', target_line, first_elem);
    end

    if is_last_in_b1
        fprintf('   - Το τελευταίο άκρο της %s είναι το %s και ανήκει στον Busbar_1 (T24)\n', target_line, last_elem);
    elseif is_last_in_b2
        fprintf('   - Το τελευταίο άκρο της %s είναι το %s και ανήκει στον Busbar_2 (T648)\n', target_line, last_elem);
    else
        fprintf('   - Το τελευταίο άκρο της %s είναι το %s και είναι τυπικό στοιχείο.\n', target_line, last_elem);
    end

    % --- ΒΑΣΙΚΟΣ ΕΛΕΓΧΟΣ ΠΗΓΩΝ (ΧΩΡΙΣ ΚΑΤΕΥΘΥΝΣΗ ΕΔΩ) ---
    first_is_src = check_if_source(first_elem, network_elements);
    last_is_src = check_if_source(last_elem, network_elements);

    if first_is_src && last_is_src
        if ~(is_first_busbar || is_last_busbar)
            fprintf('[FAIL] [Feed Direction Error]: Η γραμμή %s τροφοδοτείται και από τα δύο άκρα (Mesh Network)!\n', target_line);
            error('Mesh Network Error: Διακοπή εκτέλεσης λόγω τροφοδοσίας από τα δύο άκρα.');
        else
            fprintf('=> [Feed Direction Note]: Η γραμμή %s συνδέεται με busbar, επιτρέπεται η κατάσταση χωρίς mesh error.\n', target_line);
        end
    end
    fprintf('---------------------------------------------------------\n\n');

    % --- 4. ΤΥΦΛΟΣ ΕΛΕΓΧΟΣ: ΕΙΝΑΙ Η ΓΡΑΜΜΗ BRANCH Ή STEM (ΜΟΝΟ ΓΙΑ ΔΙΑΚΟΠΤΕΣ); ---
    open_switches_list = cell(1, length(line_elements));
    counter_sw = 0;

    for i = 1:length(line_elements)
        curr_elem = char(strtrim(string(line_elements{i})));
        match_row = network_elements(strcmp(string(network_elements.Element), curr_elem), :);
        if height(match_row) > 1
            match_row = match_row(1, :); % ασφάλεια: κοινά segments (π.χ. BClx) μπορεί να έχουν διπλή εγγραφή
        end

        if ~isempty(match_row) && ismember('State', match_row.Properties.VariableNames)
            raw_state = match_row.State;
            if iscell(raw_state), raw_state = raw_state{1}; end
            state_num = double(raw_state);

            % ΦΙΛΤΡΟ: ΑΠΟΚΛΕΙΟΥΜΕ μόνο Type=Segment από το να μετράει σαν
            %    "διακόπτης" (π.χ. ένα κοινό segment-γέφυρα σαν το BClx με
            %    State=0 που συνδέει δύο γραμμές). Ό,τι ΔΕΝ είναι Segment
            %    (CB, αλλά και Busbar-τύπου όρια όπως το "(10)T648 Pl.2")
            %     το μετράει κανονικά σαν διακόπτη  τα Sheet2 Type values δεν
            %     περιορίζονται μόνο σε "CB".
            is_cb = false;
            if ismember('Type', match_row.Properties.VariableNames)
                type_val = match_row.Type;
                if iscell(type_val), type_val = type_val{1}; end
                is_cb = ~contains(lower(string(type_val)), 'segment');
            end

            if isscalar(state_num) && ~isnan(state_num) && state_num == 0 && is_cb
                counter_sw = counter_sw + 1;
                open_switches_list{counter_sw} = curr_elem;
            end
        end
    end
    open_switches_list = open_switches_list(1:counter_sw);

    is_normally_closed_ends = (first_is_src && last_is_src);

    if ~isempty(open_switches_list) || is_normally_closed_ends
        if isempty(open_switches_list) && is_normally_closed_ends
            is_stem = false;
            fprintf('=> [Αυτόματος Έλεγχος]: Η γραμμή "%s" κρίνεται ως ΔΙΑΚΛΑΔΩΣΗ (Branch) [Κλειστά άκρα με σύνδεση busbar].\n\n', target_line);

            if is_first_busbar && is_last_busbar
                fprintf('   (Η γραμμή συνδέεται και στα δύο της άκρα με ζυγούς. Υπολογισμός ροής βάσει κυρίαρχου ζυγού...)\n');

                dominant_bus = busbar_summary.dominant_bus;

                first_is_dominant = (is_first_in_b1 && strcmp(dominant_bus, 'T24')) || (is_first_in_b2 && strcmp(dominant_bus, 'T648'));
                last_is_dominant  = (is_last_in_b1 && strcmp(dominant_bus, 'T24')) || (is_last_in_b2 && strcmp(dominant_bus, 'T648'));

                if last_is_dominant
                    feed_direction = 'RTL';
                    fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Right-to-Left (ο κυρίαρχος ζυγός %s είναι στο τέλος)\n', target_line, dominant_bus);
                elseif first_is_dominant
                    feed_direction = 'LTR';
                    fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Left-to-Right (ο κυρίαρχος ζυγός %s είναι στην αρχή)\n', target_line, dominant_bus);
                else
                    feed_direction = 'LTR';
                    fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Left-to-Right (εξ ορισμού ισοδύναμων ζυγών)\n', target_line);
                end

            elseif (is_first_busbar && contains(last_elem, '/'))
                feed_direction = 'RTL';
                fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Right-to-Left (από την καθαρή πηγή προς το busbar)\n', target_line);
            elseif (is_last_busbar && contains(first_elem, '/'))
                feed_direction = 'LTR';
                fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Left-to-Right (από την καθαρή πηγή προς το busbar)\n', target_line);
            elseif ~last_is_src && first_is_src
                feed_direction = 'LTR';
                fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Left-to-Right\n', target_line);
            else
                feed_direction = 'RTL';
                fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Right-to-Left\n', target_line);
            end

            [opened_switches, opened_positions] = Branch_Switch(target_line, line_elements, raw_input_faults, network_elements, feed_direction);
            Operation_Note(target_line, struct('name', {}, 'existing_load', {}, 'new_load', {}), opened_switches, {});

            if ~isempty(opened_positions)
                if strcmpi(feed_direction, 'RTL')
                    dead_start = 1;
                    dead_end = min(opened_positions) - 1;
                else
                    dead_start = max(opened_positions) + 1;
                    dead_end = numel(line_elements_str);
                end
                if dead_start <= dead_end
                    branch_fault_indices = [];
                    for bf = 1:numel(raw_input_faults)
                        cf = strtrim(raw_input_faults{bf});
                        if contains(cf, '-')
                            parts = split(cf, '-');
                            i1 = find(line_elements_str == strtrim(string(parts{1})), 1);
                            i2 = find(line_elements_str == strtrim(string(parts{2})), 1);
                            if ~isempty(i1) && ~isempty(i2)
                                branch_fault_indices = [branch_fault_indices, min(i1, i2):max(i1, i2)]; %#ok<AGROW>
                            end
                        else
                            i1 = find(line_elements_str == strtrim(string(cf)), 1);
                            if ~isempty(i1)
                                branch_fault_indices = [branch_fault_indices, i1]; %#ok<AGROW>
                            end
                        end
                    end
                    if dead_start == dead_end
                        branch_group_label = line_elements_str(dead_start);
                    else
                        branch_group_label = line_elements_str(dead_start) + "-" + line_elements_str(dead_end);
                    end
                    Affected_Consumers(target_line, line_elements_str, network_elements, ...
                        branch_fault_indices, branch_group_label, false);
                end
            end
        else
            is_stem = true;
            fprintf('=> [Αυτόματος Έλεγχος]: Η γραμμή "%s" κρίνεται ως ΚΟΡΜΟΣ (Stem).\n', target_line);
            if length(open_switches_list) == 1
                fprintf('   (Εντοπίστηκε ανοιχτός διακόπτης State=0: %s)\n', open_switches_list{1});
            else
                fprintf('   (Εντοπίστηκαν ανοιχτοί διακόπτες State=0: %s)\n', strjoin(open_switches_list, ', '));
            end
        end
    else
        is_stem = false;
        fprintf('=> [Αυτόματος Έλεγχος]: Η γραμμή "%s" κρίνεται ως ΔΙΑΚΛΑΔΩΣΗ (Branch).\n\n', target_line);

        if ~last_is_src && first_is_src
            feed_direction = 'LTR';
            fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Left-to-Right\n', target_line);
        else
            feed_direction = 'RTL';
            fprintf('=> [Feed Direction]: Η γραμμή %s τροφοδοτείται Right-to-Left\n', target_line);
        end

        [opened_switches, opened_positions] = Branch_Switch(target_line, line_elements, raw_input_faults, network_elements, feed_direction);
        Operation_Note(target_line, struct('name', {}, 'existing_load', {}, 'new_load', {}), opened_switches, {});

        % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ Affected_Consumers (ΚΑΙ ΓΙΑ BRANCH) ---
        %     Ίδια λογική με το άλλο Branch σημείο πιο πάνω 
        if ~isempty(opened_positions)
            if strcmpi(feed_direction, 'RTL')
                dead_start = 1;
                dead_end = min(opened_positions) - 1;
            else
                dead_start = max(opened_positions) + 1;
                dead_end = numel(line_elements_str);
            end
            if dead_start <= dead_end
                branch_fault_indices = [];
                for bf = 1:numel(raw_input_faults)
                    cf = strtrim(raw_input_faults{bf});
                    if contains(cf, '-')
                        parts = split(cf, '-');
                        i1 = find(line_elements_str == strtrim(string(parts{1})), 1);
                        i2 = find(line_elements_str == strtrim(string(parts{2})), 1);
                        if ~isempty(i1) && ~isempty(i2)
                            branch_fault_indices = [branch_fault_indices, min(i1, i2):max(i1, i2)]; %#ok<AGROW>
                        end
                    else
                        i1 = find(line_elements_str == strtrim(string(cf)), 1);
                        if ~isempty(i1)
                            branch_fault_indices = [branch_fault_indices, i1]; %#ok<AGROW>
                        end
                    end
                end
                if dead_start == dead_end
                    branch_group_label = line_elements_str(dead_start);
                else
                    branch_group_label = line_elements_str(dead_start) + "-" + line_elements_str(dead_end);
                end
                Affected_Consumers(target_line, line_elements_str, network_elements, ...
                    branch_fault_indices, branch_group_label, false);
            end
        end
    end

    % --- 4.5 ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ find_faulty_isolation_zones (ΜΟΝΟ ΓΙΑ STEM) ---
    %     Χρειάζεται πριν το compare_loads, για να έχουμε orphan_groups και
    %     fault_element_indices έτοιμα όταν φτάσουμε στο ερώτημα YES/NO.
    if is_stem
        [orphan_groups, fault_element_indices] = find_faulty_isolation_zones( ...
            target_line, line_elements_str, network_elements, raw_input_faults, ...
            first_line_elem, last_line_elem, verbose);
    end

    % --- 5. ΕΛΕΓΧΟΣ LINKS & INTERCONNECTION (ΜΟΝΟ ΓΙΑ STEM) ---
    if is_stem
        fprintf('\n--- Έλεγχος Διασύνδεσης (Is there an interconnection?) ---\n');

        fprintf('   - Συνολικοί διακόπτες που εντοπίστηκαν ανοιχτοί: %d (%s)\n', ...
            length(open_switches_list), strjoin(open_switches_list, ', '));

        all_found_sources = cell(1, length(open_switches_list));
        counter_src = 0;

        for s = 1:length(open_switches_list)
            sw_name = open_switches_list{s};
            match_row = network_elements(strcmp(string(network_elements.Element), sw_name), :);
            if height(match_row) > 1
                match_row = match_row(1, :); % ασφάλεια σε τυχόν διπλότυπες εγγραφές
            end

            link_val = "";
            if ~isempty(match_row) && ismember('Link', match_row.Properties.VariableNames)
                raw_link = match_row.Link;
                if isnumeric(raw_link)
                    if ~isnan(raw_link)
                        link_val = string(raw_link);
                    end
                else
                    if iscell(raw_link), raw_link = raw_link{1}; end
                    if ~isempty(raw_link)
                        temp_str = strtrim(string(raw_link));
                        if strlength(temp_str) > 0 && ~strcmpi(temp_str, "NaN") && ~strcmpi(temp_str, "missing")
                            link_val = temp_str;
                        end
                    end
                end
            end

            if strlength(link_val) > 0 && ~strcmpi(link_val, "NaN") && ~strcmpi(link_val, "missing")
                fprintf('   - Ο διακόπτης %s έχει Link: %s\n', sw_name, link_val);

                split_links = split(link_val, ',');
                for k = 1:length(split_links)
                    clean_link = strtrim(split_links{k});
                    if clean_link ~= ""
                        counter_src = counter_src + 1;
                        all_found_sources{counter_src} = char(clean_link);
                    end
                end
            else
                fprintf('   - Ο διακόπτης %s δεν έχει καταχωρημένο Link στο Sheet 2.\n', sw_name);
            end
        end

        all_found_sources = all_found_sources(1:counter_src);

        if ~isempty(all_found_sources)
            unique_sources = unique(all_found_sources);
        else
            unique_sources = {};
        end

        num_sources = length(unique_sources);

        fprintf('\n   > Συνολικές εναλακτικές πηγές/links που εντοπίστηκαν: %d\n', num_sources);
        if num_sources > 0
            fprintf('     (Links: %s)\n', strjoin(unique_sources, ', '));
        end

        % --- ΤΑ ΤΡΙΑ ΑΥΣΤΗΡΑ ΚΡΙΤΗΡΙΑ ΓΙΑ ΤΟ ΠΟΡΙΣΜΑ NO ---
        is_single_switch = (length(open_switches_list) == 1);
        is_at_edges = false;
        is_link_matching_line = false;

        if is_single_switch
            single_sw_name = open_switches_list{1};
            switch_pos = find(strcmp(line_elements, single_sw_name));

            if switch_pos == 1 || switch_pos == length(line_elements)
                is_at_edges = true;
            end

            match_row = network_elements(strcmp(string(network_elements.Element), single_sw_name), :);
            if height(match_row) > 1
                match_row = match_row(1, :); % ασφάλεια σε τυχόν διπλότυπες εγγραφές
            end
            link_str = "";
            if ~isempty(match_row) && ismember('Link', match_row.Properties.VariableNames)
                raw_l = match_row.Link;
                if ~isnumeric(raw_l)
                    if iscell(raw_l), raw_l = raw_l{1}; end
                    if ~isempty(raw_l)
                        link_str = strtrim(string(raw_l));
                    end
                end
            end

            target_clean = strrep(target_line, '_', '');

            if link_str == "" || strcmpi(link_str, "NaN") || strcmpi(link_str, "missing")
                is_link_matching_line = true;
            else
                split_l = split(link_str, ',');
                all_match = true;
                for l_idx = 1:length(split_l)
                    link_clean = strrep(strtrim(string(split_l{l_idx})), '_', '');
                    if ~strcmpi(link_clean, target_clean)
                        all_match = false;
                        break;
                    end
                end
                if all_match
                    is_link_matching_line = true;
                end
            end
        end

        if is_single_switch && is_at_edges && is_link_matching_line
            fprintf('-> [Τροχονόμος - Πόρισμα]: Is there an interconnection? NO\n');
            fprintf('   (Υπάρχει 1 ανάστροφη εξωτερική πηγή από την ίδια τη γραμμή -> Reverse Current)\n');
            fprintf('-> [Ροή]: --> Reverse Current --> Sequence --> Operation Note\n');

            [rev_switch_closed, saved_segments] = Reverse_Current(target_line, line_elements, open_switches_list, fault_element_indices, network_elements);

            % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ Sequence (το "Sequence" κουτί του flowchart) ---
            seq_actions = Sequence(target_line, line_elements_str, raw_input_faults, network_elements);

            % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ Operation_Note (το "Operation Note" κουτί του flowchart) ---
            close_details = struct('name', {}, 'existing_load', {}, 'new_load', {});
            source_list = {};
            if rev_switch_closed ~= ""
                close_details(1) = struct('name', char(rev_switch_closed), 'existing_load', NaN, 'new_load', NaN);
                source_list = {char(rev_switch_closed)};
            end
            open_list = {};
            for si = 1:numel(seq_actions)
                open_list = [open_list, seq_actions(si).switches_opened]; %#ok<AGROW>
            end
            Operation_Note(target_line, close_details, open_list, source_list);

            % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ Affected_Consumers (το "Affected Consumers" κουτί του flowchart) ---
            %     Ένα orphan group θεωρείται "σωσμένο" αν οι θέσεις του
            %     επικαλύπτονται με τα saved_segments που επέστρεψε το
            %     Reverse_Current (το Reverse Current μπορεί να σώσει το πολύ
            %     ΜΙΑ ζώνη - τη γειτονική στον εναλλακτικό διακόπτη).
            rescued_flags = false(1, numel(orphan_groups));
            if ~isempty(saved_segments)
                saved_positions = [];
                for k = 1:numel(saved_segments)
                    p = find(line_elements_str == string(saved_segments{k}));
                    saved_positions = [saved_positions, p]; %#ok<AGROW>
                end
                for g = 1:numel(orphan_groups)
                    grp = string(orphan_groups(g));
                    if contains(grp, "-")
                        parts = split(grp, "-");
                        i1 = find(line_elements_str == strtrim(parts(1)), 1);
                        i2 = find(line_elements_str == strtrim(parts(2)), 1);
                        if isempty(i1) || isempty(i2)
                            continue;
                        end
                        grange = min(i1, i2):max(i1, i2);
                    else
                        i1 = find(line_elements_str == strtrim(grp), 1);
                        if isempty(i1)
                            continue;
                        end
                        grange = i1;
                    end
                    rescued_flags(g) = any(ismember(grange, saved_positions));
                end
            end
            Affected_Consumers(target_line, line_elements_str, network_elements, fault_element_indices, orphan_groups, rescued_flags);

        else
            fprintf('-> [Τροχονόμος - Πόρισμα]: Is there an interconnection? YES\n');
            fprintf('   (Υπάρχουν πολλαπλά links, πολλαπλοί διακόπτες ή ο διακόπτης συνδέεται με ξένες γραμμές)\n');
            fprintf('-> [Ροή]: --> Compare Loads --> Sequence --> Operation Note\n');

            % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ compare_loads (χρησιμοποιεί το busbar_summary
            %     που ήδη υπολογίστηκε στην Ενότητα 2 - δεν ξανατρέχει το Check_Busbars) ---
            actions = compare_loads(target_line, orphan_groups, line_elements_str, ...
                network_elements, topology_data, fault_element_indices, busbar_summary, verbose);

            % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ Sequence (το "Sequence" κουτί του flowchart) ---
            seq_actions = Sequence(target_line, line_elements_str, raw_input_faults, network_elements);

            % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ Operation_Note (το "Operation Note" κουτί του flowchart) ---
            close_details = struct('name', {}, 'existing_load', {}, 'new_load', {});
            source_list = {};
            for gi = 1:numel(actions)
                close_details = [close_details, actions(gi).close_details]; %#ok<AGROW>
                if actions(gi).rescued && ~isempty(actions(gi).source)
                    source_list = [source_list, {actions(gi).source}]; %#ok<AGROW>
                end
            end
            open_list = {};
            for si = 1:numel(seq_actions)
                open_list = [open_list, seq_actions(si).switches_opened]; %#ok<AGROW>
            end
            Operation_Note(target_line, close_details, open_list, source_list);

            % --- ΚΛΗΣΗ ΤΗΣ ΣΥΝΑΡΤΗΣΗΣ Affected_Consumers (το "Affected Consumers" κουτί του flowchart) ---
            %     Εδώ έχουμε ΗΔΗ ακριβές rescued/not-rescued ανά group από το
            %     ίδιο το compare_loads (actions(g).rescued) - καμία ανάγκη
            %     για επικάλυψη θέσεων όπως στο Reverse Current.
            rescued_flags = [actions.rescued];
            Affected_Consumers(target_line, line_elements_str, network_elements, fault_element_indices, orphan_groups, rescued_flags);
        end

    end
    time = toc;
    fprintf('\n=========================================================\n');
    fprintf('==> Χρόνος εκτέλεσης: %.3f δευτερόλεπτα\n', time);
    fprintf('=========================================================\n');

end



