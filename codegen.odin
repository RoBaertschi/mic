package mic

import "core:fmt"
import "core:container/xar"

codegen :: proc(u: ^Tacky_Unit, out_u: ^Asm_Unit) {
	function       := asm_new(out_u, Asm_Def_Function)
	function.name   = asm_clone_string(out_u, u.function.name)
	out_u.function  = function

	insts :: proc(function: ^Asm_Def_Function, instructions: ..Asm_Inst) {
		xar.append(&function.instructions, ..instructions)
	}

	convert_value_to_operand :: proc(function: ^Asm_Def_Function, operand: Tacky_Value) -> Asm_Operand {
		switch op in operand {
		case Tacky_Value_Constant:
			return Asm_Immediate(op)
		case Tacky_Value_Variable:
			pseudo := Asm_Pseudo(op)
			function.largest_pseudo = max(function.largest_pseudo, pseudo)
			return pseudo
		}
		fmt.panicf("invalid operand %v", operand)
	}

	for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
		switch i in inst {
		case Tacky_Inst_Return:
			insts(
				function,
				Asm_Inst_Mov {
					src = convert_value_to_operand(function, Tacky_Value(i)),
					dst = .AX,
				},
				Asm_Inst_Ret {},
			)
		case Tacky_Inst_Unary:
			dst := convert_value_to_operand(function, i.dst)

			insts(
				function,
				Asm_Inst_Mov {
					src = convert_value_to_operand(function, i.src),
					dst = dst,
				},
				Asm_Inst_Unary {
					operand  = dst,
					operator = tacky_unary_operator_to_asm_unary_operator(i.operator),
				},
			)
		}
	}
}
