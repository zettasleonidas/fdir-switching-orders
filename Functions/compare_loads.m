function actions = compare_loads(target_line, orphan_groups, line_elements, ...
        network_elements, topology_data, fault_element_indices, busbar_summary, verbose)
% =========================================================================
% FUNCTION: compare_loads
% -------------------------------------------------------------------------
% Το "Compare Loads" ρουτίνα του flowchart, σαν μία callable συνάρτηση.
%  Ενώνει
%   1) find_rescue_candidates  -> candidates ανά ορφανό group
%   2) Επιλογή του καλύτερου έγκυρου candidate ανά group (max min_margin)
%   3) State-aware μήνυμα: ποιοι διακόπτες της νικήτριας αλυσίδας
%      χρειάζονται ΠΡΑΓΜΑΤΙΚΑ εντολή κλεισίματος (state==0) και ποιοι
%      είναι ήδη κλειστοί (καμία ενέργεια)
%   4) Για groups χωρίς κανέναν έγκυρο candidate: ρητό μήνυμα ότι δεν
%      υπάρχει εναλλακτική πηγή τροφοδότησης
%
% ΣΗΜΕΙΩΣΗ: το busbar_summary περνιέται ΕΤΟΙΜΟ από τον καλούντα (π.χ. τη
% main, που το έχει ήδη υπολογίσει μία φορά στην αρχή) — το compare_loads
% ΔΕΝ ξανακαλεί το Check_Busbars, γιατί έχει μεγάλο output και δεν
% χρειάζεται να τρέξει δεύτερη φορά για το ίδιο τρέξιμο.
%
% ΕΙΣΟΔΟΙ:
%   target_line             : π.χ. 'Line_2'
%   orphan_groups            : string array (output της find_faulty_isolation_zones)
%   line_elements            : string array, τοπολογία target_line
%   network_elements         : table (Sheet2)
%   topology_data            : table (Sheet1)
%   fault_element_indices    : output της find_faulty_isolation_zones
%   busbar_summary           : ήδη υπολογισμένο (Check_Busbars) από τον καλούντα
%
% ΕΞΟΔΟΣ:
%   actions : struct array, ένα per orphan group, με πεδία:
%       .group          το όνομα του group (π.χ. "Bl6-Bl7")
%       .rescued        true/false - βρέθηκε έγκυρος candidate;
%       .winner_cb      το όνομα του candidate που κέρδισε (αν rescued)
%       .side           'L'/'R'/'M' του winner (αν rescued)
%       .chain          η πλήρης αλυσίδα του winner (struct array, με state/needs_close)
%       .cbs_to_close   cellstr με τα ονόματα των διακοπτών που ΠΡΑΓΜΑΤΙΚΑ
%                       χρειάζονται εντολή κλεισίματος (state==0 στην αλυσίδα)
%       .close_details  struct array (name, existing_load, new_load) - ίδιοι
%                       διακόπτες με το cbs_to_close, με τα πριν/μετά φορτία
%                       τους, για το Operation_Note
%       .source         το όνομα της ΤΕΛΙΚΗΣ πηγής της αλυσίδας (τελευταίος
%                       κρίκος), π.χ. "53/VIII" - κενό αν δεν σώθηκε
% =========================================================================

    if nargin < 8
        verbose = true; 
    end

    fprintf('\n--- COMPARE LOADS: Αναζήτηση & αξιολόγηση εναλλακτικών πηγών ---\n');

    actions = struct('group', {}, 'rescued', {}, 'winner_cb', {}, 'side', {}, ...
        'chain', {}, 'cbs_to_close', {}, 'close_details', {}, 'source', {});

    for g = 1:numel(orphan_groups)
        cands = find_rescue_candidates(orphan_groups(g), target_line, ...
            line_elements, network_elements, topology_data, ...
            fault_element_indices, busbar_summary, verbose);

        valid_cands = cands([cands.valid]);

        if isempty(valid_cands)
            fprintf('   Το τμήμα "%s" ΔΕΝ έχει εναλλακτική πηγή τροφοδότησης.\n\n', orphan_groups(g));
            actions(end+1) = struct('group', orphan_groups(g), 'rescued', false, ...
                'winner_cb', '', 'side', '', 'chain', [], 'cbs_to_close', {{}}, ...
                'close_details', struct('name', {}, 'existing_load', {}, 'new_load', {}), ...
                'source', ''); %#ok<AGROW>
            continue;
        end

        [~, best_idx] = max([valid_cands.min_margin]);
        best = valid_cands(best_idx);

        needs_close_mask = [best.chain.needs_close];
        cbs_to_close = {best.chain(needs_close_mask).name};

        close_details = struct('name', {}, 'existing_load', {}, 'new_load', {});
        chain_needs_close = best.chain(needs_close_mask);
        for li = 1:numel(chain_needs_close)
            close_details(end+1) = struct( ...
                'name', chain_needs_close(li).name, ...
                'existing_load', chain_needs_close(li).existing_load, ...
                'new_load', chain_needs_close(li).new_load); %#ok<AGROW>
        end
        source_name = char(best.chain(end).name); % ο τελευταίος κρίκος = η τελική πηγή

        fprintf('   ==> Επιλέχθηκε η Αλυσίδα %d (μεγαλύτερο διαθέσιμο περιθώριο: %g A).\n', ...
            best.option_number, best.min_margin);

        if isempty(cbs_to_close)
            fprintf('   Το τμήμα "%s" τροφοδοτείται μέσω %s — όλοι οι διακόπτες της διαδρομής είναι ήδη κλειστοί, καμία ενέργεια απαιτείται.\n\n', ...
                orphan_groups(g), best.candidate_cb);
        else
            fprintf('   Το τμήμα "%s" σώζεται μέσω %s. Δίνεται εντολή κλεισίματος στους διακόπτες: %s.\n\n', ...
                orphan_groups(g), best.candidate_cb, strjoin(cbs_to_close, ', '));
        end

        % --- Προειδοποίηση μοιρασμένου φορτίου (αν υπάρχουν ΚΑΙ ΑΛΛΕΣ ---
        % έγκυρες διαδρομές, όχι μόνο η νικήτρια) ---
        % ΔΕΝ κάνουμε πλήρες load-flow (Kirchhoff) ανάμεσα σε παράλληλες
        % πηγές - στην πράξη το πραγματικό ρεύμα μπορεί να μοιράζεται
        % ανάμεσα σε όλες τις έγκυρες διαδρομές ταυτόχρονα, όχι μόνο μέσω
        % της "νικήτριας". Επισημαίνουμε ρητά τους ήδη-κλειστούς διακόπτες
        % των ΑΛΛΩΝ έγκυρων διαδρομών, ώστε ο μηχανικός να το λάβει υπόψη.
        %
        % ΕΠΙΠΛΕΟΝ: αν κάποιος τέτοιος ήδη κλειστός διακόπτης έχει
        % existing_load == 0 (δηλαδή ήδη σήμερα δεν κουβαλάει τίποτα 
        % καθαρό, ανενεργό backup-tie σημείο, π.χ. (20)T24 Pl.1 όταν η
        % Line_7 τροφοδοτείται ήδη αλλού), τότε ΔΕΝ υπάρχει κίνδυνος να
        % "χάσουμε" κάτι υπάρχον ανοίγοντάς το. Το προτείνουμε ρητά σαν
        % πρόταση ανοίγματος (όχι αυτόματη εντολή - παραμένει στον
        % μηχανικό να το επιβεβαιώσει/εκτελέσει). Αν αντίθετα ήδη
        % κουβαλάει πραγματικό φορτίο (existing>0), ΔΕΝ προτείνουμε άνοιγμα
        % μόνο προειδοποιούμε, γιατί θα έκοβε κάτι άσχετο που ήδη δουλεύει.
        if numel(valid_cands) > 1
            fprintf('   Σημείωση: εντοπίστηκαν %d έγκυρες εναλλακτικές αλυσίδες για το "%s". Το πρόγραμμα δεν προσομοιώνει πλήρη κατανομή ρεύματος (Kirchhoff) — στην πράξη το πραγματικό φορτίο μπορεί να μοιράζεται ανάμεσά τους. Προτείνεται επιτόπια επιβεβαίωση, ιδίως στους ήδη κλειστούς διακόπτες των υπόλοιπων αλυσίδων:\n\n', ...
                numel(valid_cands), orphan_groups(g));
            for oc = 1:numel(valid_cands)
                if oc == best_idx
                    continue;
                end
                other = valid_cands(oc);
                other_needs_close = [other.chain.needs_close];
                already_closed = other.chain(~other_needs_close);
                already_closed_names = {already_closed.name};
                if ~isempty(already_closed_names)
                    fprintf('      Αλυσίδα %d (μέσω %s): %s\n', ...
                        other.option_number, other.candidate_cb, strjoin(already_closed_names, ', '));
                end

                safe_to_open = already_closed([already_closed.existing_load] == 0);
                if ~isempty(safe_to_open)
                    safe_names = {safe_to_open.name};
                    fprintf('         Πρόταση: %s δεν κουβαλάει φορτίο σήμερα — ασφαλές να ανοίξει προληπτικά ώστε να μη μοιραστεί το νέο φορτίο.\n', ...
                        strjoin(safe_names, ', '));
                end
            end
            fprintf('\n');
        end

        actions(end+1) = struct('group', orphan_groups(g), 'rescued', true, ...
            'winner_cb', best.candidate_cb, 'side', best.side, 'chain', best.chain, ...
            'cbs_to_close', {cbs_to_close}, 'close_details', close_details, ...
            'source', source_name); %#ok<AGROW>
    end

    fprintf('--- Τέλος Compare Loads ---\n');

    % --- Συγκεντρωτικό μήνυμα: όλα τα τελικά paths + όλες οι εντολές μαζί ---
    rescued_actions = actions([actions.rescued]);
    if ~isempty(rescued_actions)
        fprintf('\n=== Συγκεντρωτική Αναφορά ===\n\n');
        all_cbs_to_close = {};
        for a = 1:numel(rescued_actions)
            act = rescued_actions(a);
            chain_names = {act.chain.name};
            fprintf('   %s  ->  %s\n', act.group, strjoin(chain_names, ' -> '));
            all_cbs_to_close = [all_cbs_to_close, act.cbs_to_close]; %#ok<AGROW>
        end
        all_cbs_to_close = unique(all_cbs_to_close, 'stable');
        if isempty(all_cbs_to_close)
            fprintf('\n   Καμία εντολή κλεισίματος απαιτείται (όλες οι διαδρομές ήδη κλειστές).\n');
        else
            fprintf('\n   Συνολική εντολή κλεισίματος: %s\n', strjoin(all_cbs_to_close, ', '));
        end
    end
end
