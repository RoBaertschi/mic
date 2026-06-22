package mic

import "core:io"
import "core:fmt"
import "core:container/xar"

// asm_write :: proc(u: ^Asm_Unit, w: io.Writer) {
// 	fmt.wprintf(w, "\t.globl {0}\n{0}:\n", u.function.name)
//
// 	for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
// 		switch i in inst {
// 		case Asm_Inst_Mov:
// 			io.write_string(w, "\tmovl ")
// 			asm_write_operand(i.src, w)
// 			io.write_string(w, ", ")
// 			asm_write_operand(i.dst, w)
// 			io.write_string(w, "\n")
// 		case Asm_Inst_Ret:
// 			io.write_string(w, "\tret\n")
// 		}
// 	}
//
// 	io.write_string(w, "\n")
// 	io.write_string(w, "\t.section .note.GNU-stack,\"\",@progbits\n")
// }
//
// asm_write_operand :: proc(operand: Asm_Operand, w: io.Writer) {
// 	switch op in operand {
// 	case Asm_Immediate:
// 		io.write_string(w, "$")
// 		io.write_int(w, int(op))
// 	case Asm_Register:
// 		switch op {
// 		case .AX:
// 			io.write_string(w, "%eax")
// 		}
// 	}
// }
