%% @hidden
-module(erlim_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).


%% We do not block on send anymore.
-define(TCP_SEND_TIMEOUT, 15000).

-define(TCP_OPTIONS, [binary,
    {ip, {0, 0, 0, 0}},
    {packet, 0},
    %% {backlog, 8192},
    {buffer, 1024},
    %% {recbuf, 8192},
    {active, false},
    {reuseaddr, true},
    {nodelay, true},
    {send_timeout, ?TCP_SEND_TIMEOUT},
    {send_timeout_close, true},
    {keepalive, true}]
).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    erlim_mnesia:init_mnesia(),

    [ok = application:start(App) ||
        App <- [syntax_tools, asn1, crypto, public_key, bcrypt, emysql]],
    ssl:start(),
    esockd:start(),
    lager:start(),
    {ok, [
        {<<"database">>,
            [{<<"encoding">>, <<"utf8">>}, {<<"db">>, <<"movie_together_development">>}, {<<"pwd">>, <<"root">>}, {<<"name">>, <<"root">>}, {<<"size">>, 1}, {<<"host">>, <<"192.168.10.140">>}]
        },
        {<<"socket">>,
            [{<<"time_out">>, 15000}, {<<"max_clients">>, 10000}, {<<"acceptors">>, 4}, {<<"port">>, 8080}]
        },
        {<<"ssl">>,
            [{<<"keyfile">>, <<"/home/yy/dev/erlang/erlim/crt/nginx.key">>}, {<<"certfile">>, <<"/home/yy/dev/erlang/erlim/crt/nginx.crt">>}, {<<"cacertfile">>, <<"/home/yy/dev/erlang/erlim/crt/demoCA/cacert....">>}]
        }
    ]},
    %% erlang app config file
    %% http://blog.yufeng.info/archives/2852
    {ok, [
        {<<"database">>,
            [
                {<<"encoding">>, Encoding},
                {<<"db">>, Dbname},
                {<<"pwd">>, Pwd},
                {<<"name">>, UserName},
                {<<"size">>, Size},
                {<<"host">>, Host}
            ]
        },
        {<<"socket">>,
            [
                {<<"use_ssl">>, EnableSSL},
                {<<"time_out">>, _TcpSentTimeOut},
                {<<"max_clients">>, MaxClients},
                {<<"acceptors">>, Acceptors},
                {<<"port">>, Port}
            ]
        },
        {<<"ssl">>,
            [
                {<<"keyfile">>, KeyFile},
                {<<"certfile">>, CertFile},
                {<<"cacertfile">>, CaCertFile}
            ]
        }
    ]} = toml_util:parse(),
    emysql:add_pool(erlim_pool, [
        {size, Size},
        {user, binary_to_list(UserName)},
        {password, binary_to_list(Pwd)},
        {host, binary_to_list(Host)},
        {database, binary_to_list(Dbname)},
        {encoding, binary_to_atom(Encoding, utf8)}
    ]),

    Opts = case EnableSSL of
               0 ->
                   [{acceptors, Acceptors},
                       {max_clients, MaxClients},
                       {sockopts, ?TCP_OPTIONS}];
               1 ->
                   %% http://www.ttlsa.com/nginx/nginx-configuration-ssl/
                   %% http://erlycoder.com/87/ssl-how-to-self-signed-ssl-certifiate-creation-with-open-ssl
                   SslOpts = [
                       {cacertfile, binary_to_list(CaCertFile)},
                       {certfile, binary_to_list(CertFile)},
                       {keyfile, binary_to_list(KeyFile)}
                   ],
                   [{acceptors, Acceptors},
                       {max_clients, MaxClients},
                       {ssl, SslOpts},
                       {sockopts, ?TCP_OPTIONS}];
               _ -> exit(config_file_error)
           end,

    MFArgs = {erlim_tls_receiver, start_link, []},
    esockd:open(onechat, Port, Opts, MFArgs),

    erlim_sup:start_link().

stop(_State) ->
    ok.