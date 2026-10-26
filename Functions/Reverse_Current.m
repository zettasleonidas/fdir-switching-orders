function [closed_switch, saved_segments] = Reverse_Current(target_line, line_elements, open_switches_list, fault_element_indices, network_elements)
    % =========================================================================
    % ΣΥΝΑΡΤΗΣΗ: Reverse_Current
    % -------------------------------------------------------------------------
    % Εκτελεί τη ρουτίνα της ανάστροφης τροφοδοσίας: εντοπίζει τον
    % εναλλακτικό (ανοιχτό) διακόπτη στο άκρο της γραμμής, ελέγχει αν το
    % κλείσιμό του έχει πραγματικά νόημα (δεν αγγίζει άμεσα το σφάλμα), και
    % αν ναι, αναφέρει ποια segments πράγματι σώζονται.
    %
    % Έξτρα, αν το σφάλμα βρίσκεται ΑΚΡΙΒΩΣ δίπλα στον εναλλακτικό
    % διακόπτη, δεν υπάρχει καμία γραμμή προς διάσωση από αυτή την πλευρά
    % ο διακόπτης ΔΕΝ κλείνει, με σαφές μήνυμα, αποφεύγοντας περιττό
    % ανοιγόκλειμα.
    % Έξτρα, όταν πράγματι κλείνει, αναφέρει ρητά ποια segments σώζονται
    % (ονόματα + συνολικό φορτίο) και υπενθυμίζει ότι η γραμμή παραμένει
    % διακομμένη στο σημείο του σφάλματος.
    % Έξτρα, επιστρέφει το όνομα του διακόπτη που ΠΡΑΓΜΑΤΙΚΑ έκλεισε (ή
    % "" αν ακυρώθηκε/δεν βρέθηκε), ώστε να μπορεί το Operation_Note να το
    % συμπεριλάβει.
    %
    % ΕΙΣΟΔΟΙ:
    %   target_line             : π.χ. 'Line_1'
    %   line_elements            : τοπολογία της γραμμής (cell ή string array
    %                              - κανονικοποιείται αυτόματα εδώ)
    %   open_switches_list       : λίστα ανοιχτών διακοπτών (ο πρώτος
    %                              χρησιμοποιείται ως ο εναλλακτικός)
    %   fault_element_indices    : ΠΡΟΑΙΡΕΤΙΚΟ - θέσεις σφάλματος (output
    %                              της find_faulty_isolation_zones). Χωρίς
    %                              αυτό, ο έλεγχος γειτνίασης παραλείπεται
    %                              (συμβατότητα με παλιές κλήσεις).
    %   network_elements         : ΠΡΟΑΙΡΕΤΙΚΟ - table (Sheet2), για τον
    %                              υπολογισμό των φορτίων που σώζονται.
    %
    % ΕΞΟΔΟΣ:
    %   closed_switch  : το όνομα του διακόπτη που έκλεισε, ή "" αν καμία
    %                    ενέργεια δεν έγινε τελικά.
    %   saved_segments : cellstr με τα ονόματα των segments που πράγματι
    %                    σώθηκαν (κενό αν καμία ενέργεια/χωρίς load data).
    % =========================================================================

    closed_switch = "";
    saved_segments = {};
    fprintf('\n--- [Εκτέλεση Ρουτίνας] Reverse Current ---\n');

    if isempty(open_switches_list)
        fprintf('[ΠΡΟΣΟΧΗ] Προσοχή: Εντοπίστηκε Stem χωρίς Interconnection, αλλά δεν βρέθηκε ανοιχτός διακόπτης στη λίστα!\n');
        return;
    end

    % Κανονικοποίηση σε string array, ώστε να δουλεύει ίδια είτε ο
    % καλών περάσει cell array είτε string array.
    line_elements = string(line_elements);

    rev_switch = open_switches_list{1};
    switch_pos = find(strcmp(line_elements, rev_switch));

    if isempty(switch_pos)
        fprintf('[ΠΡΟΣΟΧΗ] Ο διακόπτης "%s" εντοπίστηκε αλλά δεν βρέθηκε μέσα στα στοιχεία της γραμμής "%s".\n', rev_switch, target_line);
        return;
    end
    switch_pos = switch_pos(1);
    fprintf('[OK] Ο διακόπτης "%s" βρίσκεται στη θέση %d της γραμμής "%s".\n', rev_switch, switch_pos, target_line);

    % --- Κατεύθυνση σάρωσης προς το εσωτερικό της γραμμής ---
    if switch_pos == numel(line_elements)
        scan_dir = -1;
    else
        scan_dir = 1; % switch_pos == 1 (τυπική περίπτωση) ή fallback
    end

    have_fault_data = (nargin >= 4) && ~isempty(fault_element_indices);
    have_load_data  = (nargin >= 5) && ~isempty(network_elements);

    % --- Έλεγχος: αγγίζει το σφάλμα ΑΚΡΙΒΩΣ τον εναλλακτικό διακόπτη; ---
    if have_fault_data
        first_neighbor = switch_pos + scan_dir;
        if first_neighbor >= 1 && first_neighbor <= numel(line_elements) && ismember(first_neighbor, fault_element_indices)
            fprintf('[FAIL] [Ακύρωση]: Το σφάλμα βρίσκεται ακριβώς δίπλα στον εναλλακτικό διακόπτη "%s" — καμία γραμμή δεν θα ωφελούνταν από το κλείσιμό του.\n', rev_switch);
            fprintf('   Ο διακόπτης "%s" ΔΕΝ κλείνει, ώστε να αποφευχθεί περιττό ανοιγόκλειμα.\n', rev_switch);
            return;
        end
    end

    % --- Εύρεση "ζώνης διάσωσης": segments από τον διακόπτη μέχρι το πρώτο σφάλμα (ή το τέλος) ---
    saved_segments = {};
    saved_load = 0;
    pos = switch_pos + scan_dir;
    while pos >= 1 && pos <= numel(line_elements)
        if have_fault_data && ismember(pos, fault_element_indices)
            break;
        end
        elem = char(line_elements(pos));
        if have_load_data && is_segment_element(elem, network_elements)
            saved_segments{end+1} = elem; %#ok<AGROW>
            saved_load = saved_load + get_element_load(elem, network_elements);
        end
        pos = pos + scan_dir;
    end

    % --- OPERATION NOTE ---
    fprintf('[INFO] OPERATION NOTE: Δίνεται εντολή κλεισίματος στον διακόπτη %s.\n', rev_switch);
    fprintf('[INFO] [Κατάσταση Δικτύου]: Η γραμμή "%s" τροφοδοτείται προσωρινά και από τις δύο κατευθύνσεις (κανονική & ανάστροφη τροφοδοσία), αποτρέποντας τη διακοπή φορτίων.\n', target_line);

    if have_load_data
        if ~isempty(saved_segments)
            fprintf('[OK] [Φορτία που σώζονται]: %s (συνολικό φορτίο: %g A)\n', strjoin(saved_segments, ', '), saved_load);
        else
            fprintf('[INFO] Δεν εντοπίστηκαν segments στη ζώνη διάσωσης του διακόπτη.\n');
        end
    end
    if have_fault_data
        fprintf('[ΠΡΟΣΟΧΗ] [Παραμένει χωρίς ρεύμα]: Η γραμμή "%s" παραμένει διακομμένη στο σημείο του σφάλματος — τμήματα πέρα από αυτό ΔΕΝ επηρεάζονται από αυτή την ενέργεια.\n', target_line);
    end

    closed_switch = string(rev_switch);
end

function tf = is_segment_element(elem_name, network_elements)
    tf = false;
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember('Type', row.Properties.VariableNames), return; end
    type_val = row.Type;
    if iscell(type_val), type_val = type_val{1}; end
    tf = contains(lower(string(type_val)), 'segment');
end

function v = get_element_load(elem_name, network_elements)
    v = 0;
    row = network_elements(strcmp(network_elements.Element, elem_name), :);
    if height(row) > 1, row = row(1, :); end
    if isempty(row) || ~ismember('Load', row.Properties.VariableNames), return; end
    raw = row.Load;
    if iscell(raw), raw = raw{1}; end
    val = double(raw);
    if ~isempty(val) && ~isnan(val), v = val; end
end
