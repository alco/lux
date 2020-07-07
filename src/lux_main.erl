%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Copyright 2012-2020 Tail-f Systems AB
%%
%% See the file "LICENSE" for information on usage and redistribution
%% of this file, and for a DISCLAIMER OF ALL WARRANTIES.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-module(lux_main).

-export([
         unsafe_main/1
        ]).

-include("lux.hrl").

-define(FILES, "--").

-spec(unsafe_main([string()]) -> non_neg_integer()).
unsafe_main(OrigArgs) ->
    LuxAppDir = require_app(undefined, ?APPLICATION),
    OpModes = ["--internal_debug", "--suite_trace",
               "--display_trace", "--event_trace",
               "--help", "--version", "--install",
               "--annotate", "--history",
               "--reltool", "--xref",
               "--gen_markdown", "--pre_markdown"],
    Args  = expand_flags(OrigArgs, OpModes),
    Specs = specs(),
    ThisEscript = require_escript(),
    Opts = getopts(Args, Specs, LuxAppDir, ThisEscript),
    %% io:format("Args: ~p\n", [Opts]),
    dispatch(Opts, LuxAppDir, OpModes, Specs, OrigArgs, ThisEscript).

dispatch([{files, Files}, {prev_log_dir, PrevLogDir} | Opts],
         _LuxAppDir, _OpModes, _Specs, OrigArgs, ThisEscript) ->
    run(Opts, Files, PrevLogDir, OrigArgs, ThisEscript);
dispatch(Opts, LuxAppDir, OpModes, Specs, OrigArgs, ThisEscript) ->
    case select_op(Opts, OpModes) of
        {Op, Args} ->
            do_dispatch(Op, Opts, LuxAppDir, OpModes, Specs,
                        Args, OrigArgs, ThisEscript);
        undefined ->
            case add_defaults(Opts) of
                {ok, [{files, Files}, {prev_log_dir, PrevLogDir} | Opts2]} ->
                    run(Opts2, Files, PrevLogDir, OrigArgs, ThisEscript);
                {error, Format, Args} ->
                    io:format(Format, Args),
                    1
            end
    end.

do_dispatch(Op, Opts, LuxAppDir, OpModes, Specs, Args, OrigArgs, ThisEscript) ->
   EscriptMod = escript_mod(ThisEscript),
    case {Op, Args} of
        {"--version", [_]} ->
            io:format("~p\n", [lux_utils:version()]),
            0;
        {"--gen_markdown", [File]} ->
            gen_markdown(File);
        {"--pre_markdown", [File]} ->
            pre_markdown(LuxAppDir, File);
        {"--internal_debug", [_]} ->
            internal_debug(Op, OrigArgs);
        {"--event_trace", [_]} ->
            event_trace(Op, LuxAppDir, Opts,
                        OpModes, Specs,
                        OrigArgs, ThisEscript);
        {"--suite_trace", [_]} ->
            suite_trace(Op, LuxAppDir, Opts,
                        OpModes, Specs,
                        OrigArgs, ThisEscript);
        {"--display_trace", [File]} ->
            display_trace(Op, LuxAppDir, File, Opts);
        {"--install", [InstallDir]} ->
            install(Op, LuxAppDir, InstallDir, Opts);
        {"--reltool", [_]} ->
            reltool(Op, LuxAppDir, Opts);
        {"--xref", [_]} ->
            xref(Op, LuxAppDir, Opts, EscriptMod);
        {"--annotate", [LogFile]} ->
            annotate(LogFile, Opts);
        {"--history", [LogDir]} ->
            history(LogDir, Opts);
        _BadArgs ->
            usage(Specs, LuxAppDir, EscriptMod)
    end.

expand_flags(Args, OpModes) ->
    case Args of
        [First | _] ->
            case lists:member(First, OpModes) of
                true  -> Args; % Ignore additional flags for aux commands
                false -> do_expand_flags(Args)
            end;
        [] ->
            do_expand_flags(Args)
    end.

do_expand_flags(Args) ->
    env_to_args("LUX_FLAGS") ++ env_to_args("LUX_SYSTEM_FLAGS") ++ Args.

env_to_args(Var) ->
    case os:getenv(Var) of
        false -> [];
        Flags -> string:tokens(Flags, " ")
    end.

select_op(Opts, [Key | Keys]) ->
    case proplists:get_value(Key, Opts) of
        [] ->
            select_op(Opts, Keys);
        Vals ->
            {Key, Vals}
    end;
select_op(_Opts, []) ->
    undefined.

specs() ->
    [
     {"-h",                   ["--help=usage"]},
     {"-r",                   ["--rerun=fail"]},
     {"-c",                   ["--progress=compact"]},
     {"-v",                   ["--progress=verbose"]},
     {"-V",                   ["--progress=etrace"]},
     {"-VV",                  ["--progress=ctrace"]},
     {"-t",                   ["--progress=silent", "--tap=stdout"]},
     {"-d",                   ["--debug"]},
     {"-D",                   ["--internal_debug"]},
     {"-E",                   ["--event_trace"]},
     {"-T",                   ["--suite_trace"]},
     {?FILES,                 "",          string,                 mandatory},
     {"--help",               usage,       {enum, help},           optional},
     {"--version",            false,       boolean,                none},
     {"--gen_markdown",       undefined,   string,                 mandatory},
     {"--pre_markdown",       undefined,   string,                 mandatory},
     {"--internal_debug",     false,       boolean,                none},
     {"--event_trace",        false,       boolean,                none},
     {"--suite_trace",        false,       boolean,                none},
     {"--display_trace",      undefined,   string,                 mandatory},
     {"--filter_trace",       undefined,   string,                 mandatory},
     {"--install",            "",          string,                 optional},
     {"--install_app",        undefined,   string,                 mandatory},
     {"--install_profile",    standalone,  {enum, profile},        mandatory},
     {"--reltool",            false,       boolean,                none},
     {"--xref",               false,       boolean,                none},
     {"--annotate",           false,       string,                 mandatory},
     {"--history",            false,       string,                 mandatory},
     {"--rerun",              enable,      {enum, prio},           mandatory},
     {"--html",               enable,      {enum, html},           mandatory},
     {"--debug",              false,       boolean,                none},
     {"--debug_file",         undefined,   string,                 mandatory},
     {"--skip",               undefined,   string,                 mandatory},
     {"--skip_unless",        undefined,   string,                 mandatory},
     {"--skip_unstable",      false,       boolean,                none},
     {"--skip_skip",          false,       boolean,                none},
     {"--require",            undefined,   string,                 mandatory},
     {"--case_prefix",        undefined,   string,                 mandatory},
     {"--log_dir",            undefined,   string,                 mandatory},
     {"--config_dir",         undefined,   string,                 mandatory},
     {"--config_name",        undefined,   string,                 mandatory},
     {"--suite",              undefined,   string,                 mandatory},
     {"--run",                undefined,   string,                 mandatory},
     {"--extend_run",         false,       boolean,                none},
     {"--revision",           undefined,   string,                 mandatory},
     {"--hostname",           undefined,   string,                 mandatory},
     {"--mode",               execute,     {enum, mode},           mandatory},
     {"--doc",                infinity,    {integer, 0, infinity}, optional},
     {"--progress",           brief,       {enum, progress},       mandatory},
     {"--multiplier",         1000,        {integer, 0, infinity}, mandatory},
     {"--suite_timeout",      infinity,    {integer, 0, infinity}, mandatory},
     {"--case_timeout",       5*60*1000,   {integer, 0, infinity}, mandatory},
     {"--flush_timeout",      1000,        {integer, 0, infinity}, mandatory},
     {"--poll_timeout",       100,         {integer, 0, infinity}, mandatory},
     {"--timeout",            10*1000,     {integer, 0, infinity}, mandatory},
     {"--cleanup_timeout",    100*1000,    {integer, 0, infinity}, mandatory},
     {"--newshell"     ,      false,       boolean,                none},
     {"--shell_wrapper",      "",          string,                 optional},
     {"--shell_cmd",          "/bin/sh",   string,                 mandatory},
     {"--shell_args",         ["-i"],      string,                 mandatory},
     {"--shell_prompt_cmd",   "export PS1=SH-PROMPT:",
      string,                 mandatory},
     {"--shell_prompt_regexp","^SH-PROMPT:",
      string,                 mandatory},
     {"--post_cleanup_cmd",   undefined,   string,                 optional},
     {"--file_pattern", ".*\.lux" ++ [$$], string,                 mandatory},
     {"--root_dir",           undefined,   string,                 mandatory},
     {"--var",                undefined,   string,                 mandatory},
     {"--tap",                undefined,   string,                 mandatory},
     {"--junit",              false,       boolean,                none}
    ].

enum(profile) ->
    [standalone, development, embedded];
enum(mode) ->
    [list, list_dir, doc, validate, dump, expand, execute];
enum(prio) ->
    [enable, success, skip, warning, fail, error, disable];
enum(html) ->
    [validate | enum(prio)];
enum(progress) ->
    [silent, summary, brief, doc, compact, verbose, etrace, ctrace];
enum(help) ->
    [usage, info, app_dir].

enum_usage(Enum) ->
    Atoms = enum(Enum),
    Strings = [atom_to_list(A) || A <- Atoms],
    "enum(" ++ string:join(Strings, "|") ++ ")".

enum_value(Enum, Val) when is_list(Val) ->
    enum_value(Enum, list_to_atom(Val));
enum_value(Enum, Val) when is_atom(Val) ->
    Vals = enum(Enum),
    case lists:member(Val, Vals) of
        true  -> Val;
        false -> badarg(Val, Enum)
    end.

add_defaults(Opts) ->
    case lists:keymember(files, 1, Opts) of
        true ->
            Opts;
        false ->
            {Files, Opts2} = translate_opts(Opts),
            do_add_defaults(Files, Opts2)
    end.

do_add_defaults(Files, Opts) ->
    UserRun = proplists:get_value(run, Opts),
    UserLogDir = proplists:get_value(log_dir, Opts),
    UserExtendRun = proplists:get_value(extend_run, Opts),
    case UserExtendRun of
        undefined -> ExtendRun = false;
        ExtendRun -> ok
    end,
    StartTime = lux_utils:timestamp(),
    UniqStr = uniq_str(StartTime),
    UniqRun = "run_" ++ UniqStr,
    Run =
        case UserRun of
            undefined -> UniqRun;
            UserRun   -> UserRun
        end,
    case UserLogDir of
        undefined -> RelLogDir = filename:join(["lux_logs", UniqRun]);
        RelLogDir -> ok
    end,
    AbsLogDir0 = lux_utils:normalize_filename(RelLogDir),
    ParentDir0 = filename:dirname(AbsLogDir0),
    Link0 = filename:join([ParentDir0, "latest_run"]),
    PrevLogDir =
        case file:read_link(Link0) of
            {ok, LinkTo} ->
                %% Reuse old log dir
                LinkTo2 = filename:join([ParentDir0, LinkTo]),
                lux_utils:normalize_filename(LinkTo2);
            {error, _} ->
                undefined
        end,
    AbsLogDir =
        if
            UserLogDir =:= undefined, ExtendRun ->
                if
                    PrevLogDir =:= undefined ->
                        AbsLogDir0;
                    true ->
                        PrevLogDir
                end;
            true ->
                AbsLogDir0
        end,
    LogBase = "lux_summary.log",
    SummaryLog = filename:join([AbsLogDir, LogBase]),
    MoreOpts =
        [
         {start_time, StartTime},
         {run, Run},
         {log_dir, AbsLogDir}
        ],
    Replace = fun({Tag, _Val} = Opt, Acc) ->
                      lists:keystore(Tag, 1, Acc, Opt)
              end,
    Opts2 = lists:foldl(Replace, Opts, MoreOpts),
    Opts3 = [{files, Files}, {prev_log_dir, PrevLogDir} | Opts2],
    case lists:keyfind(mode, 1, Opts) of
        {_, M} when M =:= list     orelse
                    M =:= list_dir orelse
                    M =:= doc      orelse
                    M =:= dump     orelse
                    M =:= expand ->
            {ok, Opts3};
        _M ->
            case opt_ensure_dir(ExtendRun, SummaryLog) of
                ok ->
                    opt_create_latest_link(UserLogDir, AbsLogDir),
                    {ok, Opts3};
                summary_log_exists ->
                    {error,
                     "ERROR: Summary log file already exists: ~s\n",
                     [SummaryLog]};
                {error, FileReason} ->
                    {error,
                     "ERROR: Failed to create log directory: ~s -> ~s\n",
                     [AbsLogDir, file:format_error(FileReason)]}
            end
    end.

uniq_str({_MegaSecs, _Secs, MicroSecs} = Now) ->
    {{Year, Month, Day}, {Hour, Min, Sec}} =
        calendar:now_to_universal_time(Now),
    lists:concat([Year, "_", r2(Month), "_", r2(Day), "_",
                  r2(Hour), "_", r2(Min), "_", r2(Sec), "_",
                  integer_to_list(MicroSecs)]).

r2(Int) when is_integer(Int) ->
    r2(integer_to_list(Int));
r2(String) when is_list(String) ->
    string:right(String, 2, $0).

opt_ensure_dir(ExtendRun, SummaryLog) ->
    case not ExtendRun andalso filelib:is_dir(SummaryLog) of
        true  -> summary_log_exists;
        false -> filelib:ensure_dir(SummaryLog)
    end.

opt_create_latest_link(undefined, AbsLogDir) ->
    ParentDir = filename:dirname(AbsLogDir),
    Link = filename:join([ParentDir, "latest_run"]),
    Base = filename:basename(AbsLogDir),
    _ = file:delete(Link),
    _ = file:make_symlink(Base, Link),
    ok;
opt_create_latest_link(_UserLogDir, _AbsLogDir) ->
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Usage
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

usage(Specs, LuxAppDir, EscriptMod) ->
    do_usage(Specs, LuxAppDir, EscriptMod),
    1.

do_usage(Specs0, LuxAppDir, EscriptMod) ->
    Specs = [{"--make", false, boolean, none}] ++ Specs0,
    io:format("usage: ~p [OPTION]... [FILE]...\n", [EscriptMod]),
    P = fun(Atom) -> [H | T] = atom_to_list(Atom), [string:to_upper(H) | T] end,
    PrettyType = fun(Type) ->
                         case Type of
                             {enum, Enum}    -> enum_usage(Enum);
                             {T, _Min, _Max} -> P(T);
                             T               -> P(T)
                         end
                 end,
    Pretty = fun(Spec) ->
                     case Spec of
                         {Short, Opts} -> % alias
                             Long = lists:flatten([[O, " "] || O <- Opts]),
                             io:format("\t~s short for ~s\n", [Short, Long]);
                         {Name, _Default, Type, mandatory} ->
                             io:format("\t~s ~s\n", [Name, PrettyType(Type)]);
                         {Name, _Default, Type, optional} ->
                             io:format("\t~s [~s]\n", [Name, PrettyType(Type)]);
                         {Name, _Default, _Type, none} ->
                             io:format("\t~s\n", [Name])
                     end
             end,
    [Pretty(S) || S <- Specs, element(1, S) =/= ?FILES],
    info_doc(LuxAppDir).

info_doc(LuxAppDir) ->
    DefaultDir = filename:join([LuxAppDir, "priv", "luxcfg"]),
    io:format("\nThe site default configuration file is located here:"
              "\n\n\t ~s\n",
              [DefaultDir]),
    ExampDir = filename:join([LuxAppDir, "examples"]),
    case filelib:is_dir(ExampDir) of
        true ->
            io:format("\nThe examples are installed here:"
                      "\n\n\t ~s\n",
                      [ExampDir]);
        false ->
            io:format("\nThere are no examples installed.\n", [])
    end,
    io:format("\nRead the full documentation of Lux (version ~p)"
              " in the browser:"
              "\n\n\t~s\n",
              [lux_utils:version(), doc_url(LuxAppDir)]).

doc_url(AppDir) ->
    UsersGuide = filename:join([AppDir, "lux.html"]),
    "file://" ++ filename:absname(UsersGuide).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Markdown
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

gen_markdown(ToFile) ->
    case lux_debug:gen_markdown(ToFile) of
        ok ->
            0;
        {error, FileReason} ->
            io:format("ERROR: ~s: ~s\n",
                      [ToFile, file:format_error(FileReason)]),
            1
    end.

pre_markdown(LuxAppDir, ToFile) ->
    FromFile = ToFile ++ ".src",
    AbsFileName0 = filename:absname(ToFile),
    AbsFileName = lux_utils:normalize_filename(AbsFileName0),
    RelFileName = lux_utils:drop_prefix(LuxAppDir, AbsFileName),
    RelFileDir = filename:dirname(RelFileName),
    {ok, Cwd} = file:get_cwd(),
    RelWorkDir = lux_utils:drop_prefix(LuxAppDir, Cwd),
    case file:read_file(FromFile) of
        {ok, Bin} ->
            try
                Expand =
                    fun(L, {Files, Lines}) ->
                            case markdown_line(RelWorkDir, L) of
                                {keep, Line} ->
                                    {Files, [Line | Lines]};
                                {expand, InclFile, InclLines} ->
                                    RelInclFile =
                                        relpath(RelFileDir, InclFile),
                                    {[RelInclFile | Files],
                                     [InclLines | Lines]};
                                {expand, EvalLines} ->
                                    {Files,
                                     [EvalLines | Lines]}
                            end
                    end,
                Lines = lux_utils:split_lines(Bin),
                {InclFiles, RevNewLines} =
                    lists:foldl(Expand, {[], []}, Lines),
                DepsIoList =
                    [
                     ToFile,
                     ": ",
                     join(" ", [FromFile | lists:reverse(InclFiles)])
                    ],
                DepsFile = ToFile ++ ".d",
                %% Make dependency file
                case file:write_file(DepsFile, DepsIoList) of
                    ok ->
                        ok;
                    {error, FileReason} ->
                        throw({error,
                               "~s: ~s", [DepsFile,
                                          file:format_error(FileReason)]})
                end,
                IoList = lux_utils:expand_lines(lists:reverse(RevNewLines)),
                %% Markdown file
                case file:write_file(ToFile, IoList) of
                    ok ->
                        0;
                    {error, FileReason2} ->
                        throw({error,
                               "~s: ~s", [ToFile,
                                          file:format_error(FileReason2)]})
                end
            catch
                throw:{error, Format, Args} ->
                    io:format("ERROR: ~s: " ++ Format ++ "\n",
                              [FromFile] ++ Args),
                    1
            end;
        {error, FileReason} ->
            io:format("ERROR: ~s: ~s\n",
                      [FromFile, file:format_error(FileReason)]),
            1
    end.

relpath(".", Path) ->
    Path;
relpath(Prefix, Path) ->
    UpDir = filename:join([".." || _ <- filename:split(Prefix)]),
    filename:join([UpDir, Path]).

markdown_line(RelWorkDir, Line) ->
    Incomplete = {error, "Incomplete include statement", []},
    case string:strip(binary_to_list(Line), left) of
        "#include " ++ InclFile ->
            case string:strip(InclFile, both) of
                "<" ->
                    throw(Incomplete);
                "<" ++ InclFile2 ->
                    case lists:reverse(InclFile2) of
                        ">" ++ RevInclFile ->
                            InclFile3 = lists:reverse(RevInclFile),
                            markup_include(InclFile3);
                        _ ->
                            throw(Incomplete)
                    end;
                _ ->
                    throw(Incomplete)
            end;
        "#eval-include " ++ Cmd0 ->
            Cmd = string:strip(Cmd0),
            FullCmd =
                case relpath(RelWorkDir, "") of
                    "" -> Cmd;
                    UpDir  -> "cd " ++ UpDir ++ " && " ++ Cmd
                end,
            io:format("\t~s\n", [FullCmd]),
            {Output, RetCode} = lux_utils:cmd(FullCmd),
            io:format("\techo $?\n\t~s\n", [RetCode]),
            Prompt = ".../lux> ",
            Prefix = ">     ",
            {expand,
             [
              "Evaluate `", Cmd, "`\n\n",
              Prefix, Prompt, Cmd, "\n",
              lux_utils:expand_lines([[Prefix, L] || L <- Output]),
              "\n",
              Prefix, Prompt, "echo $?\n",
              Prefix, RetCode, "\n"
             ]};
        "#eval-silent " ++ Cmd0 ->
            Cmd = string:strip(Cmd0),
            FullCmd =
                case relpath(RelWorkDir, "") of
                    "" -> Cmd;
                    UpDir  -> "cd " ++ UpDir ++ " && " ++ Cmd
                end,
            io:format("\t~s\n", [FullCmd]),
            {_Output, RetCode} = lux_utils:cmd(FullCmd),
            io:format("\techo $?\n\t~s\n", [RetCode]),
            {expand,
             [
              "Evaluate `", Cmd, "`\n"
             ]};
        _ ->
            {keep, Line}
    end.

markup_include(RelFile) ->
    AbsFile = filename:join(["..", RelFile]),
    case file:read_file(AbsFile) of
        {ok, Bin} ->
            Lines = lux_utils:split_lines(binary_to_list(Bin)),
            RelFile2 = filename:join(["...", "lux", RelFile]),
            {expand,
             RelFile,
             [
              "Snippet from the enclosed `", RelFile2, "` file:\n",
              "\n",
              lux_utils:expand_lines([[">     ", L] || L <- Lines])
             ]};
        {error, FileReason} ->
            RelFile2 = filename:join(["..", "lux", RelFile]),
            throw({error, "~s: ~s", [RelFile2, file:format_error(FileReason)]})
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Erlang debug
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

internal_debug(MainOp, Args) ->
    require_app(MainOp, debugger),
    require_app(MainOp, wx),
    ThisEscript = require_escript(),
    {ok, [{shebang, Shebang0} | _Rest]} = escript:extract(ThisEscript, []),
    case Shebang0 of
        default -> Shebang = "/usr/bin/env escript";
        Shebang -> ok
    end,
    FlatArgs = lists:flatten([[" ", A] || A <- Args,
                                          A =/= "-D",
                                          A =/= "--internal_debug"]),
    %% Use "escript -d" to enable debugging of this escript. Break at main/1.
    DebugCmd = Shebang ++ " -d " ++ ThisEscript ++ FlatArgs,
    io:format("~s\n", [DebugCmd]),
    PortOpts = [binary, stream, use_stdio, stderr_to_stdout, eof],
    Port = open_port({spawn, DebugCmd}, PortOpts),
    spawn_link(fun() -> forward_stdin(Port, 1) end),
    forward_stdout(Port).

forward_stdin(Port, N) ->
    case io:get_line("") of
        eof when N =:= 1 ->
            %% Closed already at startup
            exit(normal);
        eof ->
            io:format("\nEOF: stdin closed\n", []),
            exit(normal);
        {error,terminated} ->
            exit(normal);
        Data ->
            %% forward to port
            true = port_command(Port, Data),
            forward_stdin(Port, N+2)
    end.

forward_stdout(Port) ->
    receive
        {Port, {data, Data}} ->
            io:format("~s", [Data]),
            forward_stdout(Port);
        {Port, eof} ->
            port_close(Port),
            0;
        Unexpected ->
            io:format("Got something unexpected from port: ~p\n",
                      [Unexpected]),
            forward_stdout(Port)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Erlang trace
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

suite_trace(MainOp, LuxAppDir, Opts, OpModes, Specs, OrigArgs, EscriptMod) ->
    require_app(MainOp, runtime_tools),
    case add_defaults(Opts) of
        {ok, Opts2} ->
            LogDir = proplists:get_value(log_dir, Opts2),
            TraceFile0 = filename:join([LogDir, "lux_suite"]),
            {ok, TraceFile} =
                lux_trace:start_suite_trace(TraceFile0, [EscriptMod]),
            io:format("WARNING: Internal tracing of suite started,"
                      " see file ~s\n",
                      [TraceFile]),
            Key = "--suite_trace",
            NewOpts = lists:keyreplace(Key, 1, Opts2, {Key, []}),
            Res = dispatch(NewOpts, LuxAppDir, OpModes, Specs,
                           OrigArgs, EscriptMod),
            lux_trace:stop_trace(),
            Res;
        {error, Format, Args} ->
            io:format(Format, Args),
            1
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Display trace
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

display_trace(MainOp, LuxAppDir, TraceFile, Opts) ->
    require_app(MainOp, runtime_tools),
    FilterFile = filter_trace_file(LuxAppDir, Opts),
    lux_trace:display(TraceFile, FilterFile).

filter_trace_file(LuxAppDir, Opts) ->
    case lists:keyfind("--filter_trace", 1, Opts) of
        {_, []} ->
            filename:join([LuxAppDir, "priv", "filter_trace"]);
        {_, FilterFile} ->
            lists:last(FilterFile)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Event trace
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

event_trace(MainOp, LuxAppDir, Opts, OpModes, Specs,
            OrigArgs, EscriptMod) ->
    require_app(MainOp, runtime_tools),
    require_app(MainOp, et),
    require_app(MainOp, wx),
    EtOpts =
        [
         {title,"LUX"},
         {trace_global,true},
         {trace_pattern,{lux,max}},
         {hide_unknown, true},
         {max_actors,10}
        ],
    case et_viewer:start(EtOpts) of
        {ok, ViewerPid} ->
            ViewerRef = erlang:monitor(process, ViewerPid),
            Key = "--event_trace",
            NewOpts = lists:keyreplace(Key, 1, Opts, {Key, []}),
            dispatch(NewOpts, LuxAppDir, OpModes, Specs,
                     OrigArgs, EscriptMod),
            receive
                {'DOWN', ViewerRef, _Type, _Object, shutdown} ->
                    ok;
                {'DOWN', ViewerRef, _Type, _Object, Reason} ->
                    io:format("Event tracer exit: ~p\n", [Reason])
            end,
            0;
        {error, Reason} ->
            io:format("Event tracer error: ~p\n", [Reason]),
            1
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Stand-alone installation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

install(MainOp, LuxAppDir, InstallDir, Opts) ->
    InstallProf = reltool_profile(Opts),
    io:format("Installing ~p as a ~p system... ~s\n",
              [?APPLICATION, InstallProf, InstallDir]),
    {RootDir, ReltoolOpts} = reltool_opts(MainOp, LuxAppDir, Opts),
    case reltool:start_server(ReltoolOpts) of
        {ok, ServerPid} ->
            case reltool:get_status(ServerPid) of
                {ok, Warnings} ->
                    [io:format("WARNING: ~s\n", [W]) || W <- Warnings],
                    do_install(ServerPid, InstallDir, RootDir);
                {error, StatusReasonStr} ->
                    io:format("ERROR: ~s\n", [StatusReasonStr]),
                    1
            end;
        {error, StartReasonStr} ->
            io:format("ERROR: ~s\n", [StartReasonStr]),
            1
    end.

do_install(ServerPid, InstallDir, RootDir) ->
    GetSpecRes = reltool:get_target_spec(ServerPid),
    _StopRes = reltool:stop(ServerPid),
    case GetSpecRes of
        {ok, Spec} ->
            case InstallDir of
                "" ->
                    io:format("Spec: ~p.\n", [Spec]),
                    timer:sleep(timer:seconds(1)),
                    0;
                _ ->
                    case reltool:eval_target_spec(Spec,
                                                  RootDir,
                                                  InstallDir) of
                        ok ->
                            0;
                        {error, EvalReasonStr} ->
                            io:format("ERROR: ~s\n", [EvalReasonStr]),
                            1
                    end
            end;
        {error, SpecReasonStr} ->
            io:format("ERROR: ~s\n", [SpecReasonStr]),
            1
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Reltool
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

reltool(MainOp, LuxAppDir, Opts) ->
    io:format("Starting reltool...\n", []),
    process_flag(trap_exit, true),
    {_RootDir, ReltoolOpts} = reltool_opts(MainOp, LuxAppDir, Opts),
    case reltool:start(ReltoolOpts) of
        {ok, Pid} ->
            link(Pid),
            receive
                {'EXIT', Pid, Reason} ->
                    io:format("reltool exit: ~p\n", [Reason])
            end,
            0;
        {error, ReasonStr} ->
            io:format("ERROR: ~s\n", [ReasonStr]),
            1
    end.

reltool_opts(MainOp, LuxAppDir, Opts) ->
    require_app(MainOp, reltool),
    {IsCross, RootDir} = root_dir(Opts),
    ThisEscript = escript:script_name(),
    %% Include some extra files beside the default files
    AppFilters =
        [{incl_app_filters, ["^LICENSE", "^lux.html",
                             "ebin", "^priv", "^examples.*", "^emacs.*"]},
         {excl_archive_filters, ["^LICENSE", "^lux.html",
                                 "^priv", "^examples.*", "^emacs.*"]},
         {excl_app_filters, [".*empty$"]}],
    HasAppLibDir = app_has_feature(MainOp, reltool, "0.6", mandatory),
    LuxApps =
        case HasAppLibDir of
            true ->
                %% New reltool can handle lib_dir in app
                [{app, ?APPLICATION, [{lib_dir, LuxAppDir} | AppFilters]}];
            false ->
                %% Old reltool
                [{app, ?APPLICATION, AppFilters},
                 {lib_dirs, [filename:dirname(LuxAppDir)]}]
        end,
    HasRelaxedExclusion = app_has_feature(MainOp, reltool, "0.6.4", mandatory),
    {AppCondsWx, AppCondsCross} =
        case {IsCross, HasRelaxedExclusion} of
            {true, false} ->
                {[],
                 []};
            _ ->
                %% New reltool can handle excluded non-existent apps
                {[{wx, exclude}],
                 [{hipe, exclude}, {reltool, exclude}]}
        end,
    AppCondsCommon = [{erts, include}, {crypto, exclude}, {tools, exclude}],
    AppConds = AppCondsCommon ++ AppCondsCross ++ AppCondsWx,
    {_, InstallApps} = lists:keyfind("--install_app", 1, Opts),
    InstallApps2 = [{list_to_atom(A), include} || A <- InstallApps],
    AppConds2 = [{A, C} || {A, C} <- AppConds,
                           not lists:keymember(A, 1, InstallApps2)],
    AppConds3 = AppConds2 ++ InstallApps2,
    ExtraApps = filter_apps(MainOp, AppConds3, IsCross, HasRelaxedExclusion),
    Common =
        [{root_dir, RootDir},
         {debug_info, strip},
         {escript, ThisEscript, [{incl_cond, include}]}],
    Profile =
        case reltool_profile(Opts) of
            standalone ->
                [{profile, standalone},
                 {excl_sys_filters,
                  {add,
                   ["^bin/(epmd|start.boot)(|\\.exe)" ++ [$$],
                    "^erts.*/bin/(epmd|heart|ct_run)(|\\.exe)"  ++ [$$]]}}];
            InstallProf ->
                [{profile, InstallProf}]
        end,
    {RootDir, [{sys, Common ++ LuxApps ++ ExtraApps ++ Profile}]}.

reltool_profile(Opts) ->
    case lists:keyfind("--install_profile", 1, Opts) of
        {_, []}      -> standalone;
        {_, Profile} -> lists:last(Profile)
    end.

app_has_feature(MainOp, AppName, LowestVersion, Require) ->
    LoadedApps = application:loaded_applications(),
    case lists:keyfind(AppName, 1, LoadedApps) of
        {_Name, _Slogan, Version} when Version >= LowestVersion ->
            true;
        {_Name, _Slogan, _Version} ->
            false;
        false when Require =:= optional ->
            false;
        false when Require =:= mandatory ->
            require_app(MainOp, AppName), % Halt upon failure
            app_has_feature(MainOp, AppName, LowestVersion, Require)
    end.

filter_apps(_MainOp, AppConds, _IsCross, true) ->
    [{app, AppName, [{incl_cond,InclCond}]} || {AppName,InclCond} <- AppConds];
filter_apps(MainOp, AppConds, _IsCross, false) ->
    lists:zf(fun({AppName, InclCond}) ->
                     case application:load(AppName) of
                         ok ->
                             {true, {app, AppName, [{incl_cond, InclCond}]}};
                         {error, {already_loaded,AppName}}->
                             {true, {app, AppName, [{incl_cond, InclCond}]}};
                         {error, _} when InclCond =:= include ->
                             missing_app(MainOp, AppName);
                         {error, _} ->
                             false
                     end
             end,
             AppConds).

root_dir(Opts) ->
    case lists:keyfind("--root_dir", 1, Opts) of
        {_, []}        -> {false, code:root_dir()};
        {_, [RootDir]} -> {true, RootDir}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Xref
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

xref(MainOp, LuxAppDir, Opts, EscriptMod) ->
    process_flag(trap_exit, true),
    require_app(MainOp, tools),
    {_RootDir, ReltoolOpts} = reltool_opts(MainOp, LuxAppDir, Opts),
    case reltool:start_server(ReltoolOpts) of
        {ok, ServerPid} ->
            case reltool:get_status(ServerPid) of
                {ok, _Warnings} ->
                    %% [io:format("WARNING: ~s\n", [W]) || W <- Warnings],
                    {ok, {sys, Sys}} =
                        reltool:get_config(ServerPid, true, true),
                    _StopRes = reltool:stop(ServerPid),
                    try
                        do_xref(Sys, EscriptMod)
                    catch
                        _Class:Reason ->
                            io:format("XREF LUX ERROR: ~p\n", [Reason]),
                            1
                    end;
                {error, StatusReasonStr} ->
                    io:format("XREF LUX ERROR: ~s\n", [StatusReasonStr]),
                    1
            end;
        {error, StartReasonStr} ->
            io:format("XREF LUX ERROR: ~s\n", [StartReasonStr]),
            1
    end.

do_xref(Sys, EscriptMod) ->
    {_, ErtsApps} = lists:keyfind(erts, 1, Sys),
    ExtendedSys = Sys ++ ErtsApps,
    AppEbins =  [{A, filename:join([D, "ebin"])} ||
                    {app, A, O}  <- ExtendedSys,
                    {lib_dir, D} <- O],
    Fun = fun(A, M) ->
                  {_, Ebin} = lists:keyfind(A, 1, AppEbins),
                  {A, M, filename:join([Ebin, atom_to_list(M) ++ ".beam"])}
          end,
    ModFiles =  [Fun(A, M) || {app, A, O} <- ExtendedSys,
                              {mod, M, _} <- O],
    Xref = EscriptMod,
    {ok, _} = xref:start(Xref),
    %% ok = xref:set_library_path(Xref, LibDirs),
    Defaults = [{warnings,false}, {verbose,false}, {builtins,true}],
    ok = xref:set_default(Xref, Defaults),
    {ok, Cwd} = file:get_cwd(),
    Add = fun({_App, _Mod, AbsFile}, Acc) ->
                  RelFile = lux_utils:drop_prefix(Cwd, AbsFile),
                  case xref:add_module(Xref, RelFile) of
                      {ok, _} ->
                          Acc;
                      {error, Callback, Error} ->
                          Chars = lists:flatten(Callback:format_error(Error)),
                          Reason = [C || C <- Chars, C =/= $" ],
                          io:format("ERROR: ~s", [Reason]),
                          1
                  end
          end,
    ExitCode = 0,
    {ExitCode2, EscriptModFile} =
        xref_add_escript(Sys, Add, ExitCode, EscriptMod),
    ExitCode3 = lists:foldl(Add, ExitCode2, ModFiles),
    ModFiles2 = [EscriptModFile | ModFiles],
    ExitCode4 = undefined_function_calls(Xref, ModFiles2,
                                         ExitCode3, EscriptMod),
    xref:stop(Xref),
    ExitCode4.

xref_add_escript(Sys, Add, ExitCode, EscriptMod) ->
    {_, EscriptFile, _} = lists:keyfind(escript, 1, Sys),
    {ok, Sections} = escript:extract(EscriptFile, [compile_source]),
    {_, EscriptBeam} = lists:keyfind(source, 1, Sections),
    TmpEscriptFile = atom_to_list(EscriptMod) ++ ".beam",
    EscriptModFile = {?APPLICATION, EscriptMod, TmpEscriptFile},
    case file:write_file(TmpEscriptFile, EscriptBeam) of
        ok ->
            Res = Add(EscriptModFile, ExitCode),
            file:delete(TmpEscriptFile),
            {Res, EscriptModFile};
        {error, FileReason} ->
            io:format("ERROR: ~s ~s\n",
                      [TmpEscriptFile, file:format_error(FileReason)]),
            {1, EscriptModFile}
    end.

undefined_function_calls(Xref, ModFiles, ExitCode, EscriptMod) ->
    {ok, MFAs} = xref:analyze(Xref, undefined_function_calls),
    Fun =
        fun({FromMFA, ToMFA}, Acc) ->
                case ignore_call(FromMFA, ToMFA, ModFiles, EscriptMod) of
                    true ->
                        Acc;
                    false ->
                        io:format("ERROR: ~s calls undefined function ~s\n",
                                  [mfa(FromMFA), mfa(ToMFA)]),
                        1
                end
        end,
    lists:foldl(Fun, ExitCode, MFAs).

ignore_call(FromMFA, ToMFA, ModFiles, EscriptMod) ->
    FromMod = element(1, FromMFA),
     FromApp = which_app(FromMod, ModFiles, EscriptMod),
    if
        FromMod =:= EscriptMod ->
            ToMod = element(1, ToMFA),
            lists:member(ToMod, [make]);
        FromMod =:= ?MODULE ->
            ToMod = element(1, ToMFA),
            lists:member(ToMod, [reltool, xref]);
        FromApp =:= ?APPLICATION ->
            false;
        true ->
            true
    end.

which_app(Mod, ModFiles, EscriptMod) ->
    {Mod, {App, _, _}, _, _} =
        {Mod, lists:keyfind(Mod, 2, ModFiles), EscriptMod, ?LINE},
    App.

mfa({M, F, A}) ->
  io_lib:format("~s:~s/~p", [M, F, A]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% HTML
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

annotate(LogFile0, Opts) ->
    {_Files, Opts2} = translate_opts(Opts),
    LogFile = filename:absname(LogFile0),
    io:format("Annotating logs ~s...", [LogFile]),
    case lux_suite:annotate_log(true, LogFile, Opts2) of
        ok ->
            io:format("...ok\n", []),
            io:format("\nfile://~s\n", [LogFile ++ ".html"]),
            0;
        {error, File, ReasonStr} ->
            io:format("...ERROR\n\t~p: ~s\n", [File, ReasonStr]),
            1
    end.

history(RelLogDir, Opts) ->
    {Files0, Opts2} = translate_opts(Opts),
    case Files0 of
        []    -> Files = [RelLogDir];
        Files -> ok
    end,
    case safe_history(Files, RelLogDir, Opts2) of
        {ok, RelHtmlFile} ->
            io:format("...ok\n", []),
            AbsHtmlFile = filename:absname(RelHtmlFile),
            io:format("\nfile://~s\n", [AbsHtmlFile]),
            0;
        {error, File, ReasonStr} ->
            io:format("...ERROR\n\t~s: ~s\n", [File, ReasonStr]),
            1
    end.

safe_history(LogDirs, RelLogDir, Opts) ->
    case lux_html_history:generate(LogDirs, RelLogDir, Opts) of
        {ok, BinRelHtmlFile} ->
            RelHtmlFile = binary_to_list(BinRelHtmlFile),
            case lux_html_parse:validate_html(RelHtmlFile, Opts) of
                ok ->
                    {ok, RelHtmlFile};
                {error, File, Reason} ->
                    {error, File, Reason}
            end;
        {error, File, Reason} ->
            {error, File, Reason}
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Run tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

run(Opts, Files, PrevLogDir, OrigArgs, ThisEscript) ->
    case do_run(Files, Opts, PrevLogDir, OrigArgs, ThisEscript) of
        ok -> % HTML
            Summary = success,
            ok;
        {ok, Summary, _SummaryLog, _Results} -> % LUX
            ok;
        {error, undefined, no_input_files} ->
            Summary = error;
        {error, File, ReasonBin} ->
            io:format("\n\nFATAL ERROR: ~s:\n\t~s\n", [File, ReasonBin]),
            Summary = error
    end,
    exit_code(Summary).

do_run(Files, Opts, PrevLogDir, OrigArgs, ThisEscript) ->
    case is_html(Files) of
        true ->
            lux_html_parse:validate_html(hd(Files), Opts);
        false ->
            ThisEscript = escript:script_name(),
            lux_suite:run(Files, Opts, PrevLogDir, [ThisEscript | OrigArgs])
    end.

is_html(Files) ->
    lists:any(fun(F) -> lists:suffix(".html", F) end, Files).

exit_code(Summary) ->
    case Summary of
        success -> 0;
        skip    -> 0;
        warning -> 0;
        fail    -> 1;
        error   -> 1
    end.

translate_opts([
     {?FILES,                 Files},
     {"--help",               _Help},
     {"--version",            _Version},
     {"--gen_markdown",       _GenMarkdown},
     {"--pre_markdown",       _PreMarkdown},
     {"--internal_debug",     _InternalDebug},
     {"--event_trace",        _EventTrace},
     {"--suite_trace",        _SuiteTrace},
     {"--display_trace",      _DisplayTrace},
     {"--filter_trace",       _FilterTrace},
     {"--install",            _InstallDir},
     {"--install_app",        _InstallApp},
     {"--install_profile",    _InstallProfile},
     {"--reltool",            _Reltool},
     {"--xref",               _Xref},
     {"--annotate",           _LogFile},
     {"--history",            _LogDir},
     {"--rerun",              ReRun},
     {"--html",               Html},
     {"--debug",              Debug},
     {"--debug_file",         DebugFile},
     {"--skip",               Skip},
     {"--skip_unless",        SkipUnless},
     {"--skip_unstable",      SkipUnstable},
     {"--skip_skip",          SkipSkip},
     {"--require",            Require},
     {"--case_prefix",        CasePrefix},
     {"--log_dir",            LogDir},
     {"--config_dir",         ConfigDir},
     {"--config_name",        ConfigName},
     {"--suite",              Suite},
     {"--run",                Run},
     {"--extend_run",         ExtendRun},
     {"--revision",           Revision},
     {"--hostname",           Hostname},
     {"--mode",               Mode},
     {"--doc",                Doc},
     {"--progress",           Progress},
     {"--multiplier",         Multiplier},
     {"--suite_timeout",      SuiteTimeout},
     {"--case_timeout",       CaseTimeout},
     {"--flush_timeout",      FlushTimeout},
     {"--poll_timeout",       PollTimeout},
     {"--timeout",            ExpectTimeout},
     {"--cleanup_timeout",    CleanupTimeout},
     {"--newshell",           NewShell},
     {"--shell_wrapper",      ShellWrapper},
     {"--shell_cmd",          ShellCmd},
     {"--shell_args",         ShellArgs},
     {"--shell_prompt_cmd",   ShellPromptCmd},
     {"--shell_prompt_regexp",ShellPromptRegexp},
     {"--post_cleanup_cmd",   PostCleanupCmd},
     {"--file_pattern",       FilePattern},
     {"--root_dir",           _RootDir},
     {"--var",                Var},
     {"--tap",                Tap},
     {"--junit",              Junit}
    ]) ->
    Mode2 =
        if
            Doc =/= [] -> [doc];
            true       -> Mode
        end,
    Opts =
        [
         {debug,              Debug},
         {debug_file,         DebugFile},
         {progress,           Progress},
         {rerun,              ReRun},
         {html,               Html},
         {case_timeout,       CaseTimeout},
         {flush_timeout,      FlushTimeout},
         {poll_timeout,       PollTimeout},
         {timeout,            ExpectTimeout},
         {cleanup_timeout,    CleanupTimeout},
         {newshell,           NewShell},
         {shell_wrapper,      ShellWrapper},
         {shell_cmd,          ShellCmd},
         {shell_args,         ShellArgs},
         {shell_prompt_cmd,   ShellPromptCmd},
         {shell_prompt_regexp,ShellPromptRegexp},
         {post_cleanup_cmd,   PostCleanupCmd},
         {multiplier,         Multiplier},
         {suite_timeout,      SuiteTimeout},
         {log_dir,            LogDir},
         {skip,               Skip},
         {skip_unless,        SkipUnless},
         {skip_unstable,      SkipUnstable},
         {skip_skip,          SkipSkip},
         {require,            Require},
         {case_prefix,        CasePrefix},
         {var,                Var},
         {mode,               Mode2},
         {doc,                Doc},
         {config_dir,         ConfigDir},
         {config_name,        ConfigName},
         {suite,              Suite},
         {run,                Run},
         {extend_run,         ExtendRun},
         {revision,           Revision},
         {hostname,           Hostname},
         {file_pattern,       FilePattern},
         {tap,                Tap},
         {junit,              Junit}
        ],
    {Files, lux_suite:args_to_opts(Opts, suite_style, [])}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Generic option handling
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-type opt()      :: string() .
-type name()     :: string().
-type default()  :: term().
-type type()     :: string | binary |
                    atom | existing_atom |
                    integer | {integer, min(), max()} |
                    float | {float, min(), max()} |
                    boolean | validate().
-type min()      :: integer().
-type max()      :: integer() | infinity.
-type validate() :: fun((opt() | default()) -> val()).
-type presence() :: none | optional | mandatory.
-type spec()     :: {name(), [opt()]} | % alias
                    {name(), default(), type(), presence()}.
-type val()      :: term().
-spec getopts([opt()], [spec()], string(), string()) -> [[val()]].

%% Parse options and validate their values.
%% All options in the specs are returned and they keep that order.
getopts(Args, Specs, LuxAppDir, ThisEscript) ->
    EscriptMod = escript_mod(ThisEscript),
    try
        Opts = do_getopts(Args, Specs, []),
        expand_opts(Opts, Specs)
    catch
        throw:{badarg, Bad} ->
            io:format("~s: ~p is an illegal argument.\n\n",
                      [EscriptMod, Bad]),
            ExitCode = usage(Specs, LuxAppDir, EscriptMod),
            safe_halt(ExitCode);
        throw:{badarg, Bad, Type} ->
            io:format("~s: ~p is an illegal argument. ~p expected.\n\n",
                      [EscriptMod, Bad, Type]),
            ExitCode = usage(Specs, LuxAppDir, EscriptMod),
            safe_halt(ExitCode);
        throw:{badarg, Name, Bad, Type} ->
            io:format("~s: ~p is an illegal value of argument ~s."
                      " ~p expected.\n\n",
                      [EscriptMod, Bad, Name, Type]),
            ExitCode = usage(Specs, LuxAppDir, EscriptMod),
            safe_halt(ExitCode)
    end.

do_getopts([], _Specs, Acc) ->
    lists:reverse(Acc);
do_getopts(Args, Specs, Acc) ->
    {MoreArgs, Name, Val, Type, Presence} = getopt(Args, Specs),
    Val2 = validate(Name, Val, Type, Presence),
    do_getopts(MoreArgs, Specs, [{Name, Val2} | Acc]).

getopt([?FILES | Args], _Specs) ->
    {[], ?FILES, Args, string, optional};
getopt([Arg | Args], Specs) when hd(Arg) =:= $- ->
    {Val, Spec} = find_spec(Arg, Specs),
    case Spec of
        {_Short, Long} ->
            getopt(Long ++ Args, Specs);
        {Name, Default, Type, Presence} ->
            case {Presence, Val, Args} of
                {none, undefined, _} when Type =:= boolean ->
                    %% boolean - no value, return opposite of default
                    {Args, Name, not Default, Type, Presence};
                {none, "true", _} when Type =:= boolean ->
                    %% boolean - got name=true
                    {Args, Name, true, Type, Presence};
                {none, "false", _} when Type =:= boolean ->
                    %% boolean - got name=false
                    {Args, Name, false, Type, Presence};
                {none, _, _} ->
                    %% boolean - got -name=val
                    badarg(Arg, Type);
                {mandatory, undefined, []} ->
                    %% val required - no more options
                    badarg(Arg, Type);
                {mandatory, undefined, ["-" ++ _NextArg | _NextArgs]} ->
                    %% val required - next option is not a val
                    badarg(Arg, Type);
                {mandatory, undefined, [NextVal | NextArgs]} ->
                    %% val required - return separate val
                    {NextArgs, Name, NextVal, Type, Presence};
                {mandatory, _, _} ->
                    %% val required - got name=val
                    {Args, Name, Val, Type, Presence};
                {optional, undefined, []} ->
                    %% optional val - return default val
                    {Args, Name, Default, Type, Presence};
                {optional, undefined, ["-" ++ _NextArg | _NextArgs]} ->
                    %% optional val - return default val
                    {Args, Name, Default, Type, Presence};
                {optional, undefined, [NextVal | NextArgs]} ->
                    %% optional val - got name=val
                    {NextArgs, Name, NextVal, Type, Presence};
                {optional, _, _} ->
                    %% optional val - return default val
                    {Args, Name, Val, Type, Presence}
            end
    end;
getopt(Args, _Specs) ->
    {[], ?FILES, Args, string, optional}.

expand_opts(Opts, Specs) ->
    Fun = fun({_Short, _Long}, Acc) -> % alias
                  Acc;
             ({Name, _Default, _Type, _Presence}, Acc) ->
                  Vals = proplists:get_all_values(Name, Opts),
                  Vals2 =
                      if
                          Name =:= ?FILES ->
                              lists:append(Vals);
                          true ->
                              Vals
                      end,
                     [{Name, Vals2} | Acc]
          end,
    lists:reverse(lists:foldl(Fun, [], Specs)).

validate(Name, Val, Type, Presence) ->
    try
        case Type of
            string when is_list(Val) ->
                Val;
            binary ->
                list_to_binary(Val);
            atom ->
                list_to_atom(Val);
            existing_atom ->
                list_to_existing_atom(Val);
            integer ->
                list_to_integer(Val);
            {integer, _Min, infinity} when Val =:= "infinity" ->
                infinity;
            {integer, Min, infinity} when Val >= Min ->
                list_to_integer(Val);
            {integer, Min, Max} when Val >= Min, Val =< Max ->
                list_to_integer(Val);
            float ->
                list_to_float(Val);
            {float, _Min, infinity} when Val =:= "infinity" ->
                infinity;
            {float, Min, infinity} when Val >= Min ->
                list_to_float(Val);
            {float, Min, Max} when Val >= Min, Val =< Max ->
                list_to_float(Val);
            boolean when Val =:= true; Val =:= "true" ->
                true;
            boolean when Val =:= false; Val =:= "false" ->
                false;
            {enum, Enum} ->
                enum_value(Enum, Val);
            _ when Val =:= undefined, Presence =/= mandatory ->
                Val
        end
    catch
        _Class:_Reason ->
            badarg(Name, Val, Type)
    end.

find_spec(Opt, Specs) ->
    {Name, Val} =
        case lists:prefix("--", Opt) of
            true ->
                %% --name=val
                Eq = $=,
                case lists:splitwith(fun(Char) -> Char =/= Eq end, Opt) of
                    {N, [Eq | V]} -> {N, V};
                    {N, []}       -> {N, undefined}
                end;
            false ->
                {Opt, undefined}
        end,
    %% io:format("Option ~p: ~p -> ~p\n~p\n", [Opt, Name, Val, Specs]),
    case lists:keyfind(Name, 1, Specs) of
        false -> badarg(Opt);
        Spec  -> {Val, Spec}
    end.

badarg(Val) ->
    do_throw({badarg, Val}).

badarg(Val, {enum, Enum}) ->
    do_throw({badarg, Val, enum_usage(Enum)});
badarg(Val, Type) ->
    do_throw({badarg, Val, Type}).

badarg(Name, Val, {enum, Enum}) ->
    do_throw({badarg, Name, Val, enum_usage(Enum)});
badarg(Name, Val, Type) ->
    do_throw({badarg, Name, Val, Type}).

do_throw(Reason) ->
    throw(Reason).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Generic application handling
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

require_escript() ->
    escript:script_name().

escript_mod(ThisEscript) ->
    list_to_atom(filename:basename(ThisEscript) ++ "_escript").

fatal_error(RetCode, Format, Args) ->
    throw({fatal_error, RetCode, Format, Args}).

safe_halt(RetCode) ->
    throw({safe_halt, RetCode}).

join(_Sep, []) ->
    [];
join(Sep, [H|T]) ->
 [H | join2(Sep, T)].

join2(_Sep, []) ->
    [];
join2(Sep, [H | T]) ->
    [Sep , H | join2(Sep, T)].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Original code. There is a copy in bin/lux as well
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

require_app(MainOp, AppName) ->
    case code:lib_dir(AppName) of
        {error, _Reason} ->
            missing_app(MainOp, AppName);
        AppDir ->
            case application:load(AppName) of
                ok ->
                    AppDir;
                {error, {already_loaded,AppName}}->
                    AppDir;
                {error, _} ->
                    missing_app(MainOp, AppName)
            end
    end.

missing_app(undefined, AppName) ->
    fatal_error(4, "The application '~p' is missing.\n", [AppName]);
missing_app(MainOp, AppName) ->
    fatal_error(4,
                "The application '~p' is required for the ~p option.\n",
                [AppName, MainOp]).
