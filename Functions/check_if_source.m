function result = check_if_source(elem_name, network_elements)
% =========================================================================
% FUNCTION: check_if_source
% -------------------------------------------------------------------------
% Κρίνει αν ένα στοιχείο του δικτύου λειτουργεί ως πηγή τροφοδοσίας.
% Ένα στοιχείο θεωρείται πηγή όταν πληροί ΚΑΙ τα δύο κριτήρια:
%   1) Είναι "πηγή τύπου" είτε το όνομά του περιέχει "/" (γνήσια πηγή,
%      π.χ. "41/VIII"), είτε είναι Type=Busbar/Bus.
%   2) Είναι State=1 (κλειστό/normally-closed - "is_nc" = is normally closed).
%
% ΕΙΣΟΔΟΙ:
%   elem_name         : όνομα στοιχείου, π.χ. '41/VIII'
%   network_elements  : table (Sheet2)
%
% ΕΞΟΔΟΣ:
%   result : true/false
% =========================================================================
    result = false;
    sheet2_elements = strtrim(string(network_elements.Element));
    match_idx = find(strcmp(sheet2_elements, elem_name), 1);
    
    if ~isempty(match_idx)
        match_row = network_elements(match_idx, :);
        has_slash = contains(elem_name, '/');
        
        is_busbar = false;
        if ismember('Type', match_row.Properties.VariableNames)
            elem_type = strtrim(string(match_row.Type));
            is_busbar = strcmpi(elem_type, 'Busbar') || strcmpi(elem_type, 'Bus');
        end
        
        is_nc = false;
        if ismember('State', match_row.Properties.VariableNames)
            val_state = match_row.State;
            if isnumeric(val_state)
                is_nc = (val_state == 1);
            else
                is_nc = (str2double(string(val_state)) == 1);
            end
        end
        
        if (has_slash || is_busbar) && is_nc
            result = true;
        end
    end
end