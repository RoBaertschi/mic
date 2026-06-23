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
			if src, src_ok := i.src.(Asm_Register); src_ok && src == .CX && i.operator in (bit_set[Asm_Binary_Operator]{.Sal, .Sar}) {
				asm_write_operand(src, w, ._1)
			} else {
				asm_write_operand(i.src, w)
			}
			io.write_string(w, ", ")

			asm_write_operand(i.dst, w)
			io.write_string(w, "\n")
		case Asm_Inst_Idiv:
			io.write_string(w, "\tidivl ")
			asm_write_operand(i.operand, w)
			io.write_string(w, "\n")
		case Asm_Inst_Allocate_Stack:
			fmt.wprintf(w, "\tsubq $%v, %%rsp\n", i)

		case Asm_Inst_Cmp:
			io.write_string(w, "\tcmpl ")
			asm_write_operand(i.lhs, w)
			io.write_string(w, ", ")
			asm_write_operand(i.rhs, w)
			io.write_string(w, "\n")
		case Asm_Inst_Jmp:
			fmt.wprintf(w, "\tjmp .L%s_%v\n", u.function.name, i.target)
		case Asm_Inst_Jmp_CC:
			fmt.wprintf(w, "\tj%s .L%s_%v\n", asm_condition_code_lower_case[i.code], u.function.name, i.target)
		case Asm_Inst_Set_CC:
			io.write_string(w, "\tset")
			io.write_string(w, asm_condition_code_lower_case[i.code])
			io.write_string(w, " ")
			asm_write_operand(i.operand, w, ._1)
			io.write_string(w, "\n")
		case Asm_Inst_Label:
			fmt.wprintf(w, ".L%s_%v:\n", u.function.name, i)
		}
	}

	io.write_string(w, "\n")
	io.write_string(w, "\t.section .note.GNU-stack,\"\",@progbits\n")
}

Asm_Operand_Size :: enum {
	_4,
	_1,
}

asm_write_operand :: proc(operand: Asm_Operand, w: io.Writer, size := Asm_Operand_Size._4) {
	switch op in operand {
	case Asm_Immediate:
		io.write_string(w, "$")
		io.write_int(w, int(op))
	case Asm_Register:
		reg_to_string := [Asm_Operand_Size][Asm_Register]string {
			._4 = {
				.AX  = "%eax",
				.CX  = "%ecx",
				.DX  = "%edx",
				.R10 = "%r10d",
				.R11 = "%r11d",
			},
			._1 = {
				.AX  = "%al",
				.CX  = "%cl",
				.DX  = "%dl",
				.R10 = "%r10b",
				.R11 = "%r11b",
			},
		}

		io.write_string(w, reg_to_string[size][op])
	case Asm_Pseudo: fmt.panicf("pseudo operand in asm write: %v", op)
	case Asm_Stack:
		io.write_int(w, int(op))
		io.write_string(w, "(%rbp)")
	}
}
