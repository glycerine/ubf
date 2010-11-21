%% @doc UBF(B) contract parser.
%%
%% Parsing a UBF(B) contract is done via a compiler "parse transform"
%% during the usual compilation of an Erlang source module.
%%
%% @TODO More documentation required here.

-module(contract_parser).

%% parse contract language
%% Copyright 2002 Joe Armstrong (joe@sics.se)
%% Documentation http:://www.sics.se/~joe/ubf.html

-include("ubf_impl.hrl").

-export([parse_transform/2,
         make/0, make_lex/0, make_yecc/0, preDefinedTypes/0, preDefinedTypesWithoutAttrs/0, preDefinedTypesWithAttrs/0,
         tags/1, tags/2,
         parse_transform_contract/2,
         parse_file/1
        ]).

-import(lists, [filter/2, map/2, member/2, foldl/3]).

parse_transform(In, Opts) ->
    %% DEBUG io:format("In:~p~n   Opts: ~p~n",[In, Opts]),
    Imports = [X||{attribute,_,add_types,X} <- In],
    case [X||{attribute,_,add_contract,X} <- In] of
        [File] ->
            %% DEBUG io:format("Contract: ~p ~p~n", [File, Imports]),
            case file(File ++ infileExtension(), Imports) of
                {ok, Contract, Header} ->
                    HeaderFile =
                        filename:join(
                          case proplists:get_value(outdir, Opts) of undefined -> "."; OutDir -> OutDir end
                          , filename:basename(File) ++ outfileHUCExtension()
                         ),
                    %% header - hrl
                    TermHUC =
                        ["
%%%
%%% Auto-generated by contract_parser:parse_transform()
%%% Do not edit manually!
%%%
\n"]
                        ++ ["-ifndef('", File ++ ".huc", "').\n"]
                        ++ ["-define('", File ++ ".huc", "', true).\n"]
                        ++ [Header|"\n"]
                        ++ ["-endif.\n"],
                    %% DEBUG io:format("Contract Header written: ~p~n", [HeaderFile]),
                    ok = file:write_file(HeaderFile, TermHUC),
                    %% DEBUG io:format("Contract added:~n"),
                    parse_transform_contract(In, Contract);
                {error, Reason} ->
                    io:format("Error in contract:~p~n", [Reason]),
                    erlang:error(Reason)
            end;
        [] ->
            In
    end.

parse_transform_contract(In, Contract) ->
    {Export, Fns} = make_code(Contract),
    In1 = merge_in_code(In, Export, Fns),
    %% lists:foreach(fun(I) -> io:format(">>~s<<~n",[erl_pp:form(I)]) end, In1),
    In1.

make_code(C) ->
    %% contract name
    F1 = {function,0,contract_name,0,
          [{clause,0,[],[],[{string,0,C#contract.name}]}]},
    %% contract vsn
    F2 = {function,0,contract_vsn,0,
          [{clause,0,[],[],[{string,0,C#contract.vsn}]}]},
    %% contract types
    TypeNames = map(fun({Type,_, _}) -> Type end, C#contract.types),
    F3 = {function,0,contract_types,0,
          [{clause,0,[],[],[erl_parse:abstract(TypeNames, 0)]}]},
    %% contract leaftypes
    LeafTypeNames = C#contract.leaftypenames,
    F4 = {function,0,contract_leaftypes,0,
          [{clause,0,[],[],[erl_parse:abstract(LeafTypeNames, 0)]}]},
    %% contract importtypes
    ImportTypeNames = C#contract.importtypenames,
    F5 = {function,0,contract_importtypes,0,
          [{clause,0,[],[],[erl_parse:abstract(ImportTypeNames, 0)]}]},
    %% contract records
    RecordNames = map(fun({Record, _}) -> Record end, C#contract.records),
    F6 = {function,0,contract_records,0,
          [{clause,0,[],[],[erl_parse:abstract(RecordNames, 0)]}]},
    %% contract states
    StateNames =
        if C#contract.transitions =:= [] ->
                [];
           true ->
                map(fun({State,_}) -> State end, C#contract.transitions)
        end,
    F7 = {function,0,contract_states,0,
          [{clause,0,[],[],[erl_parse:abstract(StateNames, 0)]}]},
    %% contract type
    Type =
        if C#contract.types =:= [] ->
                [{clause,1,[{var,0,'_'}],[],[erl_parse:abstract([], 0)]}];
           true ->
                map(fun({Type,Val,Str}) ->
                            {clause,1,[{atom,0,Type}],[],[erl_parse:abstract({Val,Str})]}
                    end, C#contract.types)
        end,
    F8 = {function,0,contract_type,1,Type},
    %% contract record
    Record =
        if C#contract.records =:= [] ->
                [{clause,1,[{var,0,'_'}],[],[erl_parse:abstract([], 0)]}];
           true ->
                map(fun({Record, Val}) ->
                            {clause,1,[{atom,0,Record}],[],[erl_parse:abstract(Val)]}
                    end, C#contract.records)
        end,
    F9 = {function,0,contract_record,1,Record},
    %% contract state
    State =
        if C#contract.transitions =:= [] ->
                [{clause,1,[{var,0,'_'}],[],[erl_parse:abstract([], 0)]}];
           true ->
                map(fun({State,Val}) ->
                            {clause,1,[{atom,0,State}],[],[erl_parse:abstract(Val)]}
                    end, C#contract.transitions)
        end,
    F10 = {function,0,contract_state,1,State},
    %% contract anystate
    Any =
        if C#contract.anystate =:= [] ->
                [];
           true ->
                C#contract.anystate
        end,
    F11 = {function,0,contract_anystate,0,
           [{clause,0,[],[],[erl_parse:abstract(Any, 0)]}]},
    %% exports
    Exports = {attribute,0,export,
               [{contract_name,0},
                {contract_vsn,0},
                {contract_types,0},
                {contract_leaftypes,0},
                {contract_importtypes,0},
                {contract_records,0},
                {contract_states,0},
                {contract_type,1},
                {contract_record,1},
                {contract_state,1},
                {contract_anystate,0}
               ]},
    %% funcs
    Funcs =  [F1,F2,F3,F4,F5,F6,F7,F8,F9,F10,F11],
    {Exports, Funcs}.

merge_in_code([H|T], Exports, Fns)
  when element(1, H) == function orelse element(1, H) == eof ->
    [Exports,H|Fns++T];
merge_in_code([H|T], Exports, Fns) ->
    [H|merge_in_code(T, Exports, Fns)];
merge_in_code([], Exports, Fns) ->
    [Exports|Fns].

make() ->
    make_lex(),
    make_yecc().

make_lex() ->
    {ok,_} = leex:file(contract_lex),
    ok.

make_yecc() ->
    {ok,_} = yecc:file(contract_yecc),
    ok.

parse_file(F) ->
    {ok, Stream} = file:open(F, [read]),
    try
        handle(Stream, 1, [], 0)
    after
        file:close(Stream)
    end.

infileExtension()  -> ".con".
outfileHUCExtension() -> ".huc".  %% hrl UBF contract records

file(F, Imports) ->
    case parse_file(F) of
        {ok, P} ->
            tags(P, Imports);
        E ->
            E
    end.

tags(P1) ->
    tags(P1, []).

tags(P1, Imports) ->
    case (catch pass2(P1, Imports)) of
        {'EXIT', E} ->
            {error, E};
        Contract ->
            case (catch pass4(Contract)) of
                {'EXIT', E} ->
                    {error, E};
                {Records,RecordExts} ->
                    case pass5(Contract) of
                        [] ->
                            noop;
                        UnusedTypes ->
                            if Contract#contract.transitions =/= [] orelse Contract#contract.anystate =/= [] ->
                                    case UnusedTypes -- Contract#contract.importtypenames of
                                        [] ->
                                            noop;
                                        UnusedNonImportTypes ->
                                            erlang:error({unused_types, UnusedNonImportTypes})
                                    end;
                               true ->
                                    noop
                            end
                    end,
                    %% extra leaf type names
                    LeafTypeNames = pass6(Contract),
                    %% create Records
                    AllRecords =
                        lists:keysort(1, [ {{Name,length(FieldsNValues)},FieldsNValues}
                                           || {Name,FieldsNValues} <- Records ]
                                      ++ [ {{Name,length(FieldsNValues)+2},[{'$fields',undefined}|[{'$extra',undefined}|FieldsNValues]]}
                                           || {Name,FieldsNValues} <- RecordExts ]),
                    %% create Header
                    Header =
                        lists:flatten(foldl(fun({{Name,_}, FieldsNValues},L) ->
                                                    FieldStrs = [
                                                                 case Value of
                                                                     {Type,X} when Type =:= atom;
                                                                                   Type =:= binary;
                                                                                   Type =:= float;
                                                                                   Type =:= integer;
                                                                                   Type =:= string ->
                                                                         io_lib:format("'~s'= ~p", [atom_to_list(Field), X]);
                                                                     _ ->
                                                                         io_lib:format("'~s'", [atom_to_list(Field)])
                                                                 end
                                                                 || {Field,Value} <- FieldsNValues ],
                                                    FStr = join(FieldStrs, $,),
                                                    NameStr = atom_to_list(Name),
                                                    IfNdef = io_lib:format("-ifndef('~s').~n",[NameStr]),
                                                    Define = io_lib:format("-define('~s',true).~n",[NameStr]),
                                                    Record = io_lib:format("-record('~s',{~s}).~n",[NameStr,FStr]),
                                                    EndIf = "-endif.",
                                                    L++io_lib:format("~n~s~s~s~s~n",[IfNdef,Define,Record,EndIf])
                                            end
                                            , "\n", AllRecords)),
                    %% filter Records
                    FilterRecords =
                        [ {{Name,Arity}, [ Fields || {Fields,_Values} <- FieldsNValues ]}
                          || {{Name,Arity}, FieldsNValues} <- AllRecords ],
                    {ok, Contract#contract{leaftypenames=LeafTypeNames, records=FilterRecords}, Header}
            end
    end.

preDefinedTypes() -> preDefinedTypesWithoutAttrs() ++ preDefinedTypesWithAttrs().

preDefinedTypesWithoutAttrs() ->
    [atom, binary, float, integer, list, proplist, string, term, tuple, void].

preDefinedTypesWithAttrs() ->
    [
     %% atom
     {atom,[ascii]}, {atom,[asciiprintable]}, {atom,[nonempty]}, {atom,[nonundefined]}
     , {atom,[ascii,nonempty]}, {atom,[ascii,nonundefined]}, {atom,[asciiprintable,nonempty]}, {atom,[asciiprintable,nonundefined]}
     , {atom,[ascii,nonempty,nonundefined]}, {atom,[asciiprintable,nonempty,nonundefined]}
     , {atom,[nonempty,nonundefined]}
     %% binary
     , {binary,[ascii]}, {binary,[asciiprintable]}, {binary,[nonempty]}
     , {binary,[ascii,nonempty]}, {binary,[asciiprintable,nonempty]}
     %% list
     , {list,[nonempty]}
     %% proplist
     , {proplist,[nonempty]}
     %% string
     , {string,[ascii]}, {string,[asciiprintable]}, {string,[nonempty]}
     , {string,[ascii,nonempty]}, {string,[asciiprintable,nonempty]}
     %% term
     , {term,[nonempty]}, {term,[nonundefined]}
     , {term,[nonempty,nonundefined]}
     %% tuple
     , {tuple,[nonempty]}
    ].

pass2(P, Imports) ->
    Name = require(one, name, P),
    Vsn = require(one, vsn, P),
    Types = require(zero_or_one, types, P),
    Any = require(zero_or_one, anystate, P),
    Trans = require(many, transition, P),

    ImportTypes = lists:flatten(
                    [
                      begin
                          case Import of
                              Mod when is_atom(Mod) ->
                                  Mod = Mod,
                                  TL = Mod:contract_types();
                              {Mod, TL} when is_atom(Mod), is_list(TL) ->
                                  Mod = Mod,
                                  TL = TL;
                              {Mod, {except, ETL}} when is_atom(Mod), is_list(ETL) ->
                                  Mod = Mod,
                                  TL = Mod:contract_types() -- ETL;
                              X ->
                                  Mod = unused,
                                  TL = unused,
                                  exit({invalid_import, X})
                          end,
                          [ begin {TDef, TTag} = Mod:contract_type(T), {T, TDef, TTag} end
                            || T <- TL ]
                      end
                      || Import <- Imports ]
                   ),
    ImportTypeNames = [ T || {T, _, _} <- ImportTypes ],

    C = #contract{name=Name, vsn=Vsn, anystate=Any,
                  types=Types, importtypenames=ImportTypeNames, transitions=Trans},
    pass3(C, ImportTypes).

require(Multiplicity, Tag, P) ->
    Vals =  [ Val || {T,Val} <- P, T == Tag ],
    case Multiplicity of
        zero_or_one ->
            case Vals of
                [] -> [];
                [V] -> V;
                _ ->
                    io:format("~p incorrectly defined~n",
                              [Tag]),
                    erlang:error(parse)
            end;
        one ->
            case Vals of
                [V] -> V;
                _ ->
                    io:format("~p missing or incorrectly defined~n",
                              [Tag]),
                    erlang:error(parse)
            end;
        many ->
            Vals
    end.

pass3(C1, ImportTypes) ->
    Types1 = C1#contract.types,
    Transitions = C1#contract.transitions,
    _Name = C1#contract.name,
    _Vsn = C1#contract.vsn,
    AnyState = C1#contract.anystate,

    %% DEBUG io:format("Types1=~p~n",[Types1]),
    DefinedTypes1 = [ I || {I,_,_} <- Types1 ] ++ [ {predef, I} || I <- preDefinedTypes() ],
    %% DEBUG io:format("Defined types1=~p~n",[DefinedTypes1]),
    case duplicates(DefinedTypes1, []) of
        [] -> true;
        L1 -> erlang:error({duplicated_types, L1})
    end,

    C2 = C1#contract{types=lists:usort(Types1 ++ ImportTypes)},
    Types2 = C2#contract.types,
    %% DEBUG io:format("Types2=~p~n",[Types2]),
    DefinedTypes2 = [ I || {I,_,_} <- Types2 ] ++ [ {predef, I} || I <- preDefinedTypes() ],
    %% DEBUG io:format("Defined types2=~p~n",[DefinedTypes2]),
    case duplicates(DefinedTypes2, []) of
        [] -> true;
        L2 -> erlang:error({duplicated_unmatched_import_types, L2})
    end,

    %% DEBUG io:format("Transitions=~p~n",[Transitions]),
    UsedTypes = extract_prims({Types2,Transitions,AnyState}, []),
    MissingTypes = UsedTypes -- DefinedTypes2,
    %% DEBUG io:format("Used types=~p~n",[UsedTypes]),
    case MissingTypes of
        [] ->
            DefinedStates = [S||{S,_} <- Transitions] ++ [stop],
            %% DEBUG io:format("defined states=~p~n",[DefinedStates]),
            case duplicates(DefinedStates, []) of
                [] -> true;
                L3 -> erlang:error({duplicated_states, L3})
            end,
            %% DEBUG io:format("Transitions=~p~n",[Transitions]),
            UsedStates0 = [S||{_,Rules} <- Transitions,
                              {input,_,Out} <- Rules,
                              {output,_,S} <- Out],
            UsedStates = remove_duplicates(UsedStates0),
            %% DEBUG io:format("Used States=~p~n",[UsedStates]),
            MissingStates = filter(fun(I) ->
                                           not member(I, DefinedStates) end,
                                   UsedStates),
            case MissingStates of
                [] -> C2;
                _  -> erlang:error({missing_states, MissingStates})
            end;
        _ ->
            erlang:error({missing_types, MissingTypes})
    end.

pass4(C) ->
    Types = C#contract.types,
    Records = extract_records(Types,[]),
    RecordExts = extract_record_exts(Types,[]),
    case duplicates(Records++RecordExts, []) of
        [] -> true;
        L1 -> erlang:error({duplicated_records, L1})
    end,
    %% DEBUG io:format("Types=~p~nRecords=~p~nRecordExts=~p~n",[Types,Records,RecordExts]),
    {Records,RecordExts}.

pass5(C) ->
    Transitions = C#contract.transitions,
    AnyState = C#contract.anystate,
    %% DEBUG io:format("Types=~p~n",[Types]),
    UsedTypes = extract_prims({Transitions,AnyState}, []),
    pass5(C, UsedTypes, []).

pass5(C, [], L) ->
    Types = C#contract.types,
    DefinedTypes = map(fun({I,_, _}) -> I end, Types),
    DefinedTypes -- L;
pass5(C, [H|T], L) ->
    Types = C#contract.types,
    TypeDef = [ Y || {X,Y,_Z} <- Types, X =:= H ],
    UsedTypes = [ UsedType || UsedType <- extract_prims(TypeDef, []), not member(UsedType, L) ],
    pass5(C, T ++ UsedTypes, [H|L]).

pass6(C) ->
    Transitions = C#contract.transitions,
    AnyState = C#contract.anystate,
    %% DEBUG io:format("Types=~p~n",[Types]),
    RootUsedTypes = extract_prims({Transitions,AnyState}, []),
    pass6(C, RootUsedTypes, RootUsedTypes, []).

pass6(C, RootUsedTypes, [], L) ->
    Types = C#contract.types,
    DefinedTypes = map(fun({I,_, _}) -> I end, Types),
    DefinedTypes -- (RootUsedTypes -- L);
pass6(C, RootUsedTypes, [H|T], L) ->
    Types = C#contract.types,
    TypeDef = [ Y || {X,Y,_Z} <- Types, X =:= H ],
    UsedTypes = [ UsedType || UsedType <- extract_prims(TypeDef, []), member(UsedType, RootUsedTypes) ],
    pass6(C, RootUsedTypes, T, UsedTypes ++ L).

duplicates([H|T], L) ->
    case member(H, T) of
        true ->
            duplicates(T, [H|L]);
        false ->
            duplicates(T, L)
    end;
duplicates([], L) ->
    L.

extract_prims({prim, _Min, _Max, X}, L) ->
    case member(X, L) of
        false -> [X|L];
        true  -> L
    end;
extract_prims(T, L) when is_tuple(T) ->
    foldl(fun extract_prims/2, L, tuple_to_list(T));
extract_prims(T, L) when is_list(T) ->
    foldl(fun extract_prims/2, L, T);
extract_prims(_T, L) ->
    L.

%% ignore nested records
extract_records({record, Name, [Fields|Values]}, L) ->
    X = {Name,lists:zip(extract_fields(Fields),tl(Values))},
    case member(X, L) of
        true  -> L;
        false -> [X|L]
    end;
extract_records(T, L) when is_tuple(T) ->
    foldl(fun extract_records/2, L, tuple_to_list(T));
extract_records(T, L) when is_list(T) ->
    foldl(fun extract_records/2, L, T);
extract_records(_T, L) ->
    L.

%% ignore nested record_exts
extract_record_exts({record_ext, Name, [Fields|Values]}, L) ->
    X = {Name,lists:zip(extract_fields(Fields),tl(Values))},
    case member(X, L) of
        true  -> L;
        false -> [X|L]
    end;
extract_record_exts(T, L) when is_tuple(T) ->
    foldl(fun extract_record_exts/2, L, tuple_to_list(T));
extract_record_exts(T, L) when is_list(T) ->
    foldl(fun extract_record_exts/2, L, T);
extract_record_exts(_T, L) ->
    L.

extract_fields({atom,undefined}) ->
    [];
extract_fields({alt,{atom,undefined},{tuple,T}}) ->
    [Field || {atom,Field} <- T].

handle(Stream, LineNo, L, NErrors) ->
    handle1(io:requests(Stream, [{get_until,foo,contract_lex,
                                  tokens,[LineNo]}]), Stream, L, NErrors).

handle1({ok, Toks, Next}, Stream, L, Nerrs) ->
    case contract_yecc:parse(Toks) of
        {ok, Parse} ->
            %% DEBUG io:format("Parse=~p~n",[Parse]),
            handle(Stream, Next, [Parse|L], Nerrs);
        {error, {Line, Mod, What}} ->
            Str = Mod:format_error(What),
            %% DEBUG io:format("Toks=~p~n",[Toks]),
            io:format("** ~w ~s~n", [Line, Str]),
            %% handle(Stream, Next, L, Nerrs+1);
            {error, 1};
        Other ->
            io:format("Bad_parse:~p\n", [Other]),
            handle(Stream, Next, L, Nerrs+1)
    end;
handle1({eof, _}, _Stream, L, 0) ->
    {ok, lists:reverse(L)};
handle1({eof, _}, _Stream, _L, N) ->
    {error, N};
handle1(What, _Stream, _L, _N) ->
    {error, What}.

remove_duplicates([H|T]) ->
    case member(H, T) of
        true ->
            remove_duplicates(T);
        false ->
            [H|remove_duplicates(T)]
    end;
remove_duplicates([]) -> [].

join(L, Sep) ->
    lists:flatten(join2(L, Sep)).

join2([A, B|Rest], Sep) ->
    [A, Sep|join2([B|Rest], Sep)];
join2(L, _Sep) ->
    L.
