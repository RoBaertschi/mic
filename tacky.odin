package mic

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

Tacky_Def_Function :: struct {}
