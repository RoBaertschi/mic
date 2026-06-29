#+vet explicit-allocators
package mic

import "core:container/xar"
import "core:fmt"
import "core:strconv"

P_Precedence :: enum {
	Lowest,
	Assignment,
	Conditional,
	Or,
	And,
	Bitwise_Or,
	Bitwise_Xor,
	Bitwise_And,
	Equal,   // ==, !=
	Ordered, // <, <=, >, >=
	Shift,
	Sum,
	Product,
	Prefix,
}

p_precedences := #partial [Token_Kind]P_Precedence {
	.Equal                     = .Assignment,
	.Hyphen_Equal              = .Assignment,
	.Plus_Equal                = .Assignment,
	.Asterisk_Equal            = .Assignment,
	.Forward_Slash_Equal       = .Assignment,
	.Percent_Equal             = .Assignment,
	.Ampersand_Equal           = .Assignment,
	.Pipe_Equal                = .Assignment,
	.Caret_Equal               = .Assignment,
	.Double_Less_Than_Equal    = .Assignment,
	.Double_Greater_Than_Equal = .Assignment,
	.Question_Mark             = .Conditional,
	.Double_Pipe               = .Or,
	.Double_Ampersand          = .And,
	.Pipe                      = .Bitwise_Or,
	.Caret                     = .Bitwise_Xor,
	.Ampersand                 = .Bitwise_And,
	.Double_Equal              = .Equal,
	.Exclamation_Equal         = .Equal,
	.Less_Than                 = .Ordered,
	.Less_Than_Equal           = .Ordered,
	.Greater_Than              = .Ordered,
	.Greater_Than_Equal        = .Ordered,
	.Double_Less_Than          = .Shift,
	.Double_Greater_Than       = .Shift,
	.Plus                      = .Sum,
	.Hyphen                    = .Sum,
	.Asterisk                  = .Product,
	.Forward_Slash             = .Product,
	.Percent                   = .Product,
}

P_Prefix_Proc :: #type proc(p: ^Parser) -> (expr: ^Ast_Expr, ok: bool)

p_prefix_procs := #partial [Token_Kind]P_Prefix_Proc {
	.Constant      = p_parse_constant,
	.Identifier    = p_parse_variable,
	.Hyphen        = p_parse_unary,
	.Tilde         = p_parse_unary,
	.Exclamation   = p_parse_unary,
	.Double_Hyphen = p_parse_unary,
	.Double_Plus   = p_parse_unary,
	.Open_Paren    = p_parse_grouped_expression,
}

P_Infix_Proc :: #type proc(p: ^Parser, left_expr: ^Ast_Expr) -> (expr: ^Ast_Expr, ok: bool)

p_infix_procs := #partial [Token_Kind]P_Infix_Proc {
	.Equal                     = p_parse_assignment,
	.Hyphen_Equal              = p_parse_assignment,
	.Plus_Equal                = p_parse_assignment,
	.Asterisk_Equal            = p_parse_assignment,
	.Forward_Slash_Equal       = p_parse_assignment,
	.Percent_Equal             = p_parse_assignment,
	.Ampersand_Equal           = p_parse_assignment,
	.Pipe_Equal                = p_parse_assignment,
	.Caret_Equal               = p_parse_assignment,
	.Double_Less_Than_Equal    = p_parse_assignment,
	.Double_Greater_Than_Equal = p_parse_assignment,
	.Question_Mark             = p_parse_conditional,
	.Plus                      = p_parse_binary,
	.Hyphen                    = p_parse_binary,
	.Asterisk                  = p_parse_binary,
	.Forward_Slash             = p_parse_binary,
	.Percent                   = p_parse_binary,
	.Ampersand                 = p_parse_binary,
	.Pipe                      = p_parse_binary,
	.Caret                     = p_parse_binary,
	.Double_Less_Than          = p_parse_binary,
	.Double_Greater_Than       = p_parse_binary,
	.Double_Ampersand          = p_parse_binary,
	.Double_Pipe               = p_parse_binary,
	.Double_Equal              = p_parse_binary,
	.Exclamation_Equal         = p_parse_binary,
	.Less_Than                 = p_parse_binary,
	.Less_Than_Equal           = p_parse_binary,
	.Greater_Than              = p_parse_binary,
	.Greater_Than_Equal        = p_parse_binary,
}

P_Postfix_Proc :: #type proc(p: ^Parser, left_expr: ^Ast_Expr) -> (expr: ^Ast_Expr, ok: bool)

p_postfix_procs := #partial [Token_Kind]P_Postfix_Proc {
	.Double_Hyphen = p_parse_postfix,
	.Double_Plus   = p_parse_postfix,
}

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

p_peek_prec :: proc(p: ^Parser) -> P_Precedence {
	return p_precedences[p.peek_token.kind]
}

p_current_prec :: proc(p: ^Parser) -> P_Precedence {
	return p_precedences[p.current_token.kind]
}

p_parse_unit :: proc(p: ^Parser) {
	p.u.function = p_parse_def_function(p)
	p_expect_peek(p, .EOF)
}

p_parse_def_function :: proc(p: ^Parser) -> (def: ^Ast_Def_Function) {
	p_skip_def_function :: proc(p: ^Parser) {
		for p.current_token.kind != .EOF && p.current_token.kind != .Close_Brace {
			p_next_token(p)
		}
	}

	def = ast_new(p.u, p.current_token, Ast_Def_Function)
	if _, ok := p_expect(p, .Int); !ok {
		p_skip_def_function(p)
		return
	}

	ident, ok := p_expect_peek(p, .Identifier)
	if !ok {
		p_skip_def_function(p)
		return
	}

	def.t = ident
	def.name = ast_new_ident(p.u, ident)

	if _, ok := p_expect_peek(p, .Open_Paren); !ok {
		p_skip_def_function(p)
		return
	}

	if _, ok := p_expect_peek(p, .Void); !ok {
		p_skip_def_function(p)
		return
	}

	if _, ok := p_expect_peek(p, .Close_Paren); !ok {
		p_skip_def_function(p)
		return
	}

	if _, ok := p_expect_peek(p, .Open_Brace); !ok {
		p_skip_def_function(p)
		return
	}

	def.body, ok = p_parse_block(p)
	if !ok {
		p_skip_def_function(p)
		return
	}

	return
}

p_parse_block :: proc(p: ^Parser) -> (Ast_Block, bool) {
	assert(p.current_token.kind == .Open_Brace)
	block: Ast_Block
	xar.init(&block, ast_allocator(p.u))
	
	p_next_token(p)

	loop: for p.current_token.kind != .EOF {
		#partial switch p.current_token.kind {
		case .Close_Brace:
			break loop
		case .Int:
			xar.append(&block, p_parse_decl(p))
		case:
			xar.append(&block, p_parse_stmt(p))
		}
		p_next_token(p)
	}

	_, ok := p_expect(p, .Close_Brace)
	return block, ok
}

p_parse_decl :: proc(p: ^Parser) -> ^Ast_Decl {
	p_skip_decl :: proc(p: ^Parser) {
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

	token, ok := p_expect(p, .Int)
	if !ok {
		p_skip_decl(p)
		return ast_new_decl_error(p.u, token)
	}

	decl_variable := ast_new(p.u, token, Ast_Decl_Variable)

	ident: Token
	ident, ok = p_expect_peek(p, .Identifier)
	if !ok {
		p_skip_decl(p)
		return ast_new_decl_error(p.u, token)
	}

	decl_variable.name = ast_new_ident(p.u, ident)

	#partial switch p.peek_token.kind {
	case .Semicolon:
		p_expect_peek(p, .Semicolon)

		return decl_variable

	case .Equal:
		p_next_token(p) // Skip '='
		p_next_token(p) // Move onto the expression

		decl_variable.init, ok = p_parse_expr(p, .Lowest)
		if !ok {
			p_skip_decl(p)
			return decl_variable
		}

		_, ok = p_expect_peek(p, .Semicolon)
		if !ok {
			p_skip_decl(p)
		}
		return decl_variable
	case:
		p_error(p, p.peek_token, "expected Semicolon or Equal, got %v", p.peek_token.kind)
		p_skip_decl(p)
		return decl_variable
	}

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

	p_skip_stmt_close_brace :: proc(p: ^Parser) {
		for p.current_token.kind != .EOF {
			#partial switch p.peek_token.kind {
			case .Close_Brace:
				p_next_token(p)
				return
			case:
				p_next_token(p)
			}
		}
	}

	#partial switch p.current_token.kind {
	case .Return:
		stmt, ok := p_parse_return(p)
		if !ok {
			p_skip_stmt(p)
		}
		return stmt
	case .If:
		stmt, _ := p_parse_if(p)
		// NOTE(robin): cannot use skip because no semicolon or } required
		// TODO(robin): find a better way to skip if stmt's
		return stmt
	case .Semicolon:
		return ast_new(p.u, p.current_token, Ast_Stmt)
	case .Goto:
		stmt, ok := p_parse_goto(p)
		if !ok {
			p_skip_stmt(p)
		}
		return stmt
	case .Open_Brace:
		stmt, ok := p_parse_compound(p)
		if !ok {
			p_skip_stmt_close_brace(p)
		}
		return stmt
	case .Break:
		stmt, ok := p_parse_keyword(p, .Break, Ast_Stmt_Break)
		if !ok {
			p_skip_stmt(p)
		}
		return stmt
	case .Continue:
		stmt, ok := p_parse_keyword(p, .Continue, Ast_Stmt_Continue)
		if !ok {
			p_skip_stmt(p)
		}
		return stmt
	case .While:
		stmt, _ := p_parse_while(p)
		// NOTE(robin): cannot use skip because no semicolon or } required
		// TODO(robin): find a better way to skip if stmt's
		return stmt
	case .Do:
		stmt, _ := p_parse_do_while(p)
		// NOTE(robin): cannot use skip because no semicolon or } required
		// TODO(robin): find a better way to skip if stmt's
		return stmt
	case .For:
		stmt, _ := p_parse_for(p)
		// NOTE(robin): cannot use skip because no semicolon or } required
		// TODO(robin): find a better way to skip if stmt's
		return stmt
	case .Case:
		stmt, _ := p_parse_case(p)
		// NOTE(robin): cannot use skip because no semicolon or } required
		// TODO(robin): find a better way to skip if stmt's
		return stmt
	case .Default:
		stmt, _ := p_parse_default(p)
		// NOTE(robin): cannot use skip because no semicolon or } required
		// TODO(robin): find a better way to skip if stmt's
		return stmt
	case .Switch:
		stmt, _ := p_parse_switch(p)
		// NOTE(robin): cannot use skip because no semicolon or } required
		// TODO(robin): find a better way to skip if stmt's
		return stmt
	case .Identifier:
		if p.peek_token.kind == .Colon {
			stmt, _ := p_parse_label(p)
			// NOTE(robin): cannot use skip because no semicolon or } required
			// TODO(robin): find a better way to skip if stmt's
			return stmt
		}
		fallthrough
	case:
		stmt_expr := ast_new(p.u, p.current_token, Ast_Stmt_Expr)
		stmt_expr.expr, _ = p_parse_expr(p, .Lowest)
		if _, ok := p_expect_peek(p, .Semicolon); !ok {
			p_skip_stmt(p)
		}
		return stmt_expr
	}
}

p_parse_switch :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_switch: Token
	token_switch, ok = p_expect(p, .Switch)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_switch)
		return
	}

	stmt_switch := ast_new(p.u, token_switch, Ast_Stmt_Switch)
	stmt         = stmt_switch

	p_expect_peek(p, .Open_Paren) or_return
	p_next_token(p)
	stmt_switch.expr, ok = p_parse_expr(p, .Lowest)
	ok or_return

	p_expect_peek(p, .Close_Paren) or_return
	p_next_token(p)
	stmt_switch.body = p_parse_stmt(p)

	return
}

p_parse_default :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_default: Token
	token_default, ok = p_expect(p, .Default)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_default)
		return
	}

	stmt_case      := ast_new(p.u, token_default, Ast_Stmt_Default)
	stmt             = stmt_case
	
	_, ok = p_expect_peek(p, .Colon)
	ok or_return

	p_next_token(p)
	stmt_case.inner = p_parse_stmt(p)
	return
}

p_parse_case :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_case: Token
	token_case, ok = p_expect(p, .Case)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_case)
		return
	}

	stmt_case      := ast_new(p.u, token_case, Ast_Stmt_Case)
	stmt             = stmt_case

	p_next_token(p)

	stmt_case.condition, ok = p_parse_expr(p, .Lowest)
	ok or_return
	
	_, ok = p_expect_peek(p, .Colon)
	ok or_return

	p_next_token(p)
	stmt_case.inner = p_parse_stmt(p)
	return
}

p_parse_for :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_for: Token
	token_for, ok = p_expect(p, .For)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_for)
		return
	}

	stmt_for := ast_new(p.u, token_for, Ast_Stmt_For)
	stmt      = stmt_for

	p_expect_peek(p, .Open_Paren) or_return
	p_next_token(p)

	#partial switch p.current_token.kind {
	case .Semicolon: // do nothing
	case .Int:
		stmt_for.init = p_parse_decl(p)
		p_expect(p, .Semicolon) or_return
	case:
		stmt_for.init, ok = p_parse_expr(p, .Lowest)
		ok or_return
		p_expect_peek(p, .Semicolon) or_return
	}

	assert(p.current_token.kind == .Semicolon)

	if p.peek_token.kind != .Semicolon {
		p_next_token(p)
		stmt_for.condition, ok = p_parse_expr(p, .Lowest)
		ok or_return
		p_expect_peek(p, .Semicolon) or_return
	} else {
		p_next_token(p)
	}

	assert(p.current_token.kind == .Semicolon)

	if p.peek_token.kind != .Close_Paren {
		p_next_token(p)
		stmt_for.post, ok = p_parse_expr(p, .Lowest)
		ok or_return
		p_expect_peek(p, .Close_Paren) or_return
	} else {
		p_next_token(p)
	}

	p_next_token(p)
	stmt_for.body = p_parse_stmt(p)
	return
}

p_parse_do_while :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_do: Token
	token_do, ok = p_expect(p, .Do)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_do)
		return
	}

	stmt_while := ast_new(p.u, token_do, Ast_Stmt_Do_While)
	stmt        = stmt_while

	p_next_token(p)
	stmt_while.body = p_parse_stmt(p)

	p_expect_peek(p, .While) or_return
	p_expect_peek(p, .Open_Paren) or_return
	p_next_token(p)
	stmt_while.condition, ok = p_parse_expr(p, .Lowest)
	ok or_return // NOTE(robin): a bit of an abuse of the syntax, but I will allow it for now

	p_expect_peek(p, .Close_Paren) or_return
	p_expect_peek(p, .Semicolon) or_return
	return
}

p_parse_while :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_while: Token
	token_while, ok = p_expect(p, .While)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_while)
		return
	}

	stmt_while := ast_new(p.u, token_while, Ast_Stmt_While)
	stmt        = stmt_while

	p_expect_peek(p, .Open_Paren) or_return
	p_next_token(p)

	// NOTE: We still want to assign the condition even if expr parsing failed
	stmt_while.condition, ok = p_parse_expr(p, .Lowest)
	ok or_return

	p_expect_peek(p, .Close_Paren) or_return
	p_next_token(p)

	stmt_while.body = p_parse_stmt(p)
	ok              = true
	return
}

p_parse_keyword :: proc(p: ^Parser, kind: Token_Kind, $T: typeid) -> (^Ast_Stmt, bool) {
	token_keyword, ok := p_expect(p, kind)
	if !ok {
		return ast_new_stmt_error(p.u, token_keyword), false
	}

	stmt_keyword := ast_new(p.u, token_keyword, T)

	_, ok = p_expect_peek(p, .Semicolon)
	return stmt_keyword, ok
}

p_parse_compound :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	stmt_block := ast_new(p.u, p.current_token, Ast_Stmt_Compound)
	stmt        = stmt_block

	stmt_block.block, ok = p_parse_block(p)
	return
}

p_parse_goto :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_goto: Token
	token_goto, ok = p_expect(p, .Goto)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_goto)
		return
	}

	stmt_goto := ast_new(p.u, token_goto, Ast_Stmt_Goto)
	stmt       = stmt_goto

	token_label: Token
	token_label = p_expect_peek(p, .Identifier) or_return

	stmt_goto.label = ast_new_ident(p.u, token_label)

	p_expect_peek(p, .Semicolon) or_return
	return
}

p_parse_label :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_label: Token
	token_label, ok = p_expect(p, .Identifier)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_label)
		return
	}

	stmt_label      := ast_new(p.u, token_label, Ast_Stmt_Label)
	stmt             = stmt_label
	stmt_label.name  = ast_new_ident(p.u, token_label)
	
	_, ok = p_expect_peek(p, .Colon)
	ok or_return

	p_next_token(p)
	stmt_label.inner = p_parse_stmt(p)
	return
}

p_parse_return :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_return: Token
	token_return, ok = p_expect(p, .Return)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_return)
		return
	}

	stmt_return := ast_new(p.u, token_return, Ast_Stmt_Return)
	stmt         = stmt_return
	p_next_token(p)

	stmt_return.result, ok = p_parse_expr(p, .Lowest)
	ok or_return

	p_expect_peek(p, .Semicolon) or_return

	return
}

p_parse_if :: proc(p: ^Parser) -> (stmt: ^Ast_Stmt, ok: bool) {
	token_if: Token
	token_if, ok = p_expect(p, .If)
	if !ok {
		stmt = ast_new_stmt_error(p.u, token_if)
		return
	}

	stmt_if := ast_new(p.u, token_if, Ast_Stmt_If)
	stmt     = stmt_if

	p_expect_peek(p, .Open_Paren) or_return
	p_next_token(p)

	stmt_if.condition, ok = p_parse_expr(p, .Lowest)
	ok or_return


	p_expect_peek(p, .Close_Paren) or_return

	p_next_token(p)

	stmt_if.then = p_parse_stmt(p)

	if p.peek_token.kind == .Else {
		p_next_token(p)
		p_next_token(p)

		stmt_if.else_ = p_parse_stmt(p)
	}

	return
}

p_parse_expr :: proc(p: ^Parser, prec: P_Precedence) -> (expr: ^Ast_Expr, ok: bool) {
	prefix_proc := p_prefix_procs[p.current_token.kind]
	if prefix_proc == nil {
		p_error(p, p.current_token, "invalid token for expression %v", p.current_token.kind)
		expr = ast_new_expr_error(p.u, p.current_token)
		return
	}

	expr, ok = prefix_proc(p)
	if !ok {
		return
	}

	handle_postfix :: proc(p: ^Parser, left_expr: ^Ast_Expr) -> (expr: ^Ast_Expr, ok: bool) {
		ok   = true
		expr = left_expr

		for postfix := p_postfix_procs[p.peek_token.kind]; postfix != nil; postfix = p_postfix_procs[p.peek_token.kind] {
			p_next_token(p)
			expr = postfix(p, expr) or_return
		}

		return
	}

	for p.peek_token.kind != .Semicolon && prec < p_peek_prec(p) {
		infix_proc := p_infix_procs[p.peek_token.kind]
		if infix_proc == nil {
			return handle_postfix(p, expr)
		}

		p_next_token(p)
		expr, ok = infix_proc(p, expr)
		if !ok {
			return
		}
	}

	return handle_postfix(p, expr)
}

p_parse_grouped_expression :: proc(p: ^Parser) -> (expr: ^Ast_Expr, ok: bool) {
	p_next_token(p)

	expr, ok = p_parse_expr(p, .Lowest)
	if !ok {
		return
	}

	_, ok = p_expect_peek(p, .Close_Paren)
	return
}

p_parse_unary :: proc(p: ^Parser) -> (expr: ^Ast_Expr, ok: bool) {
	expr_unary := ast_new(p.u, p.current_token, Ast_Expr_Unary)
	expr = expr_unary

	#partial switch p.current_token.kind {
	case .Hyphen:        expr_unary.operator = .Negate
	case .Tilde:         expr_unary.operator = .Complement
	case .Exclamation:   expr_unary.operator = .Not
	case .Double_Hyphen: expr_unary.operator = .Decrement
	case .Double_Plus:   expr_unary.operator = .Increment
	case:                fmt.panicf("invalid token kind for p_parse_unary: %v", p.current_token.kind)
	}

	p_next_token(p)
	expr_unary.inner, ok = p_parse_expr(p, .Prefix)
	return
}

p_parse_postfix :: proc(p: ^Parser, left_expr: ^Ast_Expr) -> (expr: ^Ast_Expr, ok: bool) {
	expr_postfix       := ast_new(p.u, p.current_token, Ast_Expr_Postfix)
	expr_postfix.inner  = left_expr
	expr                = expr_postfix

	#partial switch p.current_token.kind {
	case .Double_Hyphen: expr_postfix.operator = .Decrement
	case .Double_Plus:   expr_postfix.operator = .Increment
	case:                fmt.panicf("invalid token kind for p_parse_postfix: %v", p.current_token.kind)
	}

	ok = true
	return
}

p_parse_binary :: proc(p: ^Parser, lhs: ^Ast_Expr) -> (expr: ^Ast_Expr, ok: bool) {
	expr_binary     := ast_new(p.u, p.current_token, Ast_Expr_Binary)
	expr             = expr_binary
	expr_binary.lhs  = lhs

	#partial switch p.current_token.kind {
	case .Asterisk:            expr_binary.operator = .Multiply
	case .Forward_Slash:       expr_binary.operator = .Divide
	case .Percent:             expr_binary.operator = .Remainder
	case .Plus:                expr_binary.operator = .Add
	case .Hyphen:              expr_binary.operator = .Subtract
	case .Ampersand:           expr_binary.operator = .Bitwise_And
	case .Pipe:                expr_binary.operator = .Bitwise_Or
	case .Caret:               expr_binary.operator = .Bitwise_Xor
	case .Double_Less_Than:    expr_binary.operator = .Left_Shift
	case .Double_Greater_Than: expr_binary.operator = .Right_Shift
	case .Double_Ampersand:    expr_binary.operator = .And
	case .Double_Pipe:         expr_binary.operator = .Or
	case .Double_Equal:        expr_binary.operator = .Equal
	case .Exclamation_Equal:   expr_binary.operator = .Not_Equal
	case .Less_Than:           expr_binary.operator = .Less_Than
	case .Less_Than_Equal:     expr_binary.operator = .Less_Or_Equal
	case .Greater_Than:        expr_binary.operator = .Greater_Than
	case .Greater_Than_Equal:  expr_binary.operator = .Greater_Or_Equal
	case:                      fmt.panicf("invalid token kind for p_parse_binary: %v", p.current_token.kind)
	}

	prec := p_current_prec(p)
	p_next_token(p)
	expr_binary.rhs, ok = p_parse_expr(p, prec)
	return
}

p_parse_assignment :: proc(p: ^Parser, lhs: ^Ast_Expr) -> (expr: ^Ast_Expr, ok: bool) {
	expr_assignment     := ast_new(p.u, p.current_token, Ast_Expr_Assignment)
	expr                 = expr_assignment
	expr_assignment.lhs  = lhs

	#partial switch p.current_token.kind {
	case .Equal:                     expr_assignment.operator = .None
	case .Hyphen_Equal:              expr_assignment.operator = .Subtract
	case .Plus_Equal:                expr_assignment.operator = .Add
	case .Asterisk_Equal:            expr_assignment.operator = .Multiply
	case .Forward_Slash_Equal:       expr_assignment.operator = .Divide
	case .Percent_Equal:             expr_assignment.operator = .Remainder
	case .Ampersand_Equal:           expr_assignment.operator = .Bitwise_And
	case .Pipe_Equal:                expr_assignment.operator = .Bitwise_Or
	case .Caret_Equal:               expr_assignment.operator = .Bitwise_Xor
	case .Double_Less_Than_Equal:    expr_assignment.operator = .Left_Shift
	case .Double_Greater_Than_Equal: expr_assignment.operator = .Right_Shift
	case:                            fmt.panicf("invalid token kind for p_parse_assignment: %v", p.current_token.kind)
	}

	p_next_token(p)
	expr_assignment.rhs, ok = p_parse_expr(p, .Lowest)
	return
}

p_parse_conditional :: proc(p: ^Parser, lhs: ^Ast_Expr) -> (expr: ^Ast_Expr, ok: bool) {
	ensure(p.current_token.kind == .Question_Mark)
	expr_conditional           := ast_new(p.u, p.current_token, Ast_Expr_Conditional)
	expr                      = expr_conditional
	expr_conditional.condition  = lhs

	p_next_token(p)
	expr_conditional.then = p_parse_expr(p, .Lowest) or_return
	if _, ok = p_expect_peek(p, .Colon); !ok {
		expr_conditional.else_ = ast_new_expr_error(p.u, p.peek_token)
		return
	}

	p_next_token(p)
	expr_conditional.else_, ok = p_parse_expr(p, .Assignment)
	return
}

p_parse_constant :: proc(p: ^Parser) -> (expr: ^Ast_Expr, ok: bool) {
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

p_parse_variable :: proc(p: ^Parser) -> (expr: ^Ast_Expr, ok: bool) {
	token: Token
	token, ok = p_expect(p, .Identifier)
	if !ok {
		expr = ast_new_expr_error(p.u, token)
		return
	}

	expr_variable      := ast_new(p.u, token, Ast_Expr_Variable)
	expr                = expr_variable
	expr_variable.name  = ast_new_ident(p.u, token)

	return
}
