%%%-------------------------------------------------------------------
%%% @doc
%%% Shared MRI parsing utilities for macula_mri_khepri.
%%%
%%% Delegates to macula_mri:parse/1 for the canonical MRI definition.
%%% This module converts parsed MRI maps to Khepri-specific paths.
%%%
%%% @private
%%% @end
%%%-------------------------------------------------------------------
-module(macula_mri_khepri_parse).

-export([parse/1, to_path/1]).

%%====================================================================
%% API Functions
%%====================================================================

%% @doc Parse an MRI into its components.
%%
%% Delegates to macula_mri:parse/1 and flattens the result.
%% Returns `{ok, Type, Realm, Segments}' on success.
%%
%% Example:
%% ```
%% parse(<<"mri:app:io.macula/acme/counter">>) ->
%%     {ok, app, <<"io.macula">>, [<<"acme">>, <<"counter">>]}
%% '''
-spec parse(binary()) ->
    {ok, macula_mri:mri_type(), macula_mri:realm(), [macula_mri:path_segment()]} |
    {error, term()}.
parse(MRI) ->
    case macula_mri:parse(MRI) of
        {ok, #{type := Type, realm := Realm, path := Segments}} ->
            {ok, Type, Realm, Segments};
        {error, _} = Err ->
            Err
    end.

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
-spec to_path(binary()) -> [atom() | binary()].
to_path(MRI) ->
    case parse(MRI) of
        {ok, Type, Realm, Segments} ->
            [mri, Type, Realm | Segments];
        {error, Reason} ->
            error({invalid_mri, MRI, Reason})
    end.
