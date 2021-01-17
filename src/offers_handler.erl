-module(offers_handler).
-import(util, [response/3, map_to_json/1, generate_id/1, db/2]).
-behavior(cowboy_handler).

-export([init/2]).

init(Req=#{method := <<"GET">>}, State) ->
	Params = cowboy_req:parse_qs(Req),
	{Status, Values} = case Params of 
		[{<<"id">>, OfferId}] ->
			erlang:display(offer_exists(binary_to_list(OfferId))),
			erlang:display(get_offer_price(binary_to_list(OfferId))),
			find_offer_by_id(binary_to_list(OfferId));
		[] -> 
			F = fun (Offer, Acc) -> Acc1 = [map_to_json(Offer) | Acc], Acc1 end,
			Items = db(offers, fun() -> dets:foldl(F, [], records_db) end),
			Items1 = lists:sort(Items),
			Body = "
			{
				\"offers\": [~s]
			}",
			{200, io_lib:format(Body, [Items1])}
	end,
    Res = response(Status, Values, Req),
    {ok, Res, State};

init(Req=#{method := <<"POST">>}, State) ->
	OfferId = generate_id(offers),
	Offer = offer_from_body(OfferId, Req),
	Inserted = insert_offer(OfferId, Offer),
	Res = response(201, Inserted, Req),
    {ok, Res, State};

init(Req=#{method := <<"PUT">>}, State) ->
	[{<<"id">>, OfferIdRaw}] = cowboy_req:parse_qs(Req),
	OfferId = binary_to_list(OfferIdRaw),
	Offer = offer_from_body(OfferId, Req),
	Updated = update_offer(OfferId, Offer),
    Res = response(200, Updated, Req),
    {ok, Res, State};

init(Req=#{method := <<"DELETE">>}, State) ->
	[{<<"id">>, OfferId}] = cowboy_req:parse_qs(Req),
	delete_offer_by_id(binary_to_list(OfferId)),
    {ok, response(204, <<"">>, Req), State};

init(Req, State) ->
    Res = cowboy_req:reply(405, #{}, Req),
    {ok, Res, State}.

offer_from_body(Id, Req) -> 
	{ok, [
		{<<"name">>, Name},
		{<<"price">>, Price},
		{<<"description">>, Description}
	], _ } = cowboy_req:read_urlencoded_body(Req),
	#{
		id => {Id, text},
		name => {Name, text},
		price => {Price, float},
		description => {Description, text}
	}.

find_offer_by_id(OfferId) -> 
	Offers = db(offers, fun() -> dets:lookup(records_db, OfferId) end),
	case Offers of
		[{OfferId2, Data}] ->
			{200, map_to_json({OfferId2, Data})};
		[] ->
			{404, io_lib:format("{\"not_found\": \"record ~s not found\"}", [OfferId])};
		_ ->
			{500, io_lib:format("{\"extra_records\": \"extra records for ~s\"}", [OfferId])}
	end.

insert_offer(Id, Offer) -> 
	ok = db(offers, fun () -> 
    	ok = dets:insert(records_db, {Id, Offer}),
    	dets:sync(records_db)
	end),
	{200, Inserted} = find_offer_by_id(Id),
	Inserted.

update_offer(Id, Offer) ->
	{200, _} = find_offer_by_id(Id),
	delete_offer_by_id(Id),
	insert_offer(Id, Offer).

delete_offer_by_id(OfferId) ->
	ok = db(offers, fun () -> dets:delete(records_db, OfferId) end).

offer_exists(OfferId) ->
	{Status, _} = find_offer_by_id(OfferId),
	if Status == 200 -> ok;
	true -> error end.

get_offer_price(OfferId) ->
	Offers = db(offers, fun() -> dets:lookup(records_db, OfferId) end),
	case Offers of
		[{_, Data}] -> 
			{ok, {Price, float}} = maps:find(price, Data),
			{ok, list_to_float(binary_to_list(Price))};
		_ -> {error, 0.0}
	end.
