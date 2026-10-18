-module(glaph_rdf_line_reader_ffi).
-export([find_newline/1, detach/1]).

%% Returns the byte index of the first LF (0x0A) in Bin, or -1 if none.
find_newline(Bin) ->
    case binary:match(Bin, <<"\n">>) of
        {Pos, _Len} -> Pos;
        nomatch -> -1
    end.

%% Copies a (possibly sub-)binary so it no longer references the larger
%% read chunk it was sliced from, letting that chunk be garbage collected.
detach(Bin) ->
    binary:copy(Bin).
