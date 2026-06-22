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
	name:           string,
	largest_pseudo: Asm_Pseudo,
	instructions:   Asm_Instructions,
}

Asm_Inst :: union { Asm_Inst_Mov, Asm_Inst_Unary, Asm_Inst_Allocate_Stack, Asm_Inst_Ret }

Asm_Inst_Mov :: struct {
	src, dst: Asm_Operand,
}

Asm_Inst_Unary :: struct {
	operator: Asm_Unary_Operator,
	operand:  Asm_Operand,
}

Asm_Unary_Operator :: enum {
	Neg,
	Not,
}

tacky_unary_operator_to_asm_unary_operator :: proc(op: Tacky_Unary_Operator) -> Asm_Unary_Operator {
	switch op {
	case .Complement:
		return .Not
	case .Negate:
		return .Neg
	}
	fmt.panicf("invalid operator in tacky_unary_operator_to_asm_unary_operator: %v", op)
}

Asm_Inst_Allocate_Stack :: distinct int

Asm_Inst_Ret :: struct {}

Asm_Operand :: union {
	Asm_Immediate,
	Asm_Register,
	Asm_Pseudo,
	Asm_Stack,
}

Asm_Register :: enum {
	AX,
	R10,
}

Asm_Immediate :: distinct int
Asm_Pseudo    :: distinct int
Asm_Stack     :: distinct int

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
		case Asm_Inst_Unary:
			fmt.wprintf(w, "  unary.%v ", i.operator)
			asm_operand_write_human_readable(i.operand, w)
			io.write_string(w, "\n")
		case Asm_Inst_Allocate_Stack:
			fmt.wprintf(w, "  allocate_stack %v\n", i)
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
		fmt.wprintf(w, "Register.%v", op)
	case Asm_Pseudo:
		fmt.wprintf(w, "%%%v", op)
	case Asm_Stack:
		fmt.wprintf(w, "Stack(%v)", op)
	}
}
