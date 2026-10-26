function Operation_Note(target_line, close_details, open_switches, sources)
% =========================================================================
% FUNCTION: Operation_Note
% -------------------------------------------------------------------------
% Το "Operation Note" ρουτίνα του flowchart: τυπώνει το ΤΕΛΙΚΟ,
% συγκεντρωτικό βήμα-βήμα των χειρισμών, ποιοι διακόπτες ΚΛΕΙΝΟΥΝ
% (δίνεται εναλλακτική τροφοδοσία, με ένδειξη φορτίου πριν/μετά όπου είναι
% διαθέσιμη) και ποιοι ΑΝΟΙΓΟΥΝ (απομονώνεται το σφάλμα), με τη σειρά,
% μαζί με ημερομηνία/ώρα, την/τις τελική/ές πηγή/ές τροφοδοσίας, και τις
% τυπικές υπενθυμίσεις ασφαλείας (CHECK, GROUND) κατά το πρότυπο του
% paper και πραγματικού εντύπου ΔΕΔΔΗΕ.
%
% ΣΕΙΡΑ ΕΝΕΡΓΕΙΩΝ (όπως και στο paper): πρώτα ΟΛΑ τα κλεισίματα (Reverse
% Current/Compare Loads), ΜΕΤΑ όλα τα ανοίγματα (Sequence).
%
% ΣΤΟΙΧΕΙΑ ΤΟΥ PAPER ΠΟΥ ΔΕΝ ΣΥΜΠΕΡΙΛΑΜΒΑΝΟΝΤΑΙ (ακόμα):
%   - IMPORTANT AND SENSITIVE CUSTOMERS: απαιτεί σύνδεση με βάση
%     καταναλωτών/GIS που δεν υπάρχει ακόμα στο project (εκκρεμεί).
%   - ENGINEER SIGNATURE: δεν έχει νόημα σε αυτοματοποιημένη έξοδο.
%   - CHECK / GROUND: τυπώνονται σαν ΥΠΕΝΘΥΜΙΣΕΙΣ/ερωτήματα προς τον
%     μηχανικό, ΟΧΙ σαν κάτι που το πρόγραμμα επιβεβαίωσε.
%
% ΕΙΣΟΔΟΙ:
%   target_line     : π.χ. 'Line_7'
%   close_details    : struct array (name, existing_load, new_load) - οι
%                      διακόπτες που ΚΛΕΙΝΟΥΝ, με τα φορτία πριν/μετά όπου
%                      είναι γνωστά (NaN αν όχι - π.χ. Reverse Current).
%                      Μπορεί να είναι κενό struct array.
%   open_switches    : cellstr (ή string array) με τα ονόματα των
%                      διακοπτών που ΑΝΟΙΓΟΥΝ (μπορεί να είναι άδειο)
%   sources          : ΠΡΟΑΙΡΕΤΙΚΟ - cellstr (ή string array) με την/τις
%                      τελική/ές πηγή/ές τροφοδοσίας (π.χ. {"53/VIII"})
% =========================================================================

    if nargin < 4
        sources = {};
    end

    open_switches = clean_list(open_switches);
    sources = clean_list(sources);
    now_moment = datetime('now');

    fprintf('\n=========================================================\n');
    fprintf('                     OPERATION NOTE\n');
    fprintf('=========================================================\n');
    fprintf(' ΓΡΑΜΜΗ  : %s\n', target_line);
    fprintf(' DATE    : %s\n', datestr(now_moment, 'dd/mm/yyyy')); %#ok<DATST>
    fprintf(' TIME    : %s\n', datestr(now_moment, 'HH:MM:SS')); %#ok<DATST>
    if ~isempty(sources)
        fprintf(' ΠΗΓΗ/ΕΣ ΤΡΟΦΟΔΟΣΙΑΣ : %s\n', strjoin(sources, ', '));
    end
    fprintf('---------------------------------------------------------\n');

    n_close = numel(close_details);
    n_open = numel(open_switches);

    if n_close == 0 && n_open == 0
        fprintf(' Δεν απαιτήθηκε καμία ενέργεια σε διακόπτες για τη γραμμή %s.\n', target_line);
        fprintf('=========================================================\n\n');
        return;
    end

    fprintf(' Για την απομόνωση της γραμμής %s ακολουθούνται τα εξής βήματα:\n\n', target_line);

    step = 1;
    for i = 1:n_close
        d = close_details(i);
        if isfield(d, 'existing_load') && isfield(d, 'new_load') && ...
                ~isnan(d.existing_load) && ~isnan(d.new_load)
            fprintf('   Βήμα %d:  Κλείσιμο διακόπτη  %-18s  (πριν: %g A  ->  μετά: %g A)\n', ...
                step, d.name, d.existing_load, d.new_load);
        else
            fprintf('   Βήμα %d:  Κλείσιμο διακόπτη  %s\n', step, d.name);
        end
        step = step + 1;
    end
    for i = 1:n_open
        fprintf('   Βήμα %d:  Άνοιγμα διακόπτη   %s\n', step, open_switches{i});
        step = step + 1;
    end

    fprintf('\n---------------------------------------------------------\n');
    fprintf(' ΥΠΕΝΘΥΜΙΣΕΙΣ ΓΙΑ ΤΟΝ ΜΗΧΑΝΙΚΟ (να επιβεβαιωθούν επιτόπου):\n');
    fprintf('   [?] CHECK  : Επιβεβαιώθηκε ότι δεν υπάρχει πλέον τάση στο απομονωμένο τμήμα;\n');
    fprintf('   [?] GROUND : Έγινε γείωση του απομονωμένου τμήματος;\n');
    fprintf('=========================================================\n\n');
end

function out = clean_list(in)
    % Δέχεται cellstr, string array, ή ακόμα και κενό/απροσδιόριστο, και
    % επιστρέφει πάντα cellstr χωρίς κενά/διπλότυπα, με σταθερή σειρά.
    if isempty(in)
        out = {};
        return;
    end
    s = string(in);
    s = s(s ~= "");
    s = unique(s, 'stable');
    out = cellstr(s);
end
