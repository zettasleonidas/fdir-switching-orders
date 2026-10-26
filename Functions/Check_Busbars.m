function summary_results = Check_Busbars(excel_filename, verbose)
% =========================================================================
% FUNCTION: Check_Busbars
% -------------------------------------------------------------------------
% Ελέγχει αν είναι υπό τάση οι δύο ζυγοί (busbars) T24 και T648, εντοπίζοντας
% αναδρομικά (μέσω checkRecursive) όλες τις ενεργές πηγές που τους
% τροφοδοτούν είτε απευθείας είτε μέσω αλυσίδας άλλων γραμμών/ζυγών.
% Αποφασίζει επίσης ποιος από τους δύο είναι ο "κυρίαρχος ζυγός"
% (dominant_bus), με βάση το πλήθος άμεσων πηγών του καθενός, και tie-break
% κριτήριο σε ισοπαλία
%
% ΕΙΣΟΔΟΙ:
%   πρακτικά είναι hardcoded καθώς εδώ δίνονται τα busbar_targets = {'T24', 'T648'};
%   και τα  busbar_cols = {'Busbar_1', 'Busbar_2'};
%
%   excel_filename : ΠΡΟΑΙΡΕΤΙΚΟ, default 'Database/Elements_Data.xlsx'
%   verbose         : ΠΡΟΑΙΡΕΤΙΚΟ, true = τυπώνει αναλυτική αναφορά (default: true)
%
% ΕΞΟΔΟΣ:
%   summary_results : struct με πεδία 'T24', 'T648' (το καθένα με
%                      energized_sources/is_overall_true) και 'dominant_bus'
%                      ('T24' | 'T648' | 'NONE')
% =========================================================================
    if nargin < 1
        excel_filename = fullfile('Database', 'Elements_Data.xlsx');
    end
    if nargin < 2
        verbose = true; % προεπιλογή: ίδια συμπεριφορά με πριν, αν δεν δοθεί
    end

    if ~isfile(excel_filename)
        error('Το αρχείο Excel δεν βρέθηκε στη διαδρομή: %s', excel_filename);
    end
    
    topology_data = readtable(excel_filename, 'Sheet', 1);
    network_elements = readtable(excel_filename, 'Sheet', 2);
    
    elem_names_col = string(network_elements{:, 1});
    elem_states_col = network_elements{:, 3};
    element_map = containers.Map(elem_names_col, elem_states_col);
    
    busbar_targets = {'T24', 'T648'};
    busbar_cols = {'Busbar_1', 'Busbar_2'};
    summary_results = struct();
    
    for b = 1:length(busbar_targets)
        current_bus = busbar_targets{b};
        target_col_name = busbar_cols{b};
        
        if ~ismember(target_col_name, topology_data.Properties.VariableNames)
            continue;
        end
        
        col_data = topology_data.(target_col_name);
        switches_found = {};
        for i = 1:height(topology_data)
            val = col_data{i};
            if iscell(val), val = val{1}; end
            val_str = strtrim(char(string(val)));
            
            if ~isempty(val_str) && ~strcmpi(val_str, "missing") && ~strcmpi(val_str, "NaN") 
                if contains(val_str, current_bus)
                    switches_found{end+1} = val_str;                                                                                     %#ok<AGROW>
                end
            end
        end
        
        if isempty(switches_found)
            summary_results.(current_bus).energized_sources = {};
            summary_results.(current_bus).is_overall_true = false;
            continue;
        end
        
        var_names = topology_data.Properties.VariableNames;
        line_columns = var_names(startsWith(var_names, 'Line_'));
        energized_sources = {};
        
        for s = 1:length(switches_found)
            target_sw = switches_found{s};
            
            found_line_col = '';
            for c = 1:length(line_columns)
                col_name = line_columns{c};
                col_column_data = topology_data.(col_name);
                col_str_arr = string(table2cell(table(col_column_data))); 
                if any(col_str_arr == target_sw)
                    found_line_col = col_name;
                    break;
                end
            end
            
            if isempty(found_line_col), continue; end
            
            switch_state = -1;
            if isKey(element_map, target_sw)
                switch_state = element_map(target_sw);
            end
            
            if switch_state == 0, continue; end
            
            target_line_data = topology_data.(found_line_col);
            line_elements = {};
            for r = 1:height(topology_data)
                oe_val = target_line_data{r};
                if iscell(oe_val), oe_val = oe_val{1}; end
                oe_str = strtrim(char(string(oe_val)));
                if ~isempty(oe_str) && ~strcmpi(oe_str, "missing") && ~strcmpi(oe_str, "NaN") && ~strcmpi(oe_str, "undefined")
                    line_elements{end+1} = oe_str; %#ok<AGROW>
                end
            end
            
            if isempty(line_elements), continue; end
            
            switch_idx = find(strcmp(line_elements, target_sw));
            if ~isempty(switch_idx)
                if switch_idx(1) == 1
                    other_end_element = line_elements{end};
                else
                    other_end_element = line_elements{1};
                end
            else
                other_end_element = line_elements{end};
            end
            
            other_end_state = -1;
            if isKey(element_map, other_end_element)
                other_end_state = element_map(other_end_element);
            end
            
            if contains(other_end_element, 'T24') || contains(other_end_element, 'T648')
                sub_paths = checkRecursive(other_end_element, {target_sw}, topology_data, element_map);
                if ~isempty(sub_paths)
                    for p = 1:length(sub_paths)
                        energized_sources{end+1} = sprintf('%s (μέσω %s)', target_sw, sub_paths{p});                       %#ok<AGROW>
                    end
                end
            else
                if (switch_state == 1) && (other_end_state == 1)
                    energized_sources{end+1} = sprintf('%s (άμεσο άκρο: %s)', target_sw, other_end_element);                %#ok<AGROW>
                end
            end
        end
        
        summary_results.(current_bus).energized_sources = energized_sources;
        summary_results.(current_bus).is_overall_true = ~isempty(energized_sources);
    end
    
    % --- ΤΕΛΙΚΗ ΣΥΓΚΕΝΤΡΩΤΙΚΗ ΑΝΑΦΟΡΑ ---
    if verbose
        fprintf('\n========================================================\n');
        fprintf(' ΤΕΛΙΚΗ ΣΥΓΚΕΝΤΡΩΤΙΚΗ ΑΝΑΦΟΡΑ ΤΡΟΦΟΔΟΣΙΑΣ ΖΥΓΩΝ\n');
        fprintf('========================================================\n');
    end

    count_t24 = 0;
    count_t648 = 0;
    
    if isfield(summary_results, 'T24')
        res = summary_results.T24;
        if verbose
            if res.is_overall_true, status_str = 'true (υπό τάση)'; else, status_str = 'false (νεκρός ζυγός)'; end
            fprintf('\n* Ο ζυγός T24 είναι: %s\n', status_str);
            if ~isempty(res.energized_sources)
                fprintf('  Τροφοδοτείται από:\n');
            else
                fprintf('  (Δεν βρέθηκαν ενεργοί τροφοδότες)\n');
            end
        end
        for src = 1:length(res.energized_sources)
            if verbose
                fprintf('   - Από τον %s\n', res.energized_sources{src});
            end
            if contains(res.energized_sources{src}, 'άμεσο άκρο')
                count_t24 = count_t24 + 1;
            end
        end
    end
    
    if isfield(summary_results, 'T648')
        res = summary_results.T648;
        if verbose
            if res.is_overall_true, status_str = 'true (υπό τάση)'; else, status_str = 'false (νεκρός ζυγός)'; end
            fprintf('\n* Ο ζυγός T648 είναι: %s\n', status_str);
            if ~isempty(res.energized_sources)
                fprintf('  Τροφοδοτείται από:\n');
            else
                fprintf('  (Δεν βρέθηκαν ενεργοί τροφοδότες)\n');
            end
        end
        for src = 1:length(res.energized_sources)
            if verbose
                fprintf('   - Από τον %s\n', res.energized_sources{src});
            end
            if contains(res.energized_sources{src}, 'άμεσο άκρο')
                count_t648 = count_t648 + 1;
            end
        end
    end
    if verbose
        fprintf('========================================================\n');
        fprintf('\n-> Άμεσες πηγές T24: %d | Άμεσες πηγές T648: %d\n', count_t24, count_t648);
    end

    % TIE-BREAK: σε ισοπαλία, ελέγχουμε αν κάποιος ζυγός έχει άμεση πηγή
    % που είναι η ίδια μια transit-γραμμή (μηδενικού φορτίου, αποκλειστικά
    % αφιερωμένη στο να τροφοδοτεί τον ζυγό - π.χ. σαν τη Line_11). Αν
    % μόνο ο ένας έχει, κερδίζει αυτός. Αν κανένας ή και οι δύο, παραμένει
    % 'NONE'
    t24_has_transit = false;
    t648_has_transit = false;
    if isfield(summary_results, 'T24')
        for src = 1:length(summary_results.T24.energized_sources)
            entry = summary_results.T24.energized_sources{src};
            if contains(entry, 'άμεσο άκρο') && entry_is_transit_line(entry, topology_data, network_elements)
                t24_has_transit = true;
            end
        end
    end
    if isfield(summary_results, 'T648')
        for src = 1:length(summary_results.T648.energized_sources)
            entry = summary_results.T648.energized_sources{src};
            if contains(entry, 'άμεσο άκρο') && entry_is_transit_line(entry, topology_data, network_elements)
                t648_has_transit = true;
            end
        end
    end

    if count_t648 > count_t24
        dominant_bus = 'T648';
        if verbose, fprintf('=> [Busbar Ruling]: Ο κυρίαρχος ζυγός είναι ο T648 (%d έναντι %d).\n', count_t648, count_t24); end
    elseif count_t24 > count_t648
        dominant_bus = 'T24';
        if verbose, fprintf('=> [Busbar Ruling]: Ο κυρίαρχος ζυγός είναι ο T24 (%d έναντι %d).\n', count_t24, count_t648); end
    elseif t648_has_transit && ~t24_has_transit
        dominant_bus = 'T648';
        if verbose, fprintf('=> [Busbar Ruling]: Ισοπαλία (%d-%d) στις άμεσες πηγές, αλλά ο T648 έχει transit-γραμμή (μηδενικού φορτίου) -> κυρίαρχος T648.\n', count_t648, count_t24); end
    elseif t24_has_transit && ~t648_has_transit
        dominant_bus = 'T24';
        if verbose, fprintf('=> [Busbar Ruling]: Ισοπαλία (%d-%d) στις άμεσες πηγές, αλλά ο T24 έχει transit-γραμμή (μηδενικού φορτίου) -> κυρίαρχος T24.\n', count_t24, count_t648); end
    else
        dominant_bus = 'NONE';
        if verbose, fprintf('=> [Busbar Ruling]: Ισοδύναμοι ζυγοί (%d άμεσες πηγές) - καμία σαφής κυριαρχία.\n', count_t648); end
    end
    if verbose
        fprintf('========================================================\n\n');
    end

    summary_results.dominant_bus = dominant_bus;
end
% Αναδρομική ανίχνευση πηγής: ξεκινώντας από ένα busbar-στοιχείο, ψάχνει
% όλους τους ήδη-κλειστούς διακόπτες του ίδιου ζυγού, βρίσκει τη γραμμή
% του καθενός, προχωράει στο άλλο άκρο της, και συνεχίζει αναδρομικά αν
% κι εκείνο καταλήγει σε άλλο busbar - μέχρι να βρεθεί "Καθαρή Πηγή"
% (στοιχείο με "/" στο όνομα). Επιστρέφει ΟΛΑ τα πιθανά μονοπάτια που
% βρέθηκαν, σαν strings της μορφής "A -> B -> (Καθαρή Πηγή: X)".
function paths_found = checkRecursive(elem_name, visited_nodes, topology_data, element_map)
    paths_found = {};
    s_state = -1;
    if isKey(element_map, elem_name)
        s_state = element_map(elem_name);
    end
    if s_state == 1 && contains(elem_name, '/')
        paths_found{end+1} = ['(Καθαρή Πηγή: ' elem_name ')'];
        return;
    end
    if ismember(elem_name, visited_nodes), return; end
    visited_nodes{end+1} = elem_name; %#ok<AGROW>
    
    bus_id = ''; b_col = '';
    if contains(elem_name, 'T24'), bus_id = 'T24'; b_col = 'Busbar_1';
    elseif contains(elem_name, 'T648'), bus_id = 'T648'; b_col = 'Busbar_2';
    else, return;
    end
    
    if ismember(b_col, topology_data.Properties.VariableNames)
        col_data = topology_data.(b_col);
        var_names = topology_data.Properties.VariableNames;
        line_cols = var_names(startsWith(var_names, 'Line_'));
        
        for i = 1:height(topology_data)
            val = col_data{i};
            if iscell(val), val = val{1}; end
            v_str = strtrim(char(string(val)));
            if ~isempty(v_str) && ~strcmpi(v_str, "missing") && contains(v_str, bus_id)
                sw_st = -1;
                if isKey(element_map, v_str), sw_st = element_map(v_str); end
                if sw_st == 1
                    f_line = '';
                    for c = 1:length(line_cols)
                        lc = line_cols{c};
                        cv_data = topology_data.(lc);
                        cv_str_arr = string(table2cell(table(cv_data)));
                        if any(cv_str_arr == v_str), f_line = lc; break; end
                    end
                    if ~isempty(f_line)
                        l_data = topology_data.(f_line);
                        l_elems = {};
                        for r = 1:height(topology_data)
                            ov = l_data{r};
                            if iscell(ov), ov = ov{1}; end
                            os = strtrim(char(string(ov)));
                            if ~isempty(os) && ~strcmpi(os, "missing"), l_elems{end+1} = os; %#ok<AGROW>
                            end
                        end
                        if ~isempty(l_elems)
                            sw_idx_rec = find(strcmp(l_elems, v_str));
                            if ~isempty(sw_idx_rec) && sw_idx_rec(1) == 1, next_elem = l_elems{end};
                            else, next_elem = l_elems{1};
                            end
                            sub_paths = checkRecursive(next_elem, visited_nodes, topology_data, element_map);
                            for p = 1:length(sub_paths)
                                paths_found{end+1} = [elem_name ' -> ' v_str ' -> ' sub_paths{p}]; %#ok<AGROW>
                            end
                        end
                    end
                end
            end
        end
    end
end

function tf = entry_is_transit_line(entry_str, topology_data, network_elements)
    % Βρίσκει τον διακόπτη πλευράς ζυγού μέσα στο (προ-formatted) string
    % ενός energized_sources entry ("SW (άμεσο άκρο: ...)"), εντοπίζει τη
    % ΔΙΚΗ ΤΟΥ γραμμή, και επιστρέφει true αν εκείνη η γραμμή έχει
    % μηδενικό συνολικό Load (δηλαδή είναι transit-γραμμή, όχι
    % πραγματικός καταναλωτής  π.χ. σαν τη Line_11).
    tf = false;
    tok = regexp(entry_str, '^(.*?)\s\(άμεσο άκρο', 'tokens', 'once');
    if isempty(tok)
        return;
    end
    sw_name = strtrim(tok{1});

    var_names = topology_data.Properties.VariableNames;
    line_cols = var_names(startsWith(var_names, 'Line_'));

    for c = 1:numel(line_cols)
        col_data = topology_data.(line_cols{c});
        elems = {};
        for r = 1:height(topology_data)
            v = col_data{r};
            if iscell(v), v = v{1}; end
            s = strtrim(char(string(v)));
            if ~isempty(s) && ~strcmpi(s, "missing")
                elems{end+1} = s; %#ok<AGROW>
            end
        end
        if any(strcmp(elems, sw_name))
            tf = (line_total_load(elems, network_elements) == 0);
            return;
        end
    end
end

function total = line_total_load(elems, network_elements)
    total = 0;
    for i = 1:numel(elems)
        row = network_elements(strcmp(network_elements.Element, elems{i}), :);
        if height(row) > 1, row = row(1, :); end
        if isempty(row) || ~ismember('Type', row.Properties.VariableNames), continue; end
        type_val = row.Type;
        if iscell(type_val), type_val = type_val{1}; end
        if ~contains(lower(string(type_val)), 'segment'), continue; end
        if ~ismember('Load', row.Properties.VariableNames), continue; end
        load_val = row.Load;
        if iscell(load_val), load_val = load_val{1}; end
        v = double(load_val);
        if ~isempty(v) && ~isnan(v)
            total = total + v;
        end
    end
end
