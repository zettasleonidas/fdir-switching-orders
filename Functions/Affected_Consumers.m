function Affected_Consumers(target_line, line_elements, network_elements, fault_element_indices, orphan_groups, rescued_flags)
% =========================================================================
% FUNCTION: Affected_Consumers
% -------------------------------------------------------------------------
% Καλύπτει (σε απλοποιημένη μορφή) το "Affected Consumers" ρουτίνα του
% flowchart. Δεν έχουμε πραγματική βάση καταναλωτών/GIS - χρησιμοποιούμε
% τα ίδια τα Type=Segment στοιχεία σαν "καταναλωτές". Τυπώνει ΔΥΟ
% ξεχωριστές, οριζόντιες λίστες:
%   1) Καταναλωτές ΕΝΤΟΣ του ίδιου του σφάλματος (fault_element_indices) -
%      αναπόφευκτα επηρεαζόμενοι, δηλωμένοι στο ίδιο το σφάλμα.
%   2) Καταναλωτές που παρέμειναν χωρίς ρεύμα επειδή το orphan group τους
%      ΔΕΝ σώθηκε τελικά (compare_loads/Reverse Current) - το "επιπλέον"
%      κόστος του σεναρίου.
%
% ΕΙΣΟΔΟΙ:
%   target_line             : π.χ. 'Line_9'
%   line_elements            : τοπολογία της γραμμής (cell ή string array)
%   network_elements         : table (Sheet2)
%   fault_element_indices    : output της find_faulty_isolation_zones
%   orphan_groups            : output της find_faulty_isolation_zones
%   rescued_flags            : λογικός πίνακας, ίδιο μήκος με orphan_groups
%                              - true αν το αντίστοιχο group ΤΕΛΙΚΑ σώθηκε
% =========================================================================

    line_elements = string(line_elements);

    fault_consumers = get_segment_names(unique(fault_element_indices), line_elements, network_elements);
    fault_load = sum_load(fault_consumers, network_elements);

    unresolved_consumers = {};
    for g = 1:numel(orphan_groups)
        if g <= numel(rescued_flags) && rescued_flags(g)
            continue; % αυτό το group σώθηκε - δεν είναι "unresolved"
        end
        [s_idx, e_idx] = parse_group_range(orphan_groups(g), line_elements);
        if isempty(s_idx)
            continue;
        end
        seg_names = get_segment_names(s_idx:e_idx, line_elements, network_elements);
        unresolved_consumers = [unresolved_consumers, seg_names]; %#ok<AGROW>
    end
    unresolved_consumers = unique(unresolved_consumers, 'stable');
    unresolved_load = sum_load(unresolved_consumers, network_elements);

    fprintf('\n---------------------------------------------------------\n');
    fprintf(' ΕΠΗΡΕΑΖΟΜΕΝΟΙ ΚΑΤΑΝΑΛΩΤΕΣ (AFFECTED CONSUMERS) — Γραμμή: %s\n', target_line);
    fprintf('---------------------------------------------------------\n');
    if isempty(fault_consumers)
        fprintf(' Καταναλωτές εντός του σφάλματος        : (κανένας)\n');
    else
        fprintf(' Καταναλωτές εντός του σφάλματος        : %s  (σύνολο: %g A)\n', ...
            strjoin(fault_consumers, ', '), fault_load);
    end
    if isempty(unresolved_consumers)
        fprintf(' Καταναλωτές χωρίς ρεύμα (μη διασωθέντες): (κανένας)\n');
    else
        fprintf(' Καταναλωτές χωρίς ρεύμα (μη διασωθέντες): %s  (σύνολο: %g A)\n', ...
            strjoin(unresolved_consumers, ', '), unresolved_load);
    end
    fprintf('---------------------------------------------------------\n');
    % ΣΗΜΕΙΩΣΗ: το συνολικό φορτίο υπολογίζεται από την ΕΝΩΣΗ των δύο
    % λιστών (όχι απλό fault_load+unresolved_load), γιατί σε σενάρια
    % Branch το "νεκρό εύρος" περιλαμβάνει και τα ίδια τα δηλωμένα
    % σφάλματα με αποτέλεσμα, τα κοινά segments θα μετριούνταν διπλά. Σε
    % σενάρια Stem οι δύο λίστες είναι ούτως ή άλλως αποκλειστικές
    % μεταξύ τους, οπότε η ένωση δίνει το ίδιο αποτέλεσμα με πριν.
    all_affected = unique([fault_consumers, unresolved_consumers], 'stable');
    total_load = sum_load(all_affected, network_elements);
    fprintf(' ΣΥΝΟΛΙΚΟ ΕΠΗΡΕΑΖΟΜΕΝΟ ΦΟΡΤΙΟ (και οι δύο κατηγορίες): %g A\n', total_load);
    fprintf('---------------------------------------------------------\n\n');
end

function total = sum_load(names, network_elements)
    total = 0;
    for i = 1:numel(names)
        total = total + get_element_load(names{i}, network_elements);
    end
end

function v = get_element_load(elem_name, network_elements)
    v = 0;
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember('Load', row.Properties.VariableNames)
        return;
    end
    raw = row.Load;
    if iscell(raw), raw = raw{1}; end
    val = double(raw);
    if ~isempty(val) && ~isnan(val)
        v = val;
    end
end

function names = get_segment_names(indices, line_elements, network_elements)
    names = {};
    for i = 1:numel(indices)
        idx = indices(i);
        if idx < 1 || idx > numel(line_elements)
            continue;
        end
        elem = char(line_elements(idx));
        if is_segment_element(elem, network_elements)
            names{end+1} = elem; %#ok<AGROW>
        end
    end
end

function [s_idx, e_idx] = parse_group_range(group_str, line_elements)
    s_idx = []; e_idx = [];
    g = string(group_str);
    if contains(g, "-")
        parts = split(g, "-");
        i1 = find(line_elements == strtrim(parts(1)), 1);
        i2 = find(line_elements == strtrim(parts(2)), 1);
        if isempty(i1) || isempty(i2)
            return;
        end
        s_idx = min(i1, i2);
        e_idx = max(i1, i2);
    else
        i1 = find(line_elements == strtrim(g), 1);
        if isempty(i1)
            return;
        end
        s_idx = i1;
        e_idx = i1;
    end
end

function tf = is_segment_element(elem_name, network_elements)
    tf = false;
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember('Type', row.Properties.VariableNames)
        return;
    end
    type_val = row.Type;
    if iscell(type_val), type_val = type_val{1}; end
    tf = contains(lower(string(type_val)), 'segment');
end
