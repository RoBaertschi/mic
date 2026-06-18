#+vet explicit-allocators
package mic

import "core:strconv"
P_Error_Proc :: #type proc(data: rawptr, t: Token, format: string, args: ..any)

Parser :: struct {
	current_token, peek_token: Token,

	l: ^Lexer,
	u: ^Unit,

	errors:     int,
	error_proc: P_Error_Proc,
	error_data: rawptr,
}

p_init :: proc(p: ^Parser, u: ^Unit, l: ^Lexer, error_proc: P_Error_Proc, error_data: rawptr = nil) {
	p^ = {
		l          = l,
		u          = u,
		error_proc = error_proc,
		error_data = error_data,
	}

	p_next_token(p)
	p_next_token(p)
}

p_error :: proc(p: ^Parser, t: Token, format: string, args: ..any) {
	p.errors += 1
	if p.error_proc != nil {
		p.error_proc(p.error_data, t, format, ..args)
	}
}

p_next_token :: proc(p: ^Parser) {
	p.current_token = p.peek_token
	p.peek_token    = l_next_token(p.l)
}

p_expect :: proc(p: ^Parser, current: Token_Kind) -> (t: Token, ok: bool) {
	ok = current == p.current_token.kind
	t  = p.current_token
	if !ok {
		p_error(p, p.current_token, "unexpected %v, expected %v", p.current_token.kind, current)
	}

	return
}

p_expect_peek :: proc(p: ^Parser, peek: Token_Kind) -> (t: Token, ok: bool) {
	ok = peek == p.peek_token.kind
	t  = p.peek_token

	if !ok {
		p_error(p, p.peek_token, "unexpected %v, expected %v", p.peek_token.kind, peek)
		return
	}
	p_next_token(p)
	return
}

p_parse_unit :: proc(p: ^Parser) {
	p.u.function = p_parse_def_function(p)
	p_expect_peek(p, .EOF)
}

p_parse_def_function :: proc(p: ^Parser) -> (def: ^Ast_Def_Function) {
	p_expect(p, .Int)
	ident, _ := p_expect_peek(p, .Identifier)

	p_expect_peek(p, .Open_Paren)
	p_expect_peek(p, .Void)
	p_expect_peek(p, .Close_Paren)
	p_expect_peek(p, .Open_Brace)
	p_next_token(p)

	stmt := p_parse_stmt(p)
	p_expect_peek(p, .Close_Brace)

	def = ast_new(p.u, ident, Ast_Def_Function)
	def.body = stmt
	def.name = ast_new_ident(p.u, ident)
	return
}

p_parse_stmt :: proc(p: ^Parser) -> ^Ast_Stmt {
	p_skip_stmt :: proc(p: ^Parser) {
		for p.current_token.kind != .EOF {
			#partial switch p.peek_token.kind {
			case .Semicolon:
				p_next_token(p)
				return
			case .Close_Brace:
				return
			case:
				p_next_token(p)
			}
		}
	}

	return_token, ok := p_expect(p, .Return)
	if !ok {
		p_skip_stmt(p)
		return ast_new_stmt_error(p.u, return_token)
	}

	stmt_return := ast_new(p.u, return_token, Ast_Stmt_Return)
	p_next_token(p)

	stmt_return.result, ok = p_parse_expr(p)
	if !ok {
		p_skip_stmt(p)
		return stmt_return
	}

	p_expect_peek(p, .Semicolon)

	return stmt_return
}

p_parse_expr :: proc(p: ^Parser) -> (expr: ^Ast_Expr, ok: bool) {
	token: Token
	token, ok = p_expect(p, .Constant)
	if !ok {
		expr = ast_new_expr_error(p.u, token)
		return
	}

	value: int
	value, ok = strconv.parse_int(token.content)
	if !ok {
		expr = ast_new_expr_error(p.u, token)
		return
	}

	expr_constant       := ast_new(p.u, token, Ast_Expr_Constant)
	expr_constant.value  = value
	expr                 = expr_constant
	return
}
