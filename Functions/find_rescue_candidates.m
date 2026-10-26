function candidates = find_rescue_candidates(orphan_group_str, target_line, ...
        line_elements, network_elements, topology_data, ...
        fault_element_indices, busbar_summary, verbose)
% =========================================================================
% FUNCTION: find_rescue_candidates
% -------------------------------------------------------------------------
% Για ένα (ήδη εντοπισμένο) ορφανό group μιας stem γραμμής, ψάχνει προς τα
% αριστερά και προς τα δεξιά όλα τα πιθανά "σημεία σωτηρίας" (ανοιχτά CB
% με Capacity+Link εκτός ζώνης ασφαλείας γύρω από τα σφάλματα), χτίζει την
% αλυσίδα CB μέχρι την τελική πηγή (απευθείας γραμμή ή μέσω busbar) και
% ελέγχει αν ΟΛΟΙ οι κρίκοι της αλυσίδας αντέχουν το επιπλέον φορτίο.
%
% ΔΕΝ αποφασίζει ποιο CB
% τελικά θα ανοίξει/κλείσει — απλά επιστρέφει όλους τους έγκυρους/άκυρους
% candidates με τα στοιχεία τους, ώστε η compare_loads να διαλέξει.
%
% ΑΠΛΟΠΟΙΗΣΗ νο1: όταν το Link ενός candidate δείχνει busbar (T24/T648),
% ελέγχουμε ΟΛΕΣ τις ήδη ενεργές πηγές του busbar (busbar_summary), μία
% ξεχωριστή αλυσίδα/candidate ανά πηγή — η compare_loads διαλέγει μετά τη
% λιγότερο επιβαρυμένη μέσω του ήδη υπάρχοντος κριτηρίου max(min_margin).
% Το όνομα CB εξάγεται από το (προ-formatted) string του busbar_summary
% μέσω regex που εντοπίζει ρητά τους δείκτες " (άμεσο άκρο" / " (μέσω"
% (όχι απλό split σε κενό, γιατί τα ονόματα μπορεί να έχουν κενά, π.χ.
% "(20)T648 Pl.2"). Αν χρειαστεί μελλοντικά ακριβέστερος έλεγχος σε βαθιά
% φωλιασμένα busbar to busbar σενάρια, θα χρειαστεί το Check_Busbars να
% επιστρέφει δομημένα δεδομένα αντί για έτοιμα strings.
%
% ΑΠΛΟΠΟΙΗΣΗ νο2: όταν το Link ενός candidate δείχνει σε ΑΛΛΗ γραμμή
% (όχι στην ίδια target_line), θεωρούμε ΟΛΗ τη donor γραμμή σαν πηγή
% υπολογισμού existing_load, χωρίς να ελέγχουμε αν η ΙΔΙΑ η donor γραμμή
% έχει τα δικά της ενεργά σφάλματα που θα έκοβαν τη συνέχεια πριν το
% σημείο σύνδεσης. Αν χρειαστεί, θα πρέπει να περνάμε και τα fault
% δεδομένα της donor γραμμής σαν είσοδο.
%
%
% ΕΙΣΟΔΟΙ:
%   orphan_group_str      : π.χ. "Al4-Al8" ή "Al5" (ένα group από τα
%                            orphan_groups που επιστρέφει η
%                            find_faulty_isolation_zones)
%   target_line             : π.χ. 'Line_1' (μόνο για μηνύματα/debug)
%   line_elements           : string array, η τοπολογία ΤΗΣ ΓΡΑΜΜΗΣ target_line
%   network_elements        : table (Sheet2)
%   topology_data           : table (Sheet1, όλες οι γραμμές - χρειάζεται
%                              για να ψάξουμε donor lines/busbars)
%   fault_element_indices   : θέσεις σφάλματος (από την
%                              find_faulty_isolation_zones)
%   busbar_summary          : ήδη υπολογισμένο αποτέλεσμα του Check_Busbars
%
% ΕΞΟΔΟΣ:
%   candidates : struct array, ένα per candidate, με πεδία:
%       .side          'L' ή 'R'
%       .candidate_cb  όνομα του πρώτου CB της αλυσίδας
%       .orphan_load   το φορτίο που ζητάει το orphan group
%       .chain         struct array [name, existing_load, capacity,
%                       new_load, margin, ok] - ένα per κρίκο αλυσίδας
%       .valid         true μόνο αν ΟΛΟΙ οι κρίκοι είναι ok
%       .min_margin    min(chain.margin) - χρησιμοποιείται για σύγκριση
%                       candidates μεταξύ τους (μεγαλύτερο = καλύτερο)
% =========================================================================

    if nargin < 8
        verbose = true; % προεπιλογή: ίδια συμπεριφορά με πριν
    end

    candidates = struct('side', {}, 'candidate_cb', {}, 'orphan_load', {}, ...
        'chain', {}, 'valid', {}, 'min_margin', {}, 'option_number', {});

    % --- 0. Parse του orphan group σε start/end indices ---
    [start_idx, end_idx] = parse_group_indices(orphan_group_str, line_elements);
    if isempty(start_idx)
        fprintf('[ΠΡΟΣΟΧΗ] [find_rescue_candidates]: Δεν μπόρεσα να αναγνωρίσω το group "%s" στη γραμμή %s.\n', orphan_group_str, target_line);
        return;
    end

    orphan_load = compute_group_load(start_idx, end_idx, line_elements, network_elements);
    if verbose
        fprintf('\n--- Αναζήτηση εναλλακτικής τροφοδότησης: τμήμα "%s" (θέσεις %d-%d), ζητούμενο φορτίο %g A ---\n\n', ...
            orphan_group_str, start_idx, end_idx, orphan_load);
    end

    % --- 1. "Ζώνη ασφαλείας": fault στοιχεία + οι άμεσοι γείτονές τους ---
    unsafe_zone = unique([fault_element_indices, fault_element_indices - 1, fault_element_indices + 1]);
    unsafe_zone = unsafe_zone(unsafe_zone >= 1 & unsafe_zone <= numel(line_elements));

    % --- 2. Σάρωση ΑΡΙΣΤΕΡΑ, ΔΕΞΙΑ, & ΕΣΩΤΕΡΙΚΑ ---
    %     Η σάρωση εκτός group (αριστερά/δεξιά) μαζεύει candidates πέρα
    %     από τα άκρα του group. ΕΠΙΠΛΕΟΝ, επειδή η ομαδοποίηση των
    %     ορφανών segments "καταπίνει" ενδιάμεσα CB (π.χ. έναν κόμβο σαν
    %     το T30c ανάμεσα σε δύο ορφανά segments της ίδιας γραμμής, αφού
    %     δεν υπάρχει fault ανάμεσά τους), σαρώνουμε ΚΑΙ το εσωτερικό του
    %     ίδιου του group (start_idx+1 : end_idx-1) για τυχόν candidate
    %     CB που βρίσκεται "θαμμένο" μέσα στο group.
    left_names     = scan_for_candidates(start_idx - 1, -1, 1, line_elements, network_elements, fault_element_indices, unsafe_zone);
    right_names    = scan_for_candidates(end_idx + 1, 1, numel(line_elements), line_elements, network_elements, fault_element_indices, unsafe_zone);
    interior_names = string([]);
    if end_idx - 1 >= start_idx + 1
        interior_names = scan_for_candidates(start_idx + 1, 1, end_idx - 1, line_elements, network_elements, fault_element_indices, unsafe_zone);
    end

    for k = 1:numel(left_names)
        candidates = [candidates, build_candidate('L', left_names(k), orphan_load, target_line, line_elements, network_elements, topology_data, busbar_summary)]; %#ok<AGROW>
    end
    for k = 1:numel(right_names)
        candidates = [candidates, build_candidate('R', right_names(k), orphan_load, target_line, line_elements, network_elements, topology_data, busbar_summary)]; %#ok<AGROW>
    end
    for k = 1:numel(interior_names)
        candidates = [candidates, build_candidate('M', interior_names(k), orphan_load, target_line, line_elements, network_elements, topology_data, busbar_summary)]; %#ok<AGROW>
    end

    % --- 3. Αρίθμηση επιλογών + Εκτύπωση περίληψης ---
    for c = 1:numel(candidates)
        candidates(c).option_number = c;
    end

    if verbose
        if isempty(candidates)
            fprintf('   Δεν εντοπίστηκε κανένας πιθανός δρόμος τροφοδότησης (ούτε αριστερά, δεξιά, ούτε εσωτερικά).\n\n');
        else
            valid_count = sum([candidates.valid]);
            fprintf('   Εντοπίστηκαν %d πιθανές αλυσίδες τροφοδότησης (%d έγκυρες):\n\n', numel(candidates), valid_count);
            for c = 1:numel(candidates)
                cand = candidates(c);
                chain_names = strjoin({cand.chain.name}, ' -> ');
                side_label = tern(strcmp(cand.side,'M'), 'εσωτερικός κόμβος', cand.side);
                fprintf('   Αλυσίδα %d [%s, μέσω %s]: %s\n', c, side_label, cand.candidate_cb, chain_names);
                if cand.valid
                    fprintf('      Κατάσταση: ΕΓΚΥΡΗ (διαθέσιμο περιθώριο %g A)\n', cand.min_margin);
                else
                    fprintf('      Κατάσταση: ΜΗ ΕΓΚΥΡΗ (κάποιος κρίκος της αλυσίδας δεν αντέχει το φορτίο)\n');
                end
                for lidx = 1:numel(cand.chain)
                    l = cand.chain(lidx);
                    fprintf('         %s: υπάρχον %g A + νέο %g A = %g A (όριο %g A, περιθώριο %g A) %s\n', ...
                        l.name, l.existing_load, orphan_load, l.new_load, l.capacity, l.margin, ...
                        tern(l.needs_close, '[χρειάζεται κλείσιμο]', '[ήδη κλειστό]'));
                end
                fprintf('\n');
            end
        end
    end
end


% =========================================================================
% ΒΟΗΘΗΤΙΚΕΣ ΣΥΝΑΡΤΗΣΕΙΣ
% =========================================================================

function [start_idx, end_idx] = parse_group_indices(orphan_group_str, line_elements)
    start_idx = []; end_idx = [];
    g = string(orphan_group_str);
    if contains(g, "-")
        parts = split(g, "-");
        i1 = find(line_elements == strtrim(parts(1)), 1);
        i2 = find(line_elements == strtrim(parts(2)), 1);
        if isempty(i1) || isempty(i2), return; end
        start_idx = min(i1, i2);
        end_idx = max(i1, i2);
    else
        i1 = find(line_elements == strtrim(g), 1);
        if isempty(i1), return; end
        start_idx = i1; end_idx = i1;
    end
end

function total_load = compute_group_load(start_idx, end_idx, line_elements, network_elements)
    total_load = 0;
    for idx = start_idx:end_idx
        elem = char(line_elements(idx));
        if is_type(elem, network_elements, 'segment')
            v = get_numeric_field(elem, network_elements, 'Load');
            if ~isnan(v), total_load = total_load + v; end
        end
    end
end

function found_names = scan_for_candidates(start_pos, step, limit_pos, line_elements, ...
        network_elements, fault_element_indices, unsafe_zone)
    % Σαρώνει από start_pos προς την κατεύθυνση step (±1) μέχρι limit_pos,
    % σταματώντας ΜΟΝΟ όταν χτυπήσει fault_element_indices. Μαζεύει ΟΛΑ τα
    % elements που πληρούν τα κριτήρια candidate (δεν σταματάει στο πρώτο).
    found_names = string([]);
    idx = start_pos;
    while (step == -1 && idx >= limit_pos) || (step == 1 && idx <= limit_pos)
        if ismember(idx, fault_element_indices)
            break; % πραγματικό σφάλμα -> τέλος αυτής της πλευράς
        end
        if ~ismember(idx, unsafe_zone) % εκτός ζώνης ασφαλείας γύρω από fault
            elem = char(line_elements(idx));
            if is_rescue_candidate(elem, network_elements)
                found_names(end+1) = string(elem); %#ok<AGROW>
            end
        end
        idx = idx + step;
    end
end

function tf = is_rescue_candidate(elem_name, network_elements)
    tf = false;
    state_val = get_numeric_field(elem_name, network_elements, 'State');
    capacity_val = get_numeric_field(elem_name, network_elements, 'Capacity');
    link_val = get_link_value(elem_name, network_elements);
    if ~isnan(state_val) && state_val == 0 && ~isnan(capacity_val) && link_val ~= ""
        tf = true;
    end
end

function cands = build_candidate(side, cand_name, orphan_load, target_line, line_elements, network_elements, topology_data, busbar_summary)
    cand_name = char(cand_name);
    chains = resolve_chains(cand_name, target_line, line_elements, network_elements, topology_data, busbar_summary);

    cands = struct('side', {}, 'candidate_cb', {}, 'orphan_load', {}, ...
        'chain', {}, 'valid', {}, 'min_margin', {}, 'option_number', {});

    for ci = 1:numel(chains)
        chain = chains{ci};
        for i = 1:numel(chain)
            chain(i).new_load = chain(i).existing_load + orphan_load;
            chain(i).margin = chain(i).capacity - chain(i).new_load;
            chain(i).ok = ~isnan(chain(i).capacity) && chain(i).margin >= 0;
            % needs_close = true μόνο αν το State είναι γνωστό ΚΑΙ ίσο με 0
            % (ανοιχτό). Αν το State δεν βρέθηκε (NaN), δεν δίνουμε ποτέ
            % εντολή κλεισίματος σε κάτι άγνωστο - το σημειώνουμε ως ήδη
            % κλειστό/χωρίς ενέργεια, για ασφάλεια.
            chain(i).needs_close = ~isnan(chain(i).state) && chain(i).state == 0;
        end

        all_ok = ~isempty(chain) && all([chain.ok]);
        if isempty(chain)
            min_margin = -Inf;
        else
            min_margin = min([chain.margin]);
        end

        cands(end+1) = struct('side', side, 'candidate_cb', cand_name, 'orphan_load', orphan_load, ...
            'chain', chain, 'valid', all_ok, 'min_margin', min_margin, 'option_number', NaN); %#ok<AGROW>
    end
end

function chains = resolve_chains(candidate_name, target_line, line_elements, network_elements, topology_data, busbar_summary)
    % Επιστρέφει ΛΙΣΤΑ (cell array) πιθανών αλυσίδων από τον candidate
    % μέχρι την τελική πηγή. Συνήθως μία (Περίπτωση Α - άλλη γραμμή,
    % self-reference, ή χωρίς Link), αλλά ΠΟΛΛΑΠΛΕΣ όταν ο candidate
    % συνδέεται σε busbar που έχει περισσότερες από μία ήδη ενεργές πηγές
    % (Περίπτωση Β) — έτσι ώστε η compare_loads να μπορεί να διαλέξει,
    % μέσω του ήδη υπάρχοντος κριτηρίου max(min_margin), τη διαδρομή που
    % επιβαρύνει λιγότερο τα εμπλεκόμενα CB.
    base_link = struct('name', candidate_name, ...
        'existing_load', 0, ...
        'capacity', get_numeric_field(candidate_name, network_elements, 'Capacity'), ...
        'state', get_numeric_field(candidate_name, network_elements, 'State'));
    single_chain = struct('name', {}, 'existing_load', {}, 'capacity', {}, 'state', {});
    single_chain(1) = base_link;
    chains = {single_chain}; % προεπιλογή: μονός κρίκος

    link_val = get_link_value(candidate_name, network_elements);
    if link_val == ""
        return; % δεν έχει καν Link -> η αλυσίδα σταματάει εδώ (μόνο 1 κρίκος)
    end

    % --- Το Link μπορεί να έχει ΠΟΛΛΑΠΛΕΣ τιμές, χωρισμένες με κόμμα ---
    % π.χ. "Line9, Busbar_2" σημαίνει "ανήκω στη Line9 ΚΑΙ επιπλέον
    % συνδέομαι με τον ζυγό Busbar_2". Σπάμε σε tokens και αγνοούμε το
    % token που είναι self-reference στην ΙΔΙΑ target_line (είναι απλώς
    % "ανήκω εδώ", όχι πραγματική εναλλακτική πηγή — βλ. παρακάτω γιατί
    % δεν προεκτείνουμε ποτέ την αλυσίδα μέσω αυτού). Από τα υπόλοιπα
    % tokens παίρνουμε το πρώτο μη-self για να συνεχίσουμε την αλυσίδα.
    %
    % ΓΙΑΤΙ ΑΓΝΟΟΥΜΕ ΤΟ SELF-REFERENCE (π.χ. 40/VIII με Link="Line2" ενώ
    % target_line είναι ήδη η Line2): Αυτό ΔΕΝ είναι "άλλη γραμμή-δότης"
    % — είναι το κλασικό reverse-feed άκρο της ίδιας γραμμής. Δεν
    % προεκτείνουμε την αλυσίδα μέσω αυτού, γιατί (α) εννοιολογικά ο
    % candidate ΕΙΝΑΙ ήδη η πηγή, όχι σύνδεσμος προς άλλη πηγή, και (β)
    % ακόμα κι αν προεκτείναμε, το "existing load" ολόκληρης της
    % target_line θα ήταν λάθος αφού η ίδια η target_line έχει ήδη
    % σφάλματα στη μέση της που κόβουν τη συνέχεια.
    link_tokens = strtrim(split(link_val, ','));
    target_clean = string(lower(strrep(target_line, '_', '')));

    resolved_token = "";
    for t = 1:numel(link_tokens)
        tok_clean = string(lower(strrep(link_tokens(t), '_', '')));
        if tok_clean ~= target_clean
            resolved_token = link_tokens(t);
            break;
        end
    end

    if resolved_token == ""
        return; % Μόνο self-reference βρέθηκε -> μονός κρίκος (ήδη στο chains)
    end

    var_names = topology_data.Properties.VariableNames;
    line_cols = var_names(startsWith(var_names, 'Line_'));

    % --- Περίπτωση Α: το token δείχνει απευθείας άλλη Line_x ---
    matched_line = '';
    token_clean = lower(strrep(resolved_token, '_', ''));
    for c = 1:numel(line_cols)
        if strcmp(lower(strrep(line_cols{c}, '_', '')), token_clean)
            matched_line = line_cols{c};
            break;
        end
    end

    if ~isempty(matched_line)
        % --- Πρώτα ψάχνουμε αν ο candidate είναι κόμβος-CB δίπλα σε ένα
        %     "γέφυρα" segment (π.χ. BClx) που εμφανίζεται ΚΑΙ στη donor
        %     γραμμή — αν ναι, ο "δίδυμος" κόμβος-CB εκεί (π.χ. B135c)
        %     είναι ξεχωριστός φυσικός διακόπτης με ΔΙΚΟ ΤΟΥ Capacity και
        %     πρέπει να μπει σαν ενδιάμεσος κρίκος πριν την τελική πηγή.
        [bridge_cb, bridge_line] = find_bridge_partner_cb( ...
            candidate_name, target_line, line_elements, topology_data, network_elements);

        chain = single_chain;
        donor_col_for_source = matched_line;
        if ~isempty(bridge_cb)
            cap_bridge = get_numeric_field(bridge_cb, network_elements, 'Capacity');
            existing_bridge = get_existing_load_via_switch(bridge_cb, topology_data, network_elements);
            state_bridge = get_numeric_field(bridge_cb, network_elements, 'State');
            chain(end+1) = struct('name', bridge_cb, 'existing_load', existing_bridge, 'capacity', cap_bridge, 'state', state_bridge);
            if ~isempty(bridge_line)
                donor_col_for_source = bridge_line; % συνεχίζουμε την αναζήτηση πηγής από ΕΚΕΙ
            end
        end

        donor_elems = string(rmmissing(topology_data.(donor_col_for_source)));
        donor_elems = donor_elems(donor_elems ~= "");
        if ~isempty(donor_elems)
            first_e = char(strtrim(donor_elems(1)));
            last_e = char(strtrim(donor_elems(end)));
            far_source_name = '';
            if check_if_source(first_e, network_elements)
                far_source_name = first_e;
            elseif check_if_source(last_e, network_elements)
                far_source_name = last_e;
            end
            if ~isempty(far_source_name)
                existing_load = sum_line_segment_load(donor_elems, network_elements);
                cap_source = get_numeric_field(far_source_name, network_elements, 'Capacity');
                state_source = get_numeric_field(far_source_name, network_elements, 'State');
                chain(end+1) = struct('name', far_source_name, 'existing_load', existing_load, 'capacity', cap_source, 'state', state_source);
            end
        end
        chains = {chain};
        return;
    end

    % --- Περίπτωση Β: το token δείχνει busbar (Busbar_1/T24 ή Busbar_2/T648) ---
    % Ελέγχουμε ΟΛΕΣ τις ήδη ενεργές πηγές του busbar (όχι μόνο την
    % πρώτη) — κάθε μία γίνεται ΞΕΧΩΡΙΣΤΗ αλυσίδα/candidate, ώστε η
    % compare_loads να διαλέξει αυτή που επιβαρύνει λιγότερο.
    bus_id = '';
    if strcmpi(resolved_token, 'Busbar_1') || contains(lower(resolved_token), 't24')
        bus_id = 'T24';
    elseif strcmpi(resolved_token, 'Busbar_2') || contains(lower(resolved_token), 't648')
        bus_id = 'T648';
    end

    if ~isempty(bus_id) && isfield(busbar_summary, bus_id) && ...
            isfield(busbar_summary.(bus_id), 'energized_sources') && ...
            ~isempty(busbar_summary.(bus_id).energized_sources)

        sources = busbar_summary.(bus_id).energized_sources;
        multi_chains = {};
        for si = 1:numel(sources)
            path_str = char(sources{si});

            bus_switch_name = extract_switch_name_from_path(path_str);
            if isempty(bus_switch_name)
                continue;
            end

            % --- ΑΠΟΡΡΙΨΗ MESH-ΜΟΝΟΠΑΤΙΩΝ ---
            % Αν η γραμμή του bus_switch_name έχει busbar-άκρα ΚΑΙ στις
            % δύο πλευρές (π.χ. Line_7: T648 ΚΑΙ T24) ΚΑΙ ο δικός της
            % κυρίαρχος ζυγός είναι ΑΚΡΙΒΩΣ αυτός τον οποίο τώρα εξετάζουμε
            % (bus_id) — τότε αυτή η γραμμή ΤΡΟΦΟΔΟΤΕΙΤΑΙ από τον bus_id,
            % δεν τον τροφοδοτεί. Δεν μπορεί να είναι ταυτόχρονα και τα
            % δύο (θα δημιουργούσε mesh) — απορρίπτουμε ολόκληρη αυτή την
            % επιλογή, δεν μπαίνει καν σαν candidate.
            if is_own_dominant_bus_consumer(bus_switch_name, bus_id, topology_data, network_elements, busbar_summary)
                continue;
            end

            chain = single_chain; % candidate
            cap_bus = get_numeric_field(bus_switch_name, network_elements, 'Capacity');
            existing_load_bus = get_existing_load_via_switch(bus_switch_name, topology_data, network_elements, bus_id, busbar_summary);
            state_bus = get_numeric_field(bus_switch_name, network_elements, 'State');
            chain(end+1) = struct('name', bus_switch_name, 'existing_load', existing_load_bus, 'capacity', cap_bus, 'state', state_bus);

            % --- Συνέχεια της αλυσίδας μέχρι την ΠΡΑΓΜΑΤΙΚΗ τελική πηγή ---
            % Το path_str είτε είναι "SW (άμεσο άκρο: OTHER)" - οπότε το
            % OTHER είναι η ίδια η τελική πηγή, με δικό της Capacity - είτε
            % "SW (μέσω A -> B -> ... -> (Καθαρή Πηγή: X))" - οπότε ΟΛΟΙ οι
            % ενδιάμεσοι πραγματικοί διακόπτες (A, B, ...) ΚΑΙ η τελική
            % πηγή X πρέπει να ελεγχθούν ξεχωριστά, ο καθένας με το δικό
            % του Capacity.
            direct_marker = ' (άμεσο άκρο: ';
            via_marker = ' (μέσω ';
            d_idx = strfind(path_str, direct_marker);
            v_idx = strfind(path_str, via_marker);

            if ~isempty(d_idx)
                other_end = strtrim(path_str(d_idx(1)+length(direct_marker) : end-1));
                cap_other = get_numeric_field(other_end, network_elements, 'Capacity');
                state_other = get_numeric_field(other_end, network_elements, 'State');
                % Το other_end ΕΙΝΑΙ η ενεργή πηγή (π.χ. 41/VIII) - κανονικά
                % ήδη τροφοδοτεί όλο το φορτίο της δικής της γραμμής, οπότε
                % υπολογίζουμε αυτό ξεχωριστά (όχι με απλή αναχρησιμοποίηση
                % του existing_load_bus, που θα ήταν 0 σε γραμμές με δικό
                % τους πραγματικό φορτίο). ΕΞΑΙΡΕΣΗ: αν η γραμμή είναι
                % μηδενικού-φορτίου transit γραμμή (π.χ. Line_11), το
                % other_end ΔΕΝ τροφοδοτεί δικό της φορτίο - τροφοδοτεί
                % ΑΚΡΙΒΩΣ ό,τι ήδη υπολογίσαμε (με το transitive κομμάτι
                % συμπεριλαμβανομένο) για το bus_switch_name - ίδιο
                % φυσικό ρεύμα, μετρημένο στην άλλη άκρη της ίδιας γραμμής.
                existing_other = get_source_line_load(other_end, topology_data, network_elements);
                if existing_other == 0
                    existing_other = existing_load_bus;
                end
                chain(end+1) = struct('name', other_end, 'existing_load', existing_other, 'capacity', cap_other, 'state', state_other);
            elseif ~isempty(v_idx)
                inner = path_str(v_idx(1)+length(via_marker) : end-1); % αφαιρεί το "(μέσω " και το τελικό ")"
                extra_links = expand_recursive_path(inner, network_elements, topology_data, busbar_summary);
                for li = 1:numel(extra_links)
                    chain(end+1) = extra_links(li); %#ok<AGROW>
                end
            end

            multi_chains{end+1} = chain; %#ok<AGROW>
        end
        if ~isempty(multi_chains)
            chains = multi_chains;
        end
    end
end

function name = extract_switch_name_from_path(path_str)
    % Το path_str (από το busbar_summary) έχει τη μορφή
    % "SW_NAME (άμεσο άκρο: ...)" ή "SW_NAME (μέσω A -> B -> ...)". Το
    % SW_NAME μπορεί να περιέχει ΚΕΝΑ (π.χ. "(20)T648 Pl.2") και ΞΕΚΙΝΑ
    % με "(" — άρα δεν μπορούμε απλά να κόψουμε στο πρώτο κενό ή στην
    % πρώτη παρένθεση. Ψάχνουμε ρητά τον δείκτη " (άμεσο άκρο" ή " (μέσω"
    % που ΠΑΝΤΑ ακολουθεί αμέσως μετά το πλήρες όνομα.
    name = '';
    tok = regexp(path_str, '^(.*?)\s\((?:άμεσο άκρο|μέσω)', 'tokens', 'once');
    if ~isempty(tok)
        name = strtrim(tok{1});
    end
end

function links = expand_recursive_path(inner, network_elements, topology_data, busbar_summary)
    % Το "inner" είναι το περιεχόμενο μέσα στο "(μέσω ...)", μορφής
    % "A -> B -> ... -> (Καθαρή Πηγή: X)". Σπάμε σε tokens με "->".
    % Για κάθε ενδιάμεσο token: αν αντιστοιχεί σε πραγματική γραμμή του
    % Sheet2 ΜΕ Capacity, το προσθέτουμε σαν ξεχωριστό κρίκο (με δικό του
    % existing_load μέσω get_existing_load_via_switch) — διαφορετικά είναι
    % απλώς ενδιάμεση "ετικέτα αναφοράς" της αναδρομής (όχι φυσικός
    % διακόπτης) και το αγνοούμε. Το τελευταίο token, "(Καθαρή Πηγή: X)",
    % είναι πάντα η τελική ρίζα-πηγή — το X προστίθεται σαν τελευταίος
    % κρίκος, με existing_load = το φορτίο που ΗΔΗ τροφοδοτεί σήμερα (το
    % άθροισμα Load της γραμμής όπου το X είναι τερματικό στοιχείο) — όχι
    % 0, γιατί το X είναι ενεργή πηγή, όχι απλός διακόπτης-πλευράς-ζυγού.
    %
    % Για κάθε ενδιάμεσο πραγματικό διακόπτη, το bus_id του (ποιος ζυγός
    % τον αφορά, για το transit-load check) συνάγεται από το ΙΔΙΟ του το
    % όνομα (περιέχει "T24" ή "T648"), αφού η αναδρομή μπορεί να περνάει
    % από διαφορετικό ζυγό σε κάθε hop.
    links = struct('name', {}, 'existing_load', {}, 'capacity', {}, 'state', {});
    tokens = strtrim(split(string(inner), "->"));

    for i = 1:numel(tokens)
        tok = tokens(i);
        src_tok = regexp(tok, '^\(Καθαρή Πηγή:\s*(.+?)\)$', 'tokens', 'once');
        if ~isempty(src_tok)
            src_name = strtrim(src_tok{1});
            cap = get_numeric_field(src_name, network_elements, 'Capacity');
            state_val = get_numeric_field(src_name, network_elements, 'State');
            existing_src = get_source_line_load(src_name, topology_data, network_elements);
            if existing_src == 0 && ~isempty(links)
                % Μηδενικού-φορτίου transit γραμμή -> ίδιο ρεύμα με τον
                % αμέσως προηγούμενο (πραγματικό) κρίκο της αλυσίδας.
                existing_src = links(end).existing_load;
            end
            links(end+1) = struct('name', char(src_name), 'existing_load', existing_src, 'capacity', cap, 'state', state_val); %#ok<AGROW>
            continue;
        end

        cap = get_numeric_field(tok, network_elements, 'Capacity');
        if ~isnan(cap)
            tok_bus_id = '';
            if contains(tok, 'T24')
                tok_bus_id = 'T24';
            elseif contains(tok, 'T648')
                tok_bus_id = 'T648';
            end
            existing_load = get_existing_load_via_switch(char(tok), topology_data, network_elements, tok_bus_id, busbar_summary);
            state_val = get_numeric_field(tok, network_elements, 'State');
            links(end+1) = struct('name', char(tok), 'existing_load', existing_load, 'capacity', cap, 'state', state_val); %#ok<AGROW>
        end
        % αλλιώς: ενδιάμεση ετικέτα αναφοράς χωρίς δικό της Capacity -
        % δεν είναι φυσικός διακόπτης, την αγνοούμε.
    end
end

function [bridge_cb, bridge_line] = find_bridge_partner_cb(candidate_name, target_line, line_elements, topology_data, network_elements)
    % Αν ο candidate γειτονεύει (αριστερά/δεξιά) με ένα Type=segment στοιχείο
    % που ΕΠΙΣΗΣ εμφανίζεται σε ΑΛΛΗ Line_x στήλη (π.χ. BClx εμφανίζεται
    % και στη Line_2 και στη Line_3), τότε ψάχνουμε στην ΑΛΛΗ γραμμή τον
    % γείτονα εκείνου του segment που είναι Type=CB με δικό του Capacity —
    % αυτός είναι ο "δίδυμος" κόμβος-CB (π.χ. B135c).
    bridge_cb = ''; bridge_line = '';

    pos = find(line_elements == string(candidate_name), 1);
    if isempty(pos), return; end

    neighbor_positions = [pos - 1, pos + 1];
    neighbor_positions = neighbor_positions(neighbor_positions >= 1 & neighbor_positions <= numel(line_elements));

    bridge_name = '';
    for np = neighbor_positions
        cand_neighbor = char(line_elements(np));
        if is_type(cand_neighbor, network_elements, 'segment')
            bridge_name = cand_neighbor;
            break;
        end
    end
    if isempty(bridge_name), return; end

    var_names = topology_data.Properties.VariableNames;
    line_cols = var_names(startsWith(var_names, 'Line_'));

    for c = 1:numel(line_cols)
        if strcmpi(line_cols{c}, target_line)
            continue; % παραλείπουμε τη δική μας γραμμή, ψάχνουμε αλλού
        end
        col_data = string(rmmissing(topology_data.(line_cols{c})));
        col_data = col_data(col_data ~= "");
        pos2 = find(col_data == string(bridge_name), 1);
        if isempty(pos2), continue; end

        neighbor2_positions = [pos2 - 1, pos2 + 1];
        neighbor2_positions = neighbor2_positions(neighbor2_positions >= 1 & neighbor2_positions <= numel(col_data));
        for np2 = neighbor2_positions
            cand2 = char(col_data(np2));
            if ~is_type(cand2, network_elements, 'segment') && ~isnan(get_numeric_field(cand2, network_elements, 'Capacity'))
                bridge_cb = cand2;
                bridge_line = line_cols{c};
                return;
            end
        end
    end
end

function reject = is_own_dominant_bus_consumer(switch_name, bus_id, topology_data, network_elements, busbar_summary)
    % Επιστρέφει true αν η γραμμή του switch_name έχει busbar-άκρα ΚΑΙ
    % στις δύο πλευρές (π.χ. Line_7: ένα άκρο σε T648, ένα σε T24) ΚΑΙ ο
    % δικός της κυρίαρχος ζυγός είναι ΑΚΡΙΒΩΣ ο bus_id — που σημαίνει ότι
    % αυτή η γραμμή ΚΑΤΑΝΑΛΩΝΕΙ από τον bus_id (τροφοδοτείται ΑΠΟ αυτόν),
    % άρα ΔΕΝ μπορεί ταυτόχρονα να είναι πηγή/συνεισφορά ΠΡΟΣ τον ίδιο
    % ζυγό (θα δημιουργούσε mesh). Χρησιμοποιείται για να απορρίπτονται
    % τέτοια μη-έγκυρα μονοπάτια πριν καν χτιστεί η αλυσίδα τους.
    reject = false;
    var_names = topology_data.Properties.VariableNames;
    line_cols = var_names(startsWith(var_names, 'Line_'));

    for c = 1:numel(line_cols)
        col_data = string(rmmissing(topology_data.(line_cols{c})));
        col_data = col_data(col_data ~= "");
        if any(col_data == string(switch_name))
            if numel(col_data) < 2
                return;
            end
            first_e = char(col_data(1));
            last_e = char(col_data(end));
            first_is_bus = contains(first_e, 'T24') || contains(first_e, 'T648');
            last_is_bus = contains(last_e, 'T24') || contains(last_e, 'T648');
            if first_is_bus && last_is_bus
                dom = busbar_summary.dominant_bus;
                % Απορρίπτουμε ΚΑΙ όταν dom==bus_id (επιβεβαιωμένο mesh)
                % ΚΑΙ όταν dom=='NONE' (άγνωστη κυριαρχία - δεν μπορούμε
                % να επιβεβαιώσουμε ότι ΔΕΝ είναι mesh, οπότε συντηρητικά
                % την αγνοούμε αντί να την εμπιστευτούμε).
                if strcmp(dom, bus_id) || strcmp(dom, 'NONE')
                    reject = true;
                end
            end
            return;
        end
    end
end

function total_load = get_source_line_load(source_name, topology_data, network_elements)
    % Βρίσκει σε ποια Line_x γραμμή είναι τερματικό στοιχείο το
    % source_name (π.χ. "41/VIII" ή "53/VIII" — μια γνήσια πηγή, ΟΧΙ ένας
    % διακόπτης-πλευράς-ζυγού), και επιστρέφει το άθροισμα Load όλων των
    % segments εκείνης της γραμμής — αυτό είναι το φορτίο που η πηγή ΗΔΗ
    % τροφοδοτεί σήμερα κανονικά, ανεξάρτητα από οποιαδήποτε rescue-ενέργεια.
    total_load = 0;
    var_names = topology_data.Properties.VariableNames;
    line_cols = var_names(startsWith(var_names, 'Line_'));
    for c = 1:numel(line_cols)
        col_data = string(rmmissing(topology_data.(line_cols{c})));
        col_data = col_data(col_data ~= "");
        if any(col_data == string(source_name))
            total_load = sum_line_segment_load(col_data, network_elements);
            return;
        end
    end
end

function existing_load = get_existing_load_via_switch(switch_name, topology_data, network_elements, bus_id, busbar_summary)
    % "Κλειστό CB σε busbar δεν σημαίνει απαραίτητα ρεύμα μέσα από αυτό":
    % υπολογίζουμε existing_load = 0 αν το ΜΑΚΡΙΝΟ άκρο της γραμμής αυτού
    % του switch είναι ήδη ανεξάρτητη πηγή (δηλαδή το switch απλά δίνει
    % ηλεκτρική επαφή/τάση, όχι ρεύμα φορτίου), αλλιώς = άθροισμα Load
    % όλων των segments εκείνης της γραμμής (το switch κουβαλάει όλο το
    % φορτίο της).
    %
    % ΔΙΑΚΡΙΣΗ (νέο): το "μακρινό άκρο είναι πηγή" έχει ΔΥΟ διαφορετικές
    % σημασίες:
    %   (a) ΓΝΗΣΙΑ πηγή (π.χ. "50/VIII", έχει "/") -> το switch δεν
    %       κουβαλάει τίποτα δικό του (υπάρχουσα λογική, αμετάβλητη).
    %   (b) busbar-τύπου "πηγή" (π.χ. δίδυμη-busbar γραμμή σαν τη Line_7,
    %       όπου ΚΑΙ τα δύο άκρα είναι busbar-στοιχεία) -> ΔΕΝ είναι
    %       αυτόματα σίγουρο ποια πλευρά τροφοδοτεί ποια. Ελέγχουμε αν
    %       αυτή η πλευρά (bus_id) είναι η ΚΥΡΙΑΡΧΗ της γραμμής
    %       (busbar_summary.dominant_bus) - αν ναι, το switch ΚΟΥΒΑΛΑΕΙ
    %       πράγματι όλο το (πραγματικό) φορτίο της γραμμής· αν όχι, 0.
    %
    % ΔΙΕΛΕΥΣΗ (transit) ΠΡΟΣΘΗΚΗ: αν η ΔΙΚΗ ΤΟΥ γραμμή έχει ΜΗΔΕΝΙΚΟ
    % φορτίο (καθαρός σύνδεσμος, όχι καταναλωτής) ΚΑΙ αυτή η πλευρά
    % τροφοδοτεί πράγματι (γνήσια πηγή, ή κυρίαρχη busbar-πλευρά), τότε το
    % switch μπορεί να κουβαλάει ΚΑΙ το φορτίο άλλων γραμμών που
    % τροφοδοτούνται transitively μέσω του ίδιου ζυγού. Αυτό ελέγχεται
    % μόνο αν δοθούν τα προαιρετικά ορίσματα bus_id/busbar_summary
    % (αλλιώς παραλείπεται - συμβατότητα με παλιές κλήσεις).
    existing_load = 0;
    var_names = topology_data.Properties.VariableNames;
    line_cols = var_names(startsWith(var_names, 'Line_'));
    have_bus_data = (nargin >= 5) && ~isempty(bus_id) && ~isempty(busbar_summary);

    for c = 1:numel(line_cols)
        col_data = string(rmmissing(topology_data.(line_cols{c})));
        col_data = col_data(col_data ~= "");
        if any(col_data == string(switch_name))
            pos = find(col_data == string(switch_name), 1);
            if pos == 1
                far_end = char(col_data(end));
            else
                far_end = char(col_data(1));
            end

            own_line_load = sum_line_segment_load(col_data, network_elements);
            far_has_slash = contains(far_end, '/');
            far_is_src = check_if_source(far_end, network_elements);

            if far_is_src && far_has_slash
                % (a) Γνήσια πηγή - υπάρχουσα λογική, αμετάβλητη
                existing_load = 0;
                if own_line_load == 0 && have_bus_data
                    existing_load = existing_load + get_transitive_busbar_load( ...
                        switch_name, line_cols{c}, bus_id, topology_data, network_elements, busbar_summary);
                end
            elseif far_is_src && ~far_has_slash
                % (b) busbar-τύπου "πηγή" (δίδυμη-busbar γραμμή) -
                % εξαρτάται ποια πλευρά είναι η κυρίαρχη
                if have_bus_data && isfield(busbar_summary, 'dominant_bus') && strcmp(busbar_summary.dominant_bus, bus_id)
                    existing_load = own_line_load; % αυτή η πλευρά ΕΙΝΑΙ η κυρίαρχη -> κουβαλάει όλο το φορτίο
                    if own_line_load == 0
                        existing_load = existing_load + get_transitive_busbar_load( ...
                            switch_name, line_cols{c}, bus_id, topology_data, network_elements, busbar_summary);
                    end
                else
                    existing_load = 0; % άγνωστη/όχι-κυρίαρχη πλευρά -> συντηρητικά 0
                end
            else
                % Το μακρινό άκρο ΔΕΝ είναι καν πηγή -> η γραμμή τροφοδοτείται ΑΠΟ εδώ
                existing_load = own_line_load;
            end
            return;
        end
    end
end

function total = get_transitive_busbar_load(transit_switch_name, transit_line_col, bus_id, topology_data, network_elements, busbar_summary)
    % ΑΠΛΟΠΟΙΗΣΗ: υποθέτουμε ΤΟ ΠΟΛΥ ΜΙΑ γραμμή μηδενικού φορτίου (transit)
    % ανά ζυγό. Αν στο μέλλον υπάρξουν πολλαπλές τέτοιες γραμμές πάνω στον
    % ίδιο ζυγό ταυτόχρονα, χρειάζεται tie-breaking λογική (π.χ. επιλογή
    % αυτής με το μεγαλύτερο Capacity διακόπτη) που ΔΕΝ έχει υλοποιηθεί εδώ
    % - ο χρήστης επιβεβαίωσε ότι στο τρέχον δίκτυο δεν συμβαίνει.
    %
    % Βρίσκει, για τον δεδομένο ζυγό (bus_id), ποιες ΑΛΛΕΣ γραμμές (εκτός
    % της ίδιας της transit_line_col) είναι πραγματικοί "καταναλωτές" του
    % — δηλαδή τροφοδοτούνται ΑΠΟ τον ζυγό, όχι το αντίστροφο — και
    % αθροίζει το Load τους.
    total = 0;

    if strcmp(bus_id, 'T24')
        bus_col = 'Busbar_1';
    elseif strcmp(bus_id, 'T648')
        bus_col = 'Busbar_2';
    else
        return;
    end

    var_names = topology_data.Properties.VariableNames;
    if ~ismember(bus_col, var_names)
        return;
    end
    bus_entries = string(rmmissing(topology_data.(bus_col)));
    bus_entries = bus_entries(bus_entries ~= "");

    line_cols = var_names(startsWith(var_names, 'Line_'));
    dominant_bus = ''; % lazy - υπολογίζεται μόνο αν χρειαστεί

    for i = 1:numel(bus_entries)
        entry = char(bus_entries(i));
        if strcmp(entry, transit_switch_name)
            continue; % παραλείπουμε τον ίδιο τον transit διακόπτη
        end

        st = get_numeric_field(entry, network_elements, 'State');
        if isnan(st) || st ~= 1
            continue; % μόνο ΚΛΕΙΣΤΑ entries μπορούν να καταναλώνουν από τον ζυγό
        end

        % Βρες τη γραμμή αυτού του entry (εκτός της transit_line_col)
        entry_line_col = '';
        entry_col_data = string([]);
        for c = 1:numel(line_cols)
            if strcmp(line_cols{c}, transit_line_col)
                continue;
            end
            cd = string(rmmissing(topology_data.(line_cols{c})));
            cd = cd(cd ~= "");
            if any(cd == string(entry))
                entry_line_col = line_cols{c};
                entry_col_data = cd;
                break;
            end
        end
        if isempty(entry_line_col)
            continue;
        end

        pos = find(entry_col_data == string(entry), 1);
        if isempty(pos)
            continue;
        end
        if pos == 1
            other_end = char(entry_col_data(end));
        else
            other_end = char(entry_col_data(1));
        end

        other_state = get_numeric_field(other_end, network_elements, 'State');
        is_consumer = false;

        if ~isnan(other_state) && other_state == 0
            is_consumer = true; % το άλλο άκρο ανοιχτό -> ο ζυγός μας τον τροφοδοτεί
        elseif ~isnan(other_state) && other_state == 1
            if contains(other_end, '/')
                is_consumer = false; % ίδια γνήσια πηγή στο άλλο άκρο -> τροφοδοτείται από εκεί
            elseif contains(other_end, 'T24') || contains(other_end, 'T648')
                if isempty(dominant_bus)
                    dominant_bus = busbar_summary.dominant_bus;
                end
                if strcmp(dominant_bus, bus_id)
                    is_consumer = true;
                end
            end
        end

        if is_consumer
            total = total + sum_line_segment_load(entry_col_data, network_elements);
        end
    end
end

% ΣΗΜΕΙΩΣΗ: ο κυρίαρχος ζυγός ΔΕΝ υπολογίζεται πλέον εδώ - υπολογίζεται
% ΜΕΣΑ στο Check_Busbars.m και επιστρέφεται σαν πεδίο
% busbar_summary.dominant_bus, ώστε να υπάρχει ΜΙΑ μόνο πηγή αλήθειας.
% Οι κλήσεις παρακάτω στο αρχείο (π.χ. μέσα στο is_own_dominant_bus_consumer,
% get_transitive_busbar_load) απλά διαβάζουν busbar_summary.dominant_bus.

function total = sum_line_segment_load(line_elems, network_elements)
    total = 0;
    for i = 1:numel(line_elems)
        elem = char(line_elems(i));
        if is_type(elem, network_elements, 'segment')
            v = get_numeric_field(elem, network_elements, 'Load');
            if ~isnan(v), total = total + v; end
        end
    end
end

function tf = is_type(elem_name, network_elements, type_substr)
    tf = false;
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember('Type', row.Properties.VariableNames), return; end
    type_val = row.Type;
    if iscell(type_val), type_val = type_val{1}; end
    tf = contains(lower(string(type_val)), type_substr);
end

function val = get_numeric_field(elem_name, network_elements, field_name)
    val = NaN;
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember(field_name, row.Properties.VariableNames), return; end
    raw = row.(field_name);
    if iscell(raw), raw = raw{1}; end
    if isempty(raw), return; end
    v = double(raw);
    if ~isempty(v) && ~isnan(v), val = v; end
end

function link_val = get_link_value(elem_name, network_elements)
    % Ίδια λογική με το get_link_value του compare_Loads_1.m -
    % εγγυημένα scalar string, ασφαλές σε διπλότυπες εγγραφές/NaN/κενά.
    link_val = "";
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if isempty(row) || ~ismember('Link', row.Properties.VariableNames)
        return;
    end
    if height(row) > 1, row = row(1, :); end
    raw_link = row.Link;
    if isnumeric(raw_link)
        if ~isempty(raw_link) && ~isnan(raw_link(1))
            link_val = string(raw_link(1));
        end
    else
        if iscell(raw_link), raw_link = raw_link{1}; end
        s = strtrim(string(raw_link));
        if ~ismissing(s) && s ~= "" && ~strcmpi(s, "NaN")
            link_val = s;
        end
    end
end

function out = tern(cond, a, b)
    if cond, out = a; else, out = b; end
end
