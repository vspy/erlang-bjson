%% @doc Library for bjson serialization, totally compatible with
%%      mochijson2. See http://bjson.org/for more details
%%
%%      Short syntax cheatsheet:
%%      {"key": "value"} -> {struct, [<<"key">>, <<"value">>]}
%%
%%      ["array", 123, 12.34, true, false, null] ->
%%        [<<"array">>, 123, 12.34, true, false, null]
%%
%%      "mystring" -> <<"mystring">> or mystring (symbols could be used when encoding)
%%      1 -> 1, 42.0 -> 42.0
%%      true -> true, false -> false
%%      null -> null
%%      
-module(bjson).
-vsn("1.0.0").

-export([encode/1, decode/1]).

-define(MAX8BITS, 256).
-define(MAX16BITS, ?MAX8BITS*?MAX8BITS).
-define(MAX32BITS, ?MAX16BITS*?MAX16BITS).
-define(MAX64BITS, ?MAX32BITS*?MAX32BITS).

encode(Doc) -> bjson_encode(Doc).
decode(Doc) -> 
  {Result, Rest} = bjson_decode(Doc),
  if 
    Rest /= <<>> -> throw({extra_input, Rest});
    true -> Result
  end.

bjson_decode(<<0:8, Rest/binary>>) -> {null, Rest};
bjson_decode(<<1:8, Rest/binary>>) -> {false, Rest};
bjson_decode(<<2:8, Rest/binary>>) -> {<<>>, Rest};
bjson_decode(<<3:8, Rest/binary>>) -> {true, Rest};

bjson_decode(<<4:8, Num:8, Rest/binary>>) -> {Num, Rest};
bjson_decode(<<5:8, Num:16, Rest/binary>>) -> {Num, Rest};
bjson_decode(<<6:8, Num:32, Rest/binary>>) -> {Num, Rest};
bjson_decode(<<7:8, Num:64, Rest/binary>>) -> {Num, Rest};

bjson_decode(<<7:8, Num:8, Rest/binary>>) -> {-Num, Rest};
bjson_decode(<<8:8, Num:16, Rest/binary>>) -> {-Num, Rest};
bjson_decode(<<10:8, Num:32, Rest/binary>>) -> {-Num, Rest};
bjson_decode(<<11:8, Num:64, Rest/binary>>) -> {-Num, Rest};

bjson_decode(<<12:8, Float:32/float, Rest/binary>>) -> {Float, Rest};
bjson_decode(<<13:8, Double:64/float, Rest/binary>>) -> {Double, Rest};

bjson_decode(<<16:8, Size:8, StringAndRest/binary>>) -> bjson_decode_str(Size,StringAndRest);
bjson_decode(<<17:8, Size:16, StringAndRest/binary>>) -> bjson_decode_str(Size,StringAndRest);
bjson_decode(<<18:8, Size:32, StringAndRest/binary>>) -> bjson_decode_str(Size,StringAndRest);
bjson_decode(<<19:8, Size:64, StringAndRest/binary>>) -> bjson_decode_str(Size,StringAndRest);

bjson_decode(<<32:8, Size:8, ArrayAndRest/binary>>) -> bjson_decode_array(Size, ArrayAndRest);
bjson_decode(<<33:8, Size:16, ArrayAndRest/binary>>) -> bjson_decode_array(Size, ArrayAndRest);
bjson_decode(<<34:8, Size:32, ArrayAndRest/binary>>) -> bjson_decode_array(Size, ArrayAndRest);
bjson_decode(<<35:8, Size:64, ArrayAndRest/binary>>) -> bjson_decode_array(Size, ArrayAndRest);

bjson_decode(<<36:8, Size:8, MapAndRest/binary>>) -> bjson_decode_map(Size, MapAndRest);
bjson_decode(<<37:8, Size:16, MapAndRest/binary>>) -> bjson_decode_map(Size, MapAndRest);
bjson_decode(<<38:8, Size:32, MapAndRest/binary>>) -> bjson_decode_map(Size, MapAndRest);
bjson_decode(<<39:8, Size:64, MapAndRest/binary>>) -> bjson_decode_map(Size, MapAndRest).

bjson_decode_str(Size, StringAndRest) ->
  String = binary:part(StringAndRest, 0, Size),
  Rest = binary:part(StringAndRest, Size, byte_size(StringAndRest)-Size),
  {String, Rest}.

bjson_decode_array(Size, ArrayAndRest) ->
  Array = binary:part(ArrayAndRest, 0, Size),
  Rest = binary:part(ArrayAndRest, Size, byte_size(ArrayAndRest)-Size),
  Value = decode_array_content(Array,[]),
  {Value, Rest}.
decode_array_content(<<>>,Result) -> lists:reverse(Result);
decode_array_content(Binary, Result) -> 
  {Value, Rest} = bjson_decode(Binary),
  decode_array_content(Rest, [Value|Result]).

bjson_decode_map(Size, MapAndRest) ->
  Map = binary:part(MapAndRest, 0, Size),
  Rest = binary:part(MapAndRest, Size, byte_size(MapAndRest)-Size),
  Value = decode_map_content(Map,[]),
  {{struct, Value}, Rest}.
decode_map_content(<<>>,Result) -> lists:reverse(Result);
decode_map_content(Binary, Result) -> 
  {Value, Rest} = bjson_decode_pair(Binary),
  decode_map_content(Rest, [Value|Result]).

bjson_decode_pair(Binary) ->
  {Key, ValueAndRest} = bjson_decode(Binary),
  {Value, Rest} = bjson_decode(ValueAndRest),
  {{Key,Value}, Rest}.

bjson_encode(null) -> <<0:8>>;
bjson_encode(false) -> <<1:8>>;
bjson_encode(<<>>) -> <<2:8>>;
bjson_encode(true) -> <<3:8>>;
bjson_encode(Atom) when is_atom(Atom) -> 
  bjson_encode(erlang:atom_to_binary(Atom, utf8));
bjson_encode(Num) when is_integer(Num) and (Num>=0) ->
  if 
      Num<?MAX8BITS -> <<4:8, Num:8>>;
      Num<?MAX16BITS -> <<5:8, Num:16>>;
      Num<?MAX32BITS -> <<6:8, Num:32>>;
      Num<?MAX64BITS -> <<7:8, Num:64>>;
      true -> throw(too_long)
  end;

bjson_encode(NegNum) when (is_integer(NegNum) and (NegNum<0)) ->
  Num = -NegNum,
  if 
      Num<?MAX8BITS -> <<8:8, Num:8>>;
      Num<?MAX16BITS -> <<9:8, Num:16>>;
      Num<?MAX32BITS -> <<10:8, Num:32>>;
      Num<?MAX64BITS -> <<11:8, Num:64>>;
      true -> throw(too_long)
  end;

%% 12 is 32-bit float, but there is no such type in erlang
bjson_encode(Num) when is_float(Num) -> 
  <<13, Num/float>>;

bjson_encode(String) when is_binary(String) ->
  Size = byte_size(String),
  if 
      Size<?MAX8BITS -> <<16:8, Size:8, String/binary>>;
      Size<?MAX16BITS -> <<17:8, Size:16, String/binary>>;
      Size<?MAX32BITS -> <<18:8, Size:32, String/binary>>;
      Size<?MAX64BITS -> <<19:8, Size:64, String/binary>>;
      true -> throw(too_long)
  end;

% 20-23 is unused in this implementation, as we don't
% really recognize binary and strings as something different

bjson_encode(Array) when is_list(Array) ->
  Serialized = lists:map(fun(E)-> bjson_encode(E) end, Array),
  Size = iolist_size(Serialized),
  if 
      Size<?MAX8BITS -> [<<32:8, Size:8>>, Serialized];
      Size<?MAX16BITS -> [<<33:8, Size:16>>, Serialized];
      Size<?MAX32BITS -> [<<34:8, Size:32>>, Serialized];
      Size<?MAX64BITS -> [<<35:8, Size:64>>, Serialized];
      true -> throw(too_long)
  end;

bjson_encode({struct, Values}) when is_list(Values) ->
  Serialized = lists:map(fun(P)-> pair_encode(P) end, Values),
  Size = iolist_size(Serialized),
  if 
      Size<?MAX8BITS -> [<<36:8, Size:8>>, Serialized];
      Size<?MAX16BITS -> [<<37:8, Size:16>>, Serialized];
      Size<?MAX32BITS -> [<<38:8, Size:32>>, Serialized];
      Size<?MAX64BITS -> [<<39:8, Size:64>>, Serialized];
      true -> throw(too_long)
  end.

pair_encode({Key, Value})->
  [bjson_encode(Key), bjson_encode(Value)].
%%
%% Tests
%%
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

encode_test() -> 
  Reference = <<36,81, % map, less than 256 bytes
    16, 5, "hello"/utf8,
    16, 5, "world"/utf8,
    16, 6, "double"/utf8,
    13, 64,20,51,51,51,51,51,51, % double precision float 5.05 64bits
    16, 3, "int"/utf8,
    4,  42, % 42
    16, 7, "neg_int"/utf8,
    10,  0, 4, 147, 224, % -300000
    16, 5, "array"/utf8,
    32, 20, % array, less than 256 bytes
      4, 1, %1
      5, 7, 208, % 2000
      6, 0, 4, 147, 224, % 300000
      16, 5, "hello"/utf8,
      0, %null
      3, %true
      1  %false
  >>,
  Result = iolist_to_binary(encode({struct, [{hello, <<"world">>}, 
                                              {double, 5.05}, 
                                              {int, 42}, 
                                              {neg_int, -300000},
                                              {array, [1,2000,300000,<<"hello">>,null,true,false]}
                                            ]
                                    })),
  %error_logger:info_msg("~p~n~p~n~p...~p", [Reference, Result, binary:longest_common_prefix([Reference, Result]), binary:longest_common_suffix([Reference, Result])]),
  ?assertEqual(Reference, Result).

decede_test() ->
  Result = decode(<<36,93, % map, less than 256 bytes
    16, 5, "hello"/utf8,
    16, 5, "world"/utf8,
    16, 6, "double"/utf8,
    13, 64,20,51,51,51,51,51,51, % double precision float 5.05 64bits
    16, 3, "int"/utf8,
    4,  42, % 42
    16, 7, "neg_int"/utf8,
    10,  0, 4, 147, 224, % -300000
    16, 5, "float"/utf8,
    12, 63, 128, 0, 0, % 1.0 in single precision float - what HaXe will usually send
    16, 5, "array"/utf8,
    32, 20, % array, less than 256 bytes
      4, 1, %1
      5, 7, 208, % 2000
      6, 0, 4, 147, 224, % 300000
      16, 5, "hello"/utf8,
      0, %null
      3, %true
      1  %false
  >>),
  Reference = {struct, [{<<"hello">>, <<"world">>}, 
                        {<<"double">>, 5.05}, 
                        {<<"int">>, 42},
                        {<<"neg_int">>, -300000},
                        {<<"float">>, 1.0},
                        {<<"array">>, [1,2000,300000,<<"hello">>,null,true,false]}
                       ]
              },
  ?assertEqual(Reference, Result).

-endif.

