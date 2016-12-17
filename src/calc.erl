-module(calc).
-export([parse/1, compute/1, print/1, 
	compile/1, simulate/1, simplify/1, eval/1]).

parse(String) ->
	Tokens = tokenize(String),
	{Result, _} = parse_impl(Tokens, {}),
	{exps, Result}.

compute(Expression) ->
	{exps, ExpressionData} = Expression,
	compute_impl(ExpressionData).

print(Expression) ->
	{exps, ExpressionData} = Expression,
	print_impl(ExpressionData),
	io:format("~n").

compile(Expression) ->
	{exps, ExpressionData} = Expression,
	{stack_actions, compile_impl(ExpressionData, [])}.

simulate(StackActions) ->
	{stack_actions, Stack} = StackActions,
	{Result, _} = simulate_impl(Stack),
	Result.

simplify(Expression) ->
	{exps, ExpressionData} = Expression,
	{exps, simplify_impl(simplify_impl(ExpressionData))}.

eval(String) ->
	compute(simplify(parse(String))).

print_impl({number, Number}) ->
	io:format("~B", [Number]);
print_impl({Operator, Operand}) ->
	io:format("(~s", [get_operator_str(Operator)]),
	print_impl(Operand),
	io:format(")");
print_impl({Operator, Operand1, Operand2}) ->
	io:format("("),
	print_impl(Operand1),
	io:format("~s", [get_operator_str(Operator)]),
	print_impl(Operand2),
	io:format(")").

compute_impl({number, Number}) ->
	Number;
compute_impl({unary_minus, Expression}) ->
	Operand = compute_impl(Expression),
	do_unary_operation(unary_minus, Operand);
compute_impl({Operator, LeftExpression, RightExpression}) ->
	Operand1 = compute_impl(LeftExpression),
	Operand2 = compute_impl(RightExpression),
	do_binary_operation(Operator, Operand1, Operand2).

simplify_impl({number, Value}) ->
	{number, Value};
simplify_impl({unary_minus, Expression}) ->
	SimplifiedExpression = simplify_impl(Expression),
	case SimplifiedExpression of
		{number, 0} -> {number, 0};
		{number, Value} -> {number, -Value};
		_ -> {unary_minus, SimplifiedExpression}
	end;
simplify_impl({Operator, Operand1, Operand2}) ->
	SimplifiedOperand1 = simplify_impl(Operand1),
	SimplifiedOperand2 = simplify_impl(Operand2),
	simplify_operation({Operator, SimplifiedOperand1, SimplifiedOperand2}).

simplify_operation({minus, Operand1, Operand2}) ->
	case {Operand1, Operand2} of
		{{number, 0}, {number, 0}} -> {number, 0};
		{{number, 0}, _} -> {unary_minus, Operand2};
		{_, {number, 0}} -> Operand1;
		_ -> {minus, Operand1, Operand2}
	end;
simplify_operation({plus, Operand1, Operand2}) ->
	case {Operand1, Operand2} of
		{{number, 0}, {number, 0}} -> {number, 0};
		{{number, 0}, _} -> Operand2;
		{_, {number, 0}} -> Operand1;
		_ -> {plus, Operand1, Operand2}
	end;
simplify_operation({multiply, Operand1, Operand2}) ->
	case {Operand1, Operand2} of
		{{number, 0}, _} -> {number, 0};
		{_, {number, 0}} -> {number, 0};
		{{number, 1}, {number, 1}} -> 1;
		{{number, 1}, _} -> Operand2;
		{_, {number, 1}} -> Operand1;
		{{number, -1}, {number, -1}} -> {number, 1};
		{{number, -1}, _} -> {unary_minus, Operand2};
		{_, {number, -1}} -> {unary_minus, Operand1};
		_ -> {multiply, Operand1, Operand2}
	end;
simplify_operation({division, Operand1, Operand2}) ->
	case {Operand1, Operand2} of
		{_, {number, 0}} -> {division, Operand1, Operand2};
		{{number, 0}, _} -> {number, 0};
		{{number, 1}, {number, 1}} -> {number, 1};
		{_, {number, 1}} -> Operand1;
		{{number, -1}, {number, -1}} -> {number, 1};
		{_, {number, -1}} -> {unary_minus, Operand1};
		_ -> {division, Operand1, Operand2}
	end.

simulate_impl([H|T]) when is_number(H)->
	{H, T};
simulate_impl([unary_minus|T]) ->
	{Operand, NewStack} = simulate_impl(T),
	{do_unary_operation(unary_minus, Operand), NewStack};
simulate_impl([H|T]) ->
	{Operand2, NewStack} = simulate_impl(T),
	{Operand1, NewStack2} = simulate_impl(NewStack),
	{do_binary_operation(H, Operand1, Operand2), NewStack2}.

do_unary_operation(Operation, Operand) when Operation =:= unary_minus ->
	-Operand.

do_binary_operation(Operation, Operand1, Operand2) -> 
	case Operation of
		plus -> Operand1 + Operand2;
		minus -> Operand1 - Operand2;
		multiply -> Operand1*Operand2;
		division -> Operand1/Operand2
	end.

compile_impl(Expression, Stack) ->
	NewStack = case Expression of 
		{number, Value} -> [Value|Stack];
		{Operator, Operand1} -> 
			[Operator|compile_impl(Operand1, Stack)];
		{Operator, Operand1, Operand2} -> 
			[Operator|compile_impl(Operand2, compile_impl(Operand1, Stack))]
	end,
	NewStack.
	
tokenize([]) ->
	[];
tokenize([H|T]) ->
	State = if 
			H >= $0 andalso H =< $9 -> read_number;
			true -> read_operator
		end,
	String = [H|T],
	case State of
		read_operator -> [{operator, get_operator_name(H)}|tokenize(T)];
		read_number -> Number = list_to_integer(extrude_number(String)),
						StringWithoutNumber = remove_number(String),
						[{number, Number}|tokenize(StringWithoutNumber)]
	end.

parse_impl([], Result) -> {Result, []};
parse_impl(Tokens, Result) ->
	{NewResult, NewNextTokens, MustContinue} = case Tokens of
		[{operator, unary_minus},{operator, open_bracket}|T] -> 
			%This case is needed for parsing expressions like "(~(1+2)-3)".
			%If we don't think about unary minus and bracket as one symbol
			%we would have a problem with recursion level. 
			%I don't know another way to solve this problem.
			{SubResult, NextTokens} = parse_impl(T, {}),
			{{unary_minus, SubResult}, NextTokens, true};
		[{operator, unary_minus}|T] -> 
			{SubResult, NextTokens} = parse_impl(T, {}),
			{{unary_minus, SubResult}, NextTokens, true};
		[{operator, open_bracket}|T] -> 
			{SubResult, NextTokens} = parse_impl(T, {}),
			{SubResult, NextTokens, true};
		[{operator, close_bracket}|T] -> {Result, T, false};
		[{operator, Operator}|T] ->
			{RightSubResult, NextTokens} = parse_impl(T, {}),
			SubResult = {Operator, Result, RightSubResult},
			{SubResult, NextTokens, false};
		[{number, Operand}|T] ->
			{{number, Operand}, T, true}
	end,
	case MustContinue of
		true -> parse_impl(NewNextTokens, NewResult);
		false -> {NewResult, NewNextTokens}
	end.

get_operator_name(OpChar) ->
	case OpChar of
		$+ -> plus;
		$~ -> unary_minus;
		$- -> minus;
		$* -> multiply;
		$/ -> division;
		$( -> open_bracket;
		$) -> close_bracket
	end.	

get_operator_str(Operator) ->
	case Operator of
		plus -> "+";
		unary_minus -> "~";
		minus -> "-";
		multiply -> "*";
		division -> "/"
	end.	

extrude_number([H|T]) when H >= $0 andalso H =< $9 ->
	[H|extrude_number(T)];
extrude_number(_) ->
	[].

remove_number([H|T]) when H >= $0 andalso H =< $9 ->
	remove_number(T);
remove_number(L) ->
	L.