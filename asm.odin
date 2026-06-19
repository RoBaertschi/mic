package mic

import "core:io"
import "core:fmt"
import "core:mem"
import "core:container/xar"
import "core:mem/virtual"

Asm_Unit :: struct {
	arena:    virtual.Arena,
	function: ^Asm_Def_Function,
}

@require_results
asm_new :: proc(u: ^Asm_Unit, $T: typeid) -> ^T {
	ptr, err := virtual.new(&u.arena, T)
	ensure(err == nil) // TODO(robin): handle allocator error
	return ptr
}

@require_results
asm_clone_string :: proc(u: ^Asm_Unit, s: string) -> string {
	result, err := virtual.make(&u.arena, []byte, len(s))
	ensure(err == nil) // TODO(robin): handle allocator error
	copy(result, s)
	return string(result)
}

@require_results
asm_allocator :: proc(u: ^Asm_Unit) -> mem.Allocator {
	return virtual.arena_allocator(&u.arena)
}

Asm_Instructions :: xar.Array(Asm_Inst, 8)

Asm_Def_Function :: struct {
	name:         string,
	instructions: Asm_Instructions,
}

Asm_Inst :: union { Asm_Inst_Mov, Asm_Inst_Ret }

Asm_Inst_Mov :: struct {
	src, dst: Asm_Operand,
}

Asm_Inst_Ret :: struct {}

Asm_Operand :: union {
	Asm_Immediate,
	Asm_Register,
}

Asm_Register :: enum {
	Eax,
}

Asm_Immediate :: distinct int

asm_unit_write_human_readable :: proc(u: ^Asm_Unit, w: io.Writer) {
	fmt.wprintf(w, "Asm_Unit {{\n Function %q {{\n", u.function.name)

	for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
		switch i in inst {
		case Asm_Inst_Mov:
			io.write_string(w, "  mov ")
			asm_operand_write_human_readable(i.src, w)
			io.write_string(w, " -> ")
			asm_operand_write_human_readable(i.dst, w)
			io.write_string(w, "\n")
		case Asm_Inst_Ret:
			io.write_string(w, "  ret\n")
		}

	}
	io.write_string(w, " }\n}\n")
}

asm_operand_write_human_readable :: proc(operand: Asm_Operand, w: io.Writer) {
	switch op in operand {
	case Asm_Immediate:
		io.write_int(w, int(op))
	case Asm_Register:
		switch op {
		case .Eax:
			io.write_string(w, "Register.Eax")
		}
	}
}

// TODO(robin): temporary, will be removed when Tacky will be added

asm_emit :: proc(in_u: ^Unit, out_u: ^Asm_Unit) {
	function      := asm_new(out_u, Asm_Def_Function)
	function.name  = asm_clone_string(out_u, in_u.function.name.ident)
	xar.init(&function.instructions, asm_allocator(out_u))

	asm_emit_body(&function.instructions, in_u.function.body)
	out_u.function = function
}

asm_emit_body :: proc(i: ^Asm_Instructions, body: ^Ast_Stmt) {
	switch b in body.variant {
	case ^Ast_Stmt_Error: panic("Error stmt")
	case ^Ast_Stmt_Return:
		operand := asm_emit_expr(b.result, i)
		xar.push_back(
			i,
			Asm_Inst_Mov{ src = operand, dst = .Eax },
			Asm_Inst_Ret{},
		)
	}
}

asm_emit_expr :: proc(expr: ^Ast_Expr, i: ^Asm_Instructions) -> Asm_Operand {
	switch e in expr.variant {
	case nil:             panic("nil expr")
	case ^Ast_Expr_Error: panic("Error expr")
	case ^Ast_Expr_Constant:
		return Asm_Immediate(e.value)
	}
	fmt.panicf("missing case %v", expr.variant)
}
