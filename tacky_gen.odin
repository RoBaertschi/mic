package mic

import "core:fmt"
import "core:container/xar"

tacky_gen :: proc(u: ^Unit, out_u: ^Tacky_Unit) {
	function      := tacky_new(out_u, Tacky_Def_Function)
	function.name  = tacky_clone_string(out_u, u.function.name.ident)
	out_u.function = function

	xar.init(&function.instructions, tacky_allocator(out_u))
	tacky_gen_body(out_u, function, u.function.body)
}

tacky_gen_instructions :: proc(function: ^Tacky_Def_Function, insts: ..Tacky_Inst) {
	xar.append(&function.instructions, ..insts)
}

tacky_gen_make_temporary :: proc(function: ^Tacky_Def_Function) -> (var: Tacky_Value_Variable) {
	var              = function.locals
	function.locals += 1
	return
}

tacky_gen_body :: proc(u: ^Tacky_Unit, function: ^Tacky_Def_Function, body: ^Ast_Stmt) {
	switch b in body.variant {
	case nil:              panic("nil stmt")
	case ^Ast_Stmt_Error:  panic("Error stmt")
	case ^Ast_Stmt_Return:
		value := tacky_gen_expr(u, function, b.result)
		tacky_gen_instructions(
			function,
			Tacky_Inst_Return(value),
		)
	}
}

tacky_gen_expr :: proc(u: ^Tacky_Unit, function: ^Tacky_Def_Function, expr: ^Ast_Expr) -> Tacky_Value {
	switch e in expr.variant {
	case nil:             panic("nil expr")
	case ^Ast_Expr_Error: panic("error expr")
	case ^Ast_Expr_Constant:
		return Tacky_Value_Constant(e.value)
	case ^Ast_Expr_Unary:
		src := tacky_gen_expr(u, function, e.inner)
		dst := tacky_gen_make_temporary(function)
		tacky_gen_instructions(
			function,
			Tacky_Inst_Unary {
				operator = Tacky_Unary_Operator(e.operator),
				dst      = dst,
				src      = src,
			},
		)
		return dst
	}
	fmt.panicf("invalid expr %v", expr.variant)
}
