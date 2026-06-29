#+vet explicit-allocators
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
	pseudo_count: int,
	instructions: Asm_Instructions,
}

Asm_Inst :: union {
	Asm_Inst_Mov,
	Asm_Inst_Unary,
	Asm_Inst_Binary,
	Asm_Inst_Idiv,
	Asm_Inst_Cmp,
	Asm_Inst_Jmp,
	Asm_Inst_Jmp_CC,
	Asm_Inst_Set_CC,
	Asm_Inst_Label,
	Asm_Inst_Allocate_Stack,
	Asm_Inst_Plain,
}

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
	case .Complement: return .Not
	case .Negate:     return .Neg
	case .Not:        fmt.panicf("unsupported unary operator in tacky_unary_operator_to_asm_unary_operator: %v", op)
	}
	fmt.panicf("invalid operator in tacky_unary_operator_to_asm_unary_operator: %v", op)
}

Asm_Inst_Binary :: struct {
	operator: Asm_Binary_Operator,
	src, dst: Asm_Operand,
}

Asm_Binary_Operator :: enum {
	Add,
	Sub,
	Mult,
	And,
	Or,
	Xor,
	Sal,
	Sar,
}

tacky_binary_operator_to_asm_unary_operator :: proc(op: Tacky_Binary_Operator) -> Asm_Binary_Operator {
	#partial switch op {
	case .Add:         return .Add
	case .Subtract:    return .Sub
	case .Multiply:    return .Mult
	case .Bitwise_And: return .And
	case .Bitwise_Or:  return .Or
	case .Bitwise_Xor: return .Xor
	case .Left_Shift:  return .Sal
	case .Right_Shift: return .Sar
	}
	fmt.panicf("invalid operator in tacky_binary_operator_to_asm_unary_operator: %v", op)
}

Asm_Inst_Idiv :: struct {
	operand: Asm_Operand,
}

Asm_Inst_Cmp :: struct {
	lhs, rhs: Asm_Operand,
}

Asm_Label :: distinct Tacky_Label

Asm_Inst_Jmp :: struct {
	target: Asm_Label,
}

Asm_Condition_Code :: enum {
	E,
	NE,
	G,
	GE,
	L,
	LE,
}

asm_condition_code_lower_case := [Asm_Condition_Code]string {
	.E  = "e",
	.NE = "ne",
	.G  = "g",
	.GE = "ge",
	.L  = "l",
	.LE = "le",
}

Asm_Inst_Jmp_CC :: struct {
	code:   Asm_Condition_Code,
	target: Asm_Label,
}

Asm_Inst_Set_CC :: struct {
	code:    Asm_Condition_Code,
	operand: Asm_Operand,
}

Asm_Inst_Label :: Asm_Label

Asm_Inst_Allocate_Stack :: distinct int

Asm_Inst_Plain :: enum {
	Ret,
	Cdq,
}

asm_inst_plain_string := [Asm_Inst_Plain]string{
	.Ret = "ret",
	.Cdq = "cdq",
}

Asm_Operand :: union {
	Asm_Immediate,
	Asm_Register,
	Asm_Pseudo,
	Asm_Stack,
}

Asm_Register :: enum {
	AX,
	CX,
	DX,
	R10,
	R11,
}

Asm_Immediate :: distinct int
Asm_Pseudo    :: distinct Tacky_Value_Variable
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
		case Asm_Inst_Binary:
			fmt.wprintf(w, "  binary.%v ", i.operator)
			asm_operand_write_human_readable(i.dst, w)
			io.write_string(w, ", ")
			asm_operand_write_human_readable(i.src, w)
			io.write_string(w, " -> ")
			asm_operand_write_human_readable(i.dst, w)
			io.write_string(w, "\n")
		case Asm_Inst_Idiv:
			io.write_string(w, "  idiv ")
			asm_operand_write_human_readable(i.operand, w)
			io.write_string(w, "\n")
		case Asm_Inst_Allocate_Stack:
			fmt.wprintf(w, "  allocate_stack %v\n", i)
		case Asm_Inst_Plain:
			io.write_string(w, "  ")
			io.write_string(w, asm_inst_plain_string[i])
			io.write_string(w, "\n")
		case Asm_Inst_Cmp:
			io.write_string(w, "  cmp ")
			asm_operand_write_human_readable(i.lhs, w)
			io.write_string(w, ", ")
			asm_operand_write_human_readable(i.rhs, w)
			io.write_string(w, "\n")
		case Asm_Inst_Jmp:
			io.write_string(w, "  jmp @")
			io.write_u64(w, u64(i.target))
			io.write_string(w, "\n")
		case Asm_Inst_Jmp_CC:
			io.write_string(w, "  j")
			io.write_string(w, asm_condition_code_lower_case[i.code])
			io.write_string(w, " @")
			io.write_u64(w, u64(i.target))
			io.write_string(w, "\n")
		case Asm_Inst_Set_CC:
			io.write_string(w, "  set")
			io.write_string(w, asm_condition_code_lower_case[i.code])
			io.write_string(w, " ")
			asm_operand_write_human_readable(i.operand, w)
			io.write_string(w, "\n")
		case Asm_Label:
			io.write_string(w, "  @")
			io.write_u64(w, u64(i))
			io.write_string(w, ":\n")
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
