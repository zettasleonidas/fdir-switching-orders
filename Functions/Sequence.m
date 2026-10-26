function actions = Sequence(target_line, line_elements, raw_input_faults, network_elements)
% =========================================================================
% FUNCTION: Sequence
% -------------------------------------------------------------------------
% Το "Sequence" ρουτίνα του flowchart: για ΚΑΘΕ σφάλμα (μεμονωμένο ή
% σύνθετο) στο raw_input_faults, βρίσκει τον πρώτο διακόπτη (CB ή T)
% αριστερά και δεξιά του, και τους ανοίγει (=απομονώνει) με τη σωστή
% σειρά.
%
% ΕΙΔΙΚΟΣ ΧΕΙΡΙΣΜΟΣ Type=T (τριπολικός αποζεύκτης):
%   Το T δεν αντέχει να ανοίξει υπό φορτίο. Επειδή η πλευρά ΠΡΟΣ το
%   σφάλμα είναι εξ ορισμού νεκρή (είναι το ίδιο το σφάλμα), ελέγχουμε
%   μόνο τη ΜΑΚΡΙΝΗ πλευρά (πέρα από το T, μακριά από το σφάλμα):
%     - Αν ΔΕΝ τροφοδοτεί (ήδη νεκρή/απομονωμένη) -> το T ανοίγει
%       κατευθείαν, ήδη ασφαλές (μηδενικό ρεύμα).
%     - Αν τροφοδοτεί -> ανοίγουμε ΠΡΩΤΑ το CB αμέσως ΠΕΡΑ από το T
%       (κόβοντας τη μακρινή τροφοδοσία), και ΜΕΤΑ ανοίγει το T,
%       πλέον με μηδενικό ρεύμα.
%
% ΑΠΛΟΠΟΙΗΣΗ νο1: δεν υλοποιείται το "already dual-fed -> άνοιξε το T
% πρώτο, με ασφάλεια loop-current" shortcut (θα χρειαζόταν να ελέγχουμε
% ΚΑΙ την πλευρά προς το σφάλμα για ενδεχόμενη εναλλακτική τροφοδοσία από
% αλλού, μέσω ήδη κλεισμένων tie-switches - πολύπλοκο, σπάνιο σενάριο για
% το πλαίσιο ενός μεμονωμένου σφάλματος). Η μέθοδος που υλοποιείται εδώ
% (πάντα κόψε πρώτα τη μακρινή τροφοδοσία, μετά άνοιξε το T) είναι ΠΑΝΤΑ
% ασφαλής, απλά όχι πάντα η ταχύτερη δυνατή.
% ΑΠΛΟΠΟΙΗΣΗ νο2: δεν προβλέπονται δύο διαδοχικά T (επιβεβαιωμένο
% από τον χρήστη ότι δεν συμβαίνει στο πραγματικό δίκτυο).
%
% ΕΙΣΟΔΟΙ:
%   target_line       : π.χ. 'Line_7'
%   line_elements      : τοπολογία της γραμμής (cell ή string array -
%                        κανονικοποιείται αυτόματα εδώ)
%   raw_input_faults   : cell array σφαλμάτων, π.χ. {'Gl3-Gl5','Gl9'}
%   network_elements   : table (Sheet2)
%
% ΕΞΟΔΟΣ:
%   actions : struct array, ένα per ΕΝΟΠΟΙΗΜΕΝΟ σφάλμα, με πεδία:
%       .fault            το (ενοποιημένο) σφάλμα (π.χ. "Cl3-Cl5")
%       .switches_opened  cellstr με τα ονόματα των διακοπτών που ανοίγουν
%       .positions        οι αντίστοιχες θέσεις τους μέσα στη γραμμή
% =========================================================================

    fprintf('\n--- SEQUENCE: Απομόνωση σφαλμάτων ---\n');

    line_elements = string(line_elements);
    actions = struct('fault', {}, 'switches_opened', {}, 'positions', {});

    % --- Βήμα 0: Συγκέντρωση & ΣΥΓΧΩΝΕΥΣΗ όλων των θέσεων σφάλματος ---
    % Αν δύο δηλωμένα σφάλματα επικαλύπτονται ή το ένα περιέχει το άλλο
    % (π.χ. "Cl3-Cl5" και "Cl5"), δεν πρέπει να απομονωθούν ΔΥΟ φορές το
    % ίδιο φυσικό σημείο - τα ενοποιούμε πρώτα σε καθαρά, μη-επικαλυπτόμενα
    % μπλοκ (ίδια λογική "smart merge" με τα exercise4/5.m).
    all_indices = [];
    for f = 1:numel(raw_input_faults)
        element_block = string(raw_input_faults{f});
        [idxStart, idxEnd] = parse_fault_indices(element_block, line_elements);
        if isempty(idxStart)
            fprintf('[ΠΡΟΣΟΧΗ] [Sequence]: Το σφάλμα "%s" δεν βρέθηκε στη γραμμή %s - παραλείπεται.\n', element_block, target_line);
            continue;
        end
        all_indices = [all_indices, idxStart:idxEnd]; %#ok<AGROW>
    end

    if isempty(all_indices)
        fprintf('[ΠΡΟΣΟΧΗ] [Sequence]: Κανένα έγκυρο σφάλμα προς απομόνωση.\n');
        fprintf('\n--- Τέλος Sequence ---\n');
        return;
    end

    % --- Συγχώνευση σε "φυσικά συνεχόμενα" μπλοκ ---
    % Δύο δηλωμένα σφάλματα συγχωνεύονται σε ΕΝΑ μπλοκ όχι μόνο αν οι
    % raw θέσεις τους είναι κυριολεκτικά διαδοχικές (π.χ. επικαλυπτόμενα
    % "Cl3-Cl5"+"Cl5"), αλλά ΚΑΙ αν ανάμεσά τους υπάρχουν ΜΟΝΟ διακοπτικά
    % στοιχεία (καμία ζωντανή Segment) - π.χ. "Al2","Al3","Al4" δηλωμένα
    % ξεχωριστά, με μόνο CB ανάμεσά τους, είναι στην πράξη ΕΝΑ συνεχόμενο
    % νεκρό κομμάτι· δεν έχει νόημα να ανοιχθούν επιπλέον διακόπτες
    % ανάμεσά τους. Ίδια λογική με τη συγχώνευση ορφανών segments στο
    % find_faulty_isolation_zones, εφαρμοσμένη εδώ στα ίδια τα σφάλματα.
    clean_indices = unique(all_indices);
    block_ranges = merge_fault_clusters(clean_indices, line_elements, network_elements);

    for i = 1:size(block_ranges, 1)
        block_start = block_ranges(i, 1);
        block_end = block_ranges(i, 2);
        fault_label = build_fault_label(line_elements, block_start, block_end);

        fprintf('\n> Σφάλμα "%s" (θέσεις %d-%d):\n', fault_label, block_start, block_end);

        [names_l, pos_l] = isolate_side(block_start - 1, -1, line_elements, network_elements);
        [names_r, pos_r] = isolate_side(block_end + 1, 1, line_elements, network_elements);

        opened_names = [names_l, names_r];
        opened_positions = [pos_l, pos_r];

        if isempty(opened_names)
            fprintf('   [ΠΡΟΣΟΧΗ] Δεν βρέθηκε κανένας διακόπτης (CB/T) για την απομόνωση αυτού του σφάλματος.\n');
        else
            desc = strings(1, numel(opened_names));
            for k = 1:numel(opened_names)
                desc(k) = sprintf('%s (θέση %d)', opened_names{k}, opened_positions(k));
            end
            fprintf('   [OK] Απομονώθηκε το σφάλμα "%s" ανοίγοντας: %s\n', fault_label, strjoin(desc, ', '));
        end

        actions(end+1) = struct('fault', char(fault_label), ...
            'switches_opened', {opened_names}, 'positions', opened_positions); %#ok<AGROW>
    end

    fprintf('\n--- Τέλος Sequence ---\n');
end


% =========================================================================
% ΒΟΗΘΗΤΙΚΕΣ ΣΥΝΑΡΤΗΣΕΙΣ
% =========================================================================

function label = build_fault_label(line_elements, s_idx, e_idx)
    if s_idx == e_idx
        label = line_elements(s_idx);
    else
        label = line_elements(s_idx) + "-" + line_elements(e_idx);
    end
end

function block_ranges = merge_fault_clusters(clean_indices, line_elements, network_elements)
    % Συγχωνεύει τις (ήδη ταξινομημένες, μοναδικές) θέσεις σφάλματος σε
    % μπλοκ [start, end]. Δύο διαδοχικές θέσεις ενώνονται στο ΙΔΙΟ μπλοκ
    % αν είτε είναι κυριολεκτικά διαδοχικές (diff==1), είτε όλα τα
    % ενδιάμεσα στοιχεία ανάμεσά τους είναι ΔΙΑΚΟΠΤΙΚΑ (όχι Segment) -
    % δηλαδή δεν υπάρχει καμία ζωντανή γραμμή ανάμεσα στα δύο σφάλματα,
    % άρα είναι στην πράξη ένα ενιαίο συνεχόμενο νεκρό κομμάτι.
    n = numel(clean_indices);
    block_ranges = zeros(0, 2);
    if n == 0
        return;
    end

    cur_start = clean_indices(1);
    cur_end = clean_indices(1);

    for k = 2:n
        p = clean_indices(k);
        between = (cur_end + 1):(p - 1);
        only_switches = true;
        for b = between
            et = get_element_type(char(line_elements(b)), network_elements);
            if strcmpi(et, 'Segment') || isempty(et)
                only_switches = false;
                break;
            end
        end
        if only_switches
            cur_end = p; % συγχώνευση στο ίδιο μπλοκ
        else
            block_ranges(end+1, :) = [cur_start, cur_end]; %#ok<AGROW>
            cur_start = p;
            cur_end = p;
        end
    end
    block_ranges(end+1, :) = [cur_start, cur_end]; %#ok<AGROW>
end

function [idxStart, idxEnd] = parse_fault_indices(element_block, line_elements)
    idxStart = []; idxEnd = [];
    if contains(element_block, "-")
        limits = split(element_block, "-");
        s = strtrim(limits(1));
        e = strtrim(limits(2));
        i1 = find(line_elements == s, 1);
        i2 = find(line_elements == e, 1);
        if isempty(i1) || isempty(i2)
            return;
        end
        idxStart = min(i1, i2);
        idxEnd = max(i1, i2);
    else
        i1 = find(line_elements == strtrim(element_block), 1);
        if isempty(i1)
            return;
        end
        idxStart = i1;
        idxEnd = i1;
    end
end

function [names, positions] = isolate_side(start_pos, step, line_elements, network_elements)
    % Σαρώνει από start_pos προς την κατεύθυνση step (±1) μέχρι να βρει
    % το πρώτο στοιχείο με Type=CB ή Type=T, και επιστρέφει τη λίστα των
    % διακοπτών που ΠΡΑΓΜΑΤΙΚΑ χρειάζεται να ανοίξουν (με τη σωστή σειρά)
    % για να απομονωθεί αυτή η πλευρά.
    %
    % ΣΗΜΑΝΤΙΚΟ: αν το πλησιέστερο στοιχείο είναι ΗΔΗ ανοιχτό (State=0),
    % ΔΕΝ προστίθεται καμία εντολή γι' αυτό (δεν χρειάζεται) - αλλά η
    % σάρωση ΣΤΑΜΑΤΑΕΙ ούτως ή άλλως προς αυτή την κατεύθυνση, αφού το
    % ήδη-ανοιχτό στοιχείο ήδη παρέχει την απομόνωση από εκεί.
    names = {};
    positions = [];
    N = numel(line_elements);
    pos = start_pos;

    while pos >= 1 && pos <= N
        elem = char(line_elements(pos));
        etype = get_element_type(elem, network_elements);

        if strcmpi(etype, 'CB')
            st = get_element_state(elem, network_elements);
            if ~isnan(st) && st == 0
                fprintf('   [ΗΔΗ ΑΝΟΙΧΤΟ] %s (θέση %d) - καμία ενέργεια.\n', elem, pos);
                return; % ήδη ανοιχτό - καμία εντολή, αλλά η απομόνωση ήδη ισχύει
            end

            % --- Έλεγχος: υπάρχει τριπολικός αποζεύκτης ΑΜΕΣΩΣ μετά αυτό
            % το CB (προς την ίδια κατεύθυνση σάρωσης); Αν ναι, δεν
            % αρκεί το άνοιγμα μόνο αυτού του CB - ακολουθεί η πλήρης
            % διαδικασία των 3 βημάτων (αυτό το CB πρώτο, μετά ο
            % διακόπτης πέρα από το T, και τελευταίο το ίδιο το T). ---
            next_pos = pos + step;
            if next_pos >= 1 && next_pos <= N
                next_elem = char(line_elements(next_pos));
                next_type = get_element_type(next_elem, network_elements);
                if strcmpi(next_type, 'T')
                    fprintf('   [ΤΡΙΠΟΛΙΚΟΣ ΑΠΟΖΕΥΚΤΗΣ] Εντοπίστηκε %s αμέσως μετά τον διακόπτη %s (θέση %d) - ακολουθείται η διαδικασία ασφαλούς απομόνωσης.\n', ...
                        next_elem, elem, next_pos);

                    names{end+1} = elem; %#ok<AGROW> % 1ο βήμα: το CB που ήδη βρέθηκε
                    positions(end+1) = pos; %#ok<AGROW>

                    t_state = get_element_state(next_elem, network_elements);
                    if ~isnan(t_state) && t_state == 0
                        fprintf('   [ΗΔΗ ΑΝΟΙΧΤΟ] %s (θέση %d) - καμία ενέργεια.\n', next_elem, next_pos);
                    else
                        far_pos = next_pos + step;
                        [far_name, far_position] = find_nearest_switch(far_pos, step, line_elements, network_elements);
                        if ~isempty(far_name)
                            names{end+1} = far_name; %#ok<AGROW> % 2ο βήμα: πέρα από το T
                            positions(end+1) = far_position; %#ok<AGROW>
                        end
                        names{end+1} = next_elem; %#ok<AGROW> % 3ο, τελευταίο βήμα: το ίδιο το T
                        positions(end+1) = next_pos; %#ok<AGROW>
                    end
                    return;
                end
            end

            names{end+1} = elem; %#ok<AGROW>
            positions(end+1) = pos; %#ok<AGROW>
            return;

        elseif strcmpi(etype, 'T')
            t_state = get_element_state(elem, network_elements);
            if ~isnan(t_state) && t_state == 0
                fprintf('   [ΗΔΗ ΑΝΟΙΧΤΟ] %s (θέση %d) - καμία ενέργεια.\n', elem, pos);
                return; % ο ίδιος ο αποζεύκτης είναι ήδη ανοιχτός - τίποτα να γίνει
            end
            % --- Ειδικός χειρισμός τριπολικού αποζεύκτη ---
            % Ανοίγεται ΠΑΝΤΑ πρώτα ο διακόπτης αμέσως πέρα από το T (προς
            % την κατεύθυνση της πηγής), ανεξάρτητα από το αν πράγματι
            % τροφοδοτεί ή όχι εκείνη τη στιγμή - ίδια, συνεπής λογική με
            % το Branch_Switch, απλούστερη και πιο συντηρητική.
            fprintf('   [ΤΡΙΠΟΛΙΚΟΣ ΑΠΟΖΕΥΚΤΗΣ] Εντοπίστηκε %s (θέση %d) - ακολουθείται η διαδικασία ασφαλούς απομόνωσης.\n', elem, pos);
            far_pos = pos + step;
            [far_name, far_position] = find_nearest_switch(far_pos, step, line_elements, network_elements);
            if ~isempty(far_name)
                names{end+1} = far_name; %#ok<AGROW>
                positions(end+1) = far_position; %#ok<AGROW>
            end
            % Το T ανοίγει ΤΕΛΕΥΤΑΙΟ, αφού πλέον δεν τροφοδοτείται
            names{end+1} = elem; %#ok<AGROW>
            positions(end+1) = pos; %#ok<AGROW>
            return;
        end

        pos = pos + step;
    end
end

function [sw_name, sw_pos] = find_nearest_switch(start_pos, step, line_elements, network_elements)
    % Σαρώνει από start_pos προς την κατεύθυνση step, βρίσκει το πρώτο
    % Type=CB (αγνοεί την κατάσταση - το Τ πάντα ανοίγει τους δύο
    % γειτονικούς διακόπτες, ανεξάρτητα αν χρειαζόταν ή όχι, βλ. σχόλιο
    % στο isolate_side). Επιστρέφει ('', []) αν δεν βρεθεί.
    sw_name = '';
    sw_pos = [];
    N = numel(line_elements);
    p = start_pos;
    while p >= 1 && p <= N
        elem = char(line_elements(p));
        et = get_element_type(elem, network_elements);
        if strcmpi(et, 'CB')
            sw_name = elem;
            sw_pos = p;
            return;
        end
        p = p + step;
    end
end

function etype = get_element_type(elem_name, network_elements)
    etype = '';
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember('Type', row.Properties.VariableNames)
        return;
    end
    tv = row.Type;
    if iscell(tv), tv = tv{1}; end
    etype = strtrim(char(string(tv)));
end

function st = get_element_state(elem_name, network_elements)
    st = NaN;
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember('State', row.Properties.VariableNames)
        return;
    end
    raw = row.State;
    if iscell(raw), raw = raw{1}; end
    v = double(raw);
    if ~isempty(v) && ~isnan(v)
        st = v;
    end
end
