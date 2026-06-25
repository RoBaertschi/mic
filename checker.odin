#+vet explicit-allocators
package mic

import "core:mem/virtual"

Entity_Kind :: enum {
	Invalid,
	Variable,
}

Entity :: struct {
	kind:  Entity_Kind,
	name:  ^Ast_Ident,
	decl:  ^Ast_Decl,
	scope: ^Scope,
}

entity_new :: proc(u: ^Unit, kind: Entity_Kind, name: ^Ast_Ident, decl: ^Ast_Decl) -> ^Entity {
	ptr, err := virtual.new(&u.arena, Entity)
	ensure(err == nil)
	ptr^ = {
		kind = kind,
		name = name,
		decl = decl,
	}
	decl.entity = ptr
	return ptr
}

Scope_Kind :: enum {
	// Normal scope, parent points to the higher scope
	Normal,
	// A patch to the current scope, parent points to the previous scope, but never to an actual higher scope
	Snapshot,
	// Scope for labels only
	Label,
}

Scope :: struct {
	kind:     Scope_Kind,
	parent:   ^Scope,
	elements: map[string]^Entity,
}

scope_new :: proc(u: ^Unit, parent: ^Scope) -> ^Scope {
	ptr, err := virtual.new(&u.arena, Scope)
	ensure(err == nil)
	ptr.elements = make(map[string]^Entity, allocator = virtual.arena_allocator(&u.arena))
	ptr.parent   = parent
	return ptr
}

Adressing_Mode :: enum {
	Invalid,
	RValue,
	LValue,
	// Const, // TODO: constant folding in the future
}

Operand :: struct {
	expr:        ^Ast_Expr,
	mode:        Adressing_Mode,
	// const_value: int,
}

Unit :: struct {
	arena:    virtual.Arena,
	function: ^Ast_Def_Function,
}

Checker_Error_Proc :: #type proc(data: rawptr, t: Token, format: string, args: ..any)

Checker_Info :: struct {
	errors:     int,
	error_proc: Checker_Error_Proc,
	error_data: rawptr,
}

Checker_Context :: struct {
	info: ^Checker_Info,

	scope: ^Scope,
	u:     ^Unit,
}

check_push_scope :: proc(c: ^Checker_Context) {
	c.scope = scope_new(c.u, c.scope)
}

check_pop_scope :: proc(c: ^Checker_Context) {
	c.scope = c.scope.parent
}

check_insert_scope :: proc(c: ^Checker_Context, e: ^Entity) {
	c.scope.elements[e.name.ident] = e
	e.scope                        = c.scope
}

check_lookup_scope :: proc(c: ^Checker_Context, name: string) -> (^Entity, bool) {
	s := c.scope
	for s != nil {
		entity, ok := s.elements[name]
		if ok {
			return entity, ok
		}
		s = s.parent
	}
	return nil, false
}

@(deferred_in=check_pop_scope)
check_scope_guard :: proc(c: ^Checker_Context) {
	check_push_scope(c)
}

check_error :: proc(c: ^Checker_Context, t: Token, format: string, args: ..any) {
	c.info.errors += 1
	if c.info.error_proc != nil {
		c.info.error_proc(c.info.error_data, t, format, ..args)
	}
}

check_unit :: proc(u: ^Unit, info: ^Checker_Info) {
	c := Checker_Context {
		info = info,
		u    = u,
	}

	// TODO: collect globals
	// TODO: queue globals
	// TODO: run thread pool
	check_def_function(&c, u.function)
}
