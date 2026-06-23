package mic

import "core:io"
import "core:fmt"
import "core:container/xar"

asm_write :: proc(u: ^Asm_Unit, w: io.Writer) {
	fmt.wprintf(w, "\t.globl {0}\n{0}:\n\tpushq %%rbp\n\tmovq %%rsp, %%rbp\n", u.function.name)

	for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
		switch i in inst {
		case Asm_Inst_Mov:
			io.write_string(w, "\tmovl ")
			asm_write_operand(i.src, w)
			io.write_string(w, ", ")
			asm_write_operand(i.dst, w)
			io.write_string(w, "\n")
		case Asm_Inst_Plain:
			switch i {
			case .Ret:
				io.write_string(w, "\tmovq %rbp, %rsp\n\tpopq %rbp\n\tret\n")
			case .Cdq:
				io.write_string(w, "\tcdq\n")
			}
		case Asm_Inst_Unary:
			instruction_text := [Asm_Unary_Operator]string{
				.Neg = "\tnegl ",
				.Not = "\tnotl ",
			}

			io.write_string(w, instruction_text[i.operator])
			asm_write_operand(i.operand, w)
			io.write_string(w, "\n")
		case Asm_Inst_Binary:
			instruction_text := [Asm_Binary_Operator]string{
				.Add  = "\taddl ",
				.Sub  = "\tsubl ",
				.Mult = "\timull ",
				.And  = "\tandl ",
				.Or   = "\torl ",
				.Xor  = "\txorl ",
				.Sal  = "\tsall ",
				.Sar  = "\tsarl ",
			}

			io.write_string(w, instruction_text[i.operator])
			asm_write_operand(i.src, w)
			io.write_string(w, ", ")
			asm_write_operand(i.dst, w)
			io.write_string(w, "\n")
		case Asm_Inst_Idiv:
			io.write_string(w, "\tidivl ")
			asm_write_operand(i.operand, w)
			io.write_string(w, "\n")
		case Asm_Inst_Allocate_Stack:
			fmt.wprintf(w, "\tsubq $%v, %%rsp\n", i)
		}
	}

	io.write_string(w, "\n")
	io.write_string(w, "\t.section .note.GNU-stack,\"\",@progbits\n")
}

asm_write_operand :: proc(operand: Asm_Operand, w: io.Writer) {
	switch op in operand {
	case Asm_Immediate:
		io.write_string(w, "$")
		io.write_int(w, int(op))
	case Asm_Register:
		switch op {
		case .AX:
			io.write_string(w, "%eax")
		case .DX:
			io.write_string(w, "%edx")
		case .R10:
			io.write_string(w, "%r10d")
		case .R11:
			io.write_string(w, "%r11d")
		}
	case Asm_Pseudo: fmt.panicf("pseudo operand in asm write: %v", op)
	case Asm_Stack:
		io.write_int(w, int(op))
		io.write_string(w, "(%rbp)")
	}
}
