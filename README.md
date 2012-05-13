erlang-bjson
============

Erlang bjson encoder/decorder ( http://bjson.org/ )

Library for bjson serialization, totally compatible with
mochijson2. See http://bjson.org/ for more details

BJSON vs BSON
-------------

There is another binary flavor of JSON out there: http://bsonspec.org/ . So why not to use that one
(especially because MongoDB uses it and there is a lot of implementations already)?

  * BJSON is more space-efficient (and that is important if you use it in games, for instance).
  * BJSON can be used not only for associative arrays (hashes, documents in BSON terminology), but
    also for plain values like strings and integers.
  * There is no “Oh fuck”'s, like in [emongo](https://github.com/JacobVorreuter/emongo/blob/master/src/emongo_bson.erl#L232).

Cheatsheet
----------

Usage

    bjson:encode({struct, [{hello, <<"world">>}]})

    bjson:decode(<<36,93, 16, 5, "hello"/utf8, 16, 5, "world"/utf8>>)

Short syntax cheatsheet:

    {"key": "value"} ->
      {struct, [<<"key">>, <<"value">>]}

    ["array", 123, 12.34, true, false, null] ->
      [<<"array">>, 123, 12.34, true, false, null]

    "mystring" -> <<"mystring">> or mystring (symbols could be used when encoding)
    1 -> 1, 
    42.0 -> 42.0
    true -> true, 
    false -> false
    null -> null

So, basically, you can use same structures in your mochiweb application and in your binary protocol. Enjoy!
