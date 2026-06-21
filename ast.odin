package mic

import "core:fmt"
import "core:io"
import "core:mem"
import "base:intrinsics"
import "core:mem/virtual"

Unit :: struct {
	arena:    virtual.Arena,
	function: ^Ast_Def_Function,
}

@require_results
ast_new :: proc(u: ^Unit, t: Token, $T: typeid) -> ^T {
	ptr, err := virtual.new(&u.arena, T)
	ensure(err == nil) // TODO(robin): handle allocator error
	ptr.t = t
	when intrinsics.type_has_field(T, "variant") {
		ptr.variant = ptr
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

Ast_Def_Function :: struct {
	t:    Token,
	name: ^Ast_Ident,
	body: ^Ast_Stmt,
}

Ast_Stmt :: struct {
	t: Token,

	variant: union { ^Ast_Stmt_Error, ^Ast_Stmt_Return },
}

Ast_Stmt_Error :: struct { using stmt: Ast_Stmt }

ast_new_stmt_error :: proc(u: ^Unit, token: Token) -> ^Ast_Stmt_Error {
	return ast_new(u, token, Ast_Stmt_Error)
}

Ast_Stmt_Return :: struct {
	using stmt: Ast_Stmt,

	result: ^Ast_Expr,
}

Ast_Expr :: struct {
	t: Token,

	variant: union { ^Ast_Expr_Error, ^Ast_Expr_Constant, ^Ast_Expr_Unary },
}

Ast_Expr_Error :: struct { using expr: Ast_Expr }

ast_new_expr_error :: proc(u: ^Unit, token: Token) -> ^Ast_Expr_Error {
	return ast_new(u, token, Ast_Expr_Error)
}

Ast_Expr_Constant :: struct {
	using expr: Ast_Expr,

	value: int,
}

Ast_Unary_Operator :: enum {
	Complement,
	Negate,
}

Ast_Expr_Unary :: struct {
	using expr: Ast_Expr,

	operator: Ast_Unary_Operator,
	inner:    ^Ast_Expr,
}

@(private="file")
pad :: proc(w: io.Writer, depth: int) {
	for i in 0..<depth {
		io.write_rune(w, ' ')
	}
}

unit_write_human_readable :: proc(u: ^Unit, w: io.Writer) {
	io.write_string(w, "Unit {\n function_definition: ")

	depth := 2
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
	io.write_string(w, "body: ")
	if def_function.body != nil {
		ast_stmt_write_human_readable(def_function.body, w, depth+1)
		pad(w, depth)
		io.write_string(w, "}\n")
	} else {
		io.write_string(w, "<nil>\n")
		pad(w, depth)
		io.write_string(w, "}\n")
	}
}

ast_stmt_write_human_readable :: proc(stmt: ^Ast_Stmt, w: io.Writer, depth: int) {
	if stmt == nil {
		io.write_string(w, "<nil>")
		return
	}

	switch s in stmt.variant {
	case ^Ast_Stmt_Error:
		io.write_string(w, "<error stmt>\n")
	case ^Ast_Stmt_Return:
		io.write_string(w, "Return ")
		ast_expr_write_human_readable(s.result, w, depth)
		io.write_string(w, "\n")
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
		switch e.operator {
		case .Complement:
			io.write_rune(w, '~')
		case .Negate:
			io.write_rune(w, '-')
		}
		io.write_rune(w, '(')
		ast_expr_write_human_readable(e.inner, w, depth)
		io.write_rune(w, ')')
	}
}
