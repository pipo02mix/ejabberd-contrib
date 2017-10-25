%%%----------------------------------------------------------------------
%%% File    : mod_cobrowser.erl
%%% Author  : pipo02mix
%%% Purpose : Post availability to API endpoint
%%% Created : 3 April 2017
%%% Id      : $Id: mod_cobrowser.erl 1034 2017-04-01 19:04:17Z pipo02mix $
%%%----------------------------------------------------------------------

-module(mod_cobrowser).
-author('fernando@cobrowser.net').

-behaviour(gen_mod).

%% Required by ?DEBUG macros
-include("logger.hrl").
-include("ejabberd.hrl").
-include("jlib.hrl").

%% gen_mod API callbacks
-export([start/2, stop/1, on_user_send_packet/4, on_disconnect/3,
  send_availability/4, getenv/2, depends/2, mod_opt_type/1, extract_show/1]).

start(Host, _Opts) ->
    ?INFO_MSG("mod_cobrowser starting", []),
    inets:start(),
    ejabberd_hooks:add(user_send_packet, Host, ?MODULE, on_user_send_packet, 50),
    ejabberd_hooks:add(sm_remove_connection_hook, Host, ?MODULE, on_disconnect, 50),
    ?INFO_MSG("mod_cobrowser hooks attached", []),
    ok.

stop(Host) ->
    ?INFO_MSG("mod_cobrowser stopping", []),
    
    ejabberd_hooks:delete(user_send_packet, Host, ?MODULE, on_user_send_packet, 50),
    ejabberd_hooks:delete(sm_remove_connection_hook, Host, ?MODULE, on_disconnect, 50),
    ok.

on_user_send_packet(#xmlel{
                      name = <<"presence">>,
                      attrs = Attrs
                    } = Pkt,
                    _C2SState,
                    #jid{lresource = <<"">>} = From,
                    _To) ->
    Type = fxml:get_attr_s(<<"type">>, Attrs),
    if Type == <<"unavailable">> ->
      Jid = binary_to_list(jlib:jid_to_string(From)),
      BareJid = string:sub_string(Jid,1,string:str(Jid,"/")-1),
      Resource = string:sub_string(Jid,string:str(Jid,"/")+1),
      send_availability(BareJid, "unavailable", "", Resource);
      true -> Pkt
    end,
    Pkt;
on_user_send_packet(#xmlel{
      name = <<"presence">>,
      attrs = Attrs
    } = Pkt,
    _C2SState,
    From,
    _To) ->
  Type = fxml:get_attr_s(<<"type">>, Attrs),
  if Type == <<"">>; Type == <<"available">> ->
    Show = lists:flatten(io_lib:format("~p", [extract_show(Pkt)])),
    Jid = binary_to_list(jlib:jid_to_string(From)),
    BareJid = string:sub_string(Jid,1,string:str(Jid,"/")-1),
    Resource = string:sub_string(Jid,string:str(Jid,"/")+1),
    send_availability(BareJid, "available", Show, Resource);
    true -> Pkt
  end,
  Pkt;
on_user_send_packet(Pkt, _C2SState, _From, _To) ->
  Pkt.

on_disconnect(Sid, Jid, Info) ->
    StrJid = binary_to_list(jlib:jid_to_string(Jid)),
    BareJid = string:sub_string(StrJid,1,string:str(StrJid,"/")-1),
    Resource = string:sub_string(StrJid,string:str(StrJid,"/")+1),
    ?DEBUG("(mod_cobrowser)onDisconnect: ~p, ~p, ~p, ~p", [ Sid, BareJid, Info, Resource]),
    send_availability(BareJid, "unavailable", "", Resource),

    ok.

extract_show(Pkt) ->
  El = fxml:get_subtag(Pkt, <<"show">>),
  case El of
    #xmlel{name = <<"show">>} -> fxml:get_tag_cdata(El);
    _ -> ""
  end.

send_availability(Jid, Type, Show, Resource) ->
      APIHost = getenv("NGINX_INTERNAL_SERVICE_HOST", "nginx-internal.default.svc.cluster.local"),
      APIEndpoint = "http://" ++ APIHost ++ "/api/app.php/internal/availability/user-presence.json?token=somesecret",
      ?DEBUG("sending packet: ~p type: ~p show: ~p resource: ~p api: ~p", [ Jid, Type, Show, Resource, APIEndpoint]),
      URL = APIEndpoint ++ "&jid=" ++ Jid ++ "&type=" ++ Type ++ "&show=" ++ Show ++ "&resource=" ++ Resource,
      R = httpc:request(post, {
          URL,
          [],
          "application/x-www-form-urlencoded",
          ""}, [], []),
      {ok, {{"HTTP/1.1", ReturnCode, _}, _, _}} = R,
      ?DEBUG("API request made with result -> ~p ", [ ReturnCode]),
      ReturnCode.

-spec depends(binary(), gen_mod:opts()) -> [{module(), hard | soft}].
depends(_Host, _Opts) ->
  [].

getenv(VarName, DefaultValue) ->
    case os:getenv(VarName) of
        false ->
           DefaultValue;
        Value ->
            Value
    end.

mod_opt_type(cache_life_time) ->
  fun (I) when is_integer(I), I > 0 -> I end;
mod_opt_type(cache_size) ->
  fun (I) when is_integer(I), I > 0 -> I end;
mod_opt_type(db_type) -> fun(T) -> ejabberd_config:v_db(?MODULE, T) end;
mod_opt_type(_) ->
  [cache_life_time, cache_size, db_type].