package mic

import "core:fmt"
import "core:io"
import "core:container/xar"
import "core:mem"
import "core:mem/virtual"

Tacky_Unit :: struct {
	arena:    virtual.Arena,
	function: ^Tacky_Def_Function,
}

@require_results
tacky_new :: proc(u: ^Tacky_Unit, $T: typeid) -> ^T {
	ptr, err := virtual.new(&u.arena, T)
	ensure(err == nil) // TODO(robin): handle allocator error
	return ptr
}

@require_results
tacky_clone_string :: proc(u: ^Tacky_Unit, s: string) -> string {
	result, err := virtual.make(&u.arena, []byte, len(s))
	ensure(err == nil) // TODO(robin): handle allocator error
	copy(result, s)
	return string(result)
}

@require_results
tacky_allocator :: proc(u: ^Tacky_Unit) -> mem.Allocator {
	return virtual.arena_allocator(&u.arena)
}

Tacky_Instructions :: xar.Array(Tacky_Inst, 8)

Tacky_Def_Function :: struct {
	name:         string,
	locals:       Tacky_Value_Variable,
	instructions: Tacky_Instructions,
}

Tacky_Inst :: union {
	Tacky_Inst_Return,
	Tacky_Inst_Unary,
}

Tacky_Inst_Return :: distinct Tacky_Value
Tacky_Inst_Unary  :: struct {
	operator:       Tacky_Unary_Operator,
	src, dst: Tacky_Value,
}

Tacky_Unary_Operator :: distinct Ast_Unary_Operator

Tacky_Value :: union { Tacky_Value_Constant, Tacky_Value_Variable }

Tacky_Value_Constant :: distinct int
Tacky_Value_Variable :: distinct u32

tacky_unit_write_human_readable :: proc(u: ^Tacky_Unit, w: io.Writer) {
	fmt.wprintf(w, "Tacky_Unit {{\n Function %q {{\n", u.function.name)

	for it := xar.iterator(&u.function.instructions); inst in xar.iterate_by_val(&it) {
		switch i in inst {
		case Tacky_Inst_Unary:
			io.write_string(w, "  ")
			tacky_value_write_human_readable(i.dst, w)
			fmt.wprintf(w, " = unary.%v ", i.operator)
			tacky_value_write_human_readable(i.src, w)
			io.write_string(w, "\n")
		case Tacky_Inst_Return:
			io.write_string(w, "  return ")
			tacky_value_write_human_readable(Tacky_Value(i), w)
			io.write_string(w, "\n")
		}
	}

	io.write_string(w, " }\n}\n")
}

tacky_value_write_human_readable :: proc(value: Tacky_Value, w: io.Writer) {
	switch v in value {
	case Tacky_Value_Constant:
		fmt.wprintf(w, "$%v", v)
	case Tacky_Value_Variable:
		fmt.wprintf(w, "%%%v", v)
	}
}
