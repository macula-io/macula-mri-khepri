%%%-------------------------------------------------------------------
%%% @doc
%%% Shared MRI parsing utilities for macula_mri_khepri.
%%%
%%% This module provides internal helper functions for parsing Macula
%%% Resource Identifiers (MRIs) into their component parts.
%%%
%%% @private
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_parse).

-export([parse/1, to_path/1]).

%%====================================================================
%% Types
%%====================================================================

-type mri() :: binary().
-type mri_type() :: atom().
-type realm() :: binary().
-type segments() :: [binary()].

-export_type([mri/0, mri_type/0, realm/0, segments/0]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Parse an MRI into its components.
%%
%% Returns `{ok, Type, Realm, Segments}' on success, where:
%% - `Type' is the resource type as an atom (e.g., `app', `device')
%% - `Realm' is the realm identifier (e.g., `<<"io.macula">>')
%% - `Segments' is a list of path segments
%%
%% Returns `{error, Reason}' on failure.
%%
%% Example:
%% ```
%% parse(<<"mri:app:io.macula/acme/counter">>) ->
%%     {ok, app, <<"io.macula">>, [<<"acme">>, <<"counter">>]}
%% '''
-spec parse(mri()) -> {ok, mri_type(), realm(), segments()} | {error, term()}.
parse(<<"mri:", Rest/binary>>) ->
    case binary:split(Rest, <<":">>) of
        [TypeBin, RealmPath] ->
            Type = safe_to_atom(TypeBin),
            case binary:split(RealmPath, <<"/">>) of
                [Realm] ->
                    {ok, Type, Realm, []};
                [Realm | Segments] ->
                    %% Handle case where split returns [Realm, Rest]
                    AllSegments = case Segments of
                        [PathRest] -> binary:split(PathRest, <<"/">>, [global]);
                        Other -> Other
                    end,
                    {ok, Type, Realm, AllSegments}
            end;
        _ ->
            {error, invalid_format}
    end;
parse(_) ->
    {error, invalid_prefix}.

%% @doc Convert an MRI to a Khepri path.
%%
%% Returns a list suitable for use as a Khepri path.
%% Raises an error if the MRI is invalid.
%%
%% Example:
%% ```
%% to_path(<<"mri:app:io.macula/acme/counter">>) ->
%%     [mri, app, <<"io.macula">>, <<"acme">>, <<"counter">>]
%% '''
-spec to_path(mri()) -> [atom() | binary()].
to_path(MRI) ->
    case parse(MRI) of
        {ok, Type, Realm, Segments} ->
            [mri, Type, Realm | Segments];
        {error, Reason} ->
            error({invalid_mri, MRI, Reason})
    end.

%%====================================================================
%% Internal Functions
%%====================================================================

%% @private Safely convert binary to atom.
%% Prefers existing atoms to avoid atom table exhaustion,
%% but creates new atoms when necessary for new MRI types.
-spec safe_to_atom(binary()) -> atom().
safe_to_atom(Bin) ->
    try
        binary_to_existing_atom(Bin, utf8)
    catch
        error:badarg ->
            binary_to_atom(Bin, utf8)
    end.
