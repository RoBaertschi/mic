package mic

import "core:container/xar"
import "core:fmt"
import "core:io"
import "core:mem"
import "base:intrinsics"
import "core:mem/virtual"

@require_results
ast_new :: proc(u: ^Unit, t: Token, $T: typeid) -> ^T {
	ptr, err := virtual.new(&u.arena, T)
	ensure(err == nil) // TODO(robin): handle allocator error
	ptr.t = t
	when intrinsics.type_has_field(T, "variant") {
		// && does not seem to work
		when intrinsics.type_is_variant_of(intrinsics.type_field_type(T, "variant"), ^T) {
			ptr.variant = ptr
		}
	}
	return ptr
}

@require_results
ast_allocator :: proc(u: ^Unit) -> mem.Allocator {
	return virtual.arena_allocator(&u.arena)
}

Ast_Ident :: struct {
	t:     Token,
	ident: string,
}

ast_new_ident :: proc(u: ^Unit, t: Token) -> ^Ast_Ident {
	ident       := ast_new(u, t, Ast_Ident)
	ident.ident  = t.content
	return ident
}

Ast_Block_Item :: union {
	^Ast_Stmt,
	^Ast_Decl,
}

Ast_Block :: xar.Array(Ast_Block_Item, 8)

Ast_Def_Function :: struct {
	t:    Token,
	name: ^Ast_Ident,
	body: Ast_Block,
}

Ast_Decl :: struct {
	t: Token,

	// Checker
	entity: ^Entity,

	variant: union {
		^Ast_Decl_Error,
		^Ast_Decl_Variable,
	},
}


Ast_Decl_Error :: struct { using decl: Ast_Decl }

ast_new_decl_error :: proc(u: ^Unit, token: Token) -> ^Ast_Decl_Error {
	return ast_new(u, token, Ast_Decl_Error)
}

Ast_Decl_Variable :: struct {
	using decl: Ast_Decl,

	name: ^Ast_Ident,
	init: ^Ast_Expr,
}

Ast_Stmt :: struct {
	t: Token,

	// NOTE: can be nil, indicates an nil stmt(;)
	variant: union {
		^Ast_Stmt_Error,
		^Ast_Stmt_Expr,
		^Ast_Stmt_Return,
		^Ast_Stmt_If,
		^Ast_Stmt_Label,
		^Ast_Stmt_Goto,
		^Ast_Stmt_Compound,
	},
}

Ast_Stmt_Error :: struct { using stmt: Ast_Stmt }

ast_new_stmt_error :: proc(u: ^Unit, token: Token) -> ^Ast_Stmt_Error {
	return ast_new(u, token, Ast_Stmt_Error)
}

Ast_Stmt_Expr :: struct {
	using stmt: Ast_Stmt,
	expr:       ^Ast_Expr,
}

Ast_Stmt_Return :: struct {
	using stmt: Ast_Stmt,

	result: ^Ast_Expr,
}

Ast_Stmt_If :: struct {
	using stmt: Ast_Stmt,

	condition: ^Ast_Expr,
	then:      ^Ast_Stmt,
	else_:     ^Ast_Stmt,
}

Ast_Stmt_Label :: struct {
	using stmt: Ast_Stmt,

	name:  ^Ast_Ident,
	inner: ^Ast_Stmt,

	// Checker
	entity: ^Entity,
}

Ast_Stmt_Goto :: struct {
	using stmt: Ast_Stmt,

	label: ^Ast_Ident,

	// Checker
	entity: ^Entity,
}

Ast_Stmt_Compound :: struct {
	using stmt: Ast_Stmt,

	block: xar.Array(Ast_Block_Item, 8),
}

Ast_Expr :: struct {
	t: Token,

	variant: union {
		^Ast_Expr_Error,
		^Ast_Expr_Constant,
		^Ast_Expr_Variable,
		^Ast_Expr_Unary,
		^Ast_Expr_Postfix,
		^Ast_Expr_Binary,
		^Ast_Expr_Assignment,
		^Ast_Expr_Conditional,
	},
}

Ast_Expr_Error :: struct { using expr: Ast_Expr }

ast_new_expr_error :: proc(u: ^Unit, token: Token) -> ^Ast_Expr_Error {
	return ast_new(u, token, Ast_Expr_Error)
}

Ast_Expr_Constant :: struct {
	using expr: Ast_Expr,

	value: int,
}

Ast_Expr_Variable :: struct {
	using expr: Ast_Expr,
	name:       ^Ast_Ident,

	// Checker
	entity: ^Entity,
}

Ast_Unary_Operator :: enum {
	Complement,
	Negate,
	Not,
	Increment,
	Decrement,
}

Ast_Expr_Unary :: struct {
	using expr: Ast_Expr,

	operator: Ast_Unary_Operator,
	inner:    ^Ast_Expr,
}

Ast_Postfix_Operator :: enum {
	Increment,
	Decrement,
}

Ast_Expr_Postfix :: struct {
	using expr: Ast_Expr,

	operator: Ast_Postfix_Operator,
	inner:    ^Ast_Expr,
}

Ast_Binary_Operator :: enum {
	Add,
	Subtract,
	Multiply,
	Divide,
	Remainder,
	Bitwise_And,
	Bitwise_Or,
	Bitwise_Xor,
	Left_Shift,
	Right_Shift,
	And,
	Or,
	Equal,
	Not_Equal,
	Less_Than,
	Less_Or_Equal,
	Greater_Than,
	Greater_Or_Equal,
}

Ast_Expr_Binary :: struct {
	using expr: Ast_Expr,

	operator: Ast_Binary_Operator,
	lhs, rhs: ^Ast_Expr,
}

Ast_Assignment_Operator :: enum {
	None,
	Add,
	Subtract,
	Multiply,
	Divide,
	Remainder,
	Bitwise_And,
	Bitwise_Or,
	Bitwise_Xor,
	Left_Shift,
	Right_Shift,
}

Ast_Expr_Assignment :: struct {
	using expr: Ast_Expr,

	operator: Ast_Assignment_Operator,
	lhs, rhs: ^Ast_Expr,
}

Ast_Expr_Conditional :: struct {
	using expr: Ast_Expr,

	condition, then, else_: ^Ast_Expr,
}

@(private="file")
pad :: proc(w: io.Writer, depth: int) {
	for i in 0..<depth {
		io.write_rune(w, ' ')
	}
}

unit_write_human_readable :: proc(u: ^Unit, w: io.Writer) {
	io.write_string(w, "Unit {\n function_definition: ")

	depth := 1
	ast_def_function_write_human_readable(u.function, w, depth)

	io.write_string(w, "}\n")
}

ast_def_function_write_human_readable :: proc(def_function: ^Ast_Def_Function, w: io.Writer, depth: int) {
	if def_function == nil {
		io.write_string(w, "<nil>")
		return
	}

	io.write_string(w, "DefFunction {\n")
	pad(w, depth+1)
	if def_function.name != nil {
		fmt.wprintf(w, "name: %v\n", def_function.name.ident)
	} else {
		io.write_string(w, "name: <invalid function>\n")
	}
	pad(w, depth+1)
	io.write_string(w, "body: {\n")
	for it := xar.iterator(&def_function.body); block_item in xar.iterate_by_val(&it) {
		pad(w, depth+2)
		switch bi in block_item {
		case ^Ast_Stmt:
			ast_stmt_write_human_readable(bi, w, depth+2)
		case ^Ast_Decl:
			ast_decl_write_human_readable(bi, w, depth+2)
		}
	}
	pad(w, depth+1)
	io.write_string(w, "}\n")
	pad(w, depth)
	io.write_string(w, "}\n")
}

ast_decl_write_human_readable :: proc(decl: ^Ast_Decl, w: io.Writer, depth: int) {
	if decl == nil {
		io.write_string(w, "<nil>\n")
		return
	}

	switch d in decl.variant {
	case ^Ast_Decl_Error:
		io.write_string(w, "<error decl>\n")
	case ^Ast_Decl_Variable:
		io.write_string(w, "Variable ")
		io.write_string(w, d.name.ident)
		io.write_string(w, " = ")
		ast_expr_write_human_readable(d.init, w, depth)
		io.write_string(w, "\n")
	}
}

ast_stmt_write_human_readable :: proc(stmt: ^Ast_Stmt, w: io.Writer, depth: int) {
	if stmt == nil {
		io.write_string(w, "<nil>\n")
		return
	}

	switch s in stmt.variant {
	case ^Ast_Stmt_Error:
		io.write_string(w, "<error stmt>\n")
	case ^Ast_Stmt_Return:
		io.write_string(w, "Return ")
		ast_expr_write_human_readable(s.result, w, depth)
		io.write_string(w, "\n")
	case ^Ast_Stmt_Expr:
		io.write_string(w, "Expr ")
		ast_expr_write_human_readable(s.expr, w, depth)
		io.write_string(w, "\n")
	case ^Ast_Stmt_If:
		io.write_string(w, "If ")
		ast_expr_write_human_readable(s.condition, w, depth)
		io.write_string(w, ":\n")
		pad(w, depth+1)
		ast_stmt_write_human_readable(s.then, w, depth+1)
		if s.else_ != nil {
			pad(w, depth)
			io.write_string(w, "Else:\n")
			pad(w, depth+1)
			ast_stmt_write_human_readable(s.else_, w, depth+1)
		}
	case nil:
		io.write_string(w, "Null\n")
	case ^Ast_Stmt_Label:
		io.write_string(w, "Label ")
		io.write_string(w, s.name.ident)
		io.write_string(w, ":\n")
			pad(w, depth+1)
		ast_stmt_write_human_readable(s.inner, w, depth+1)
	case ^Ast_Stmt_Goto:
		io.write_string(w, "Goto ")
		io.write_string(w, s.label.ident)
		io.write_string(w, "\n")
	case ^Ast_Stmt_Compound:
		io.write_string(w, "{\n")
		for it := xar.iterator(&s.block); block_item in xar.iterate_by_val(&it) {
			pad(w, depth+1)
			switch bi in block_item {
			case ^Ast_Stmt:
				ast_stmt_write_human_readable(bi, w, depth+1)
			case ^Ast_Decl:
				ast_decl_write_human_readable(bi, w, depth+1)
			}
		}
		pad(w, depth)
		io.write_string(w, "}\n")
	}
}

ast_expr_write_human_readable :: proc(expr: ^Ast_Expr, w: io.Writer, depth: int) {
	if expr == nil {
		io.write_string(w, "<nil>")
		return
	}

	switch e in expr.variant {
	case ^Ast_Expr_Error:
		io.write_string(w, "<error expr>")
	case ^Ast_Expr_Constant:
		io.write_int(w, e.value)
	case ^Ast_Expr_Unary:
		io.write_string(w, e.t.content)
		io.write_rune(w, '(')
		ast_expr_write_human_readable(e.inner, w, depth)
		io.write_rune(w, ')')
	case ^Ast_Expr_Postfix:
		io.write_rune(w, '(')
		ast_expr_write_human_readable(e.inner, w, depth)
		io.write_rune(w, ')')
		io.write_string(w, e.t.content)
	case ^Ast_Expr_Binary:
		io.write_rune(w, '(')
		ast_expr_write_human_readable(e.lhs, w, depth)
		io.write_string(w, e.t.content)
		ast_expr_write_human_readable(e.rhs, w, depth)
		io.write_rune(w, ')')
	case ^Ast_Expr_Variable:
		io.write_string(w, e.name.ident)
	case ^Ast_Expr_Assignment:
		io.write_rune(w, '(')
		ast_expr_write_human_readable(e.lhs, w, depth)
		io.write_string(w, e.t.content)
		ast_expr_write_human_readable(e.rhs, w, depth)
		io.write_rune(w, ')')
	case ^Ast_Expr_Conditional:
		io.write_rune(w, '(')
		ast_expr_write_human_readable(e.condition, w, depth)
		io.write_rune(w, '?')
		ast_expr_write_human_readable(e.then, w, depth)
		io.write_rune(w, ':')
		ast_expr_write_human_readable(e.else_, w, depth)
		io.write_rune(w, ')')
	}
}
