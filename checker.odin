#+vet explicit-allocators
package mic

import "core:container/xar"
import "core:container/intrusive/list"
import "core:mem/virtual"

Entity_Kind :: enum {
	Invalid,
	Variable,
	Label,
}

Entity :: struct {
	kind:  Entity_Kind,
	name:  ^Ast_Ident,
	decl:  ^Ast_Decl,
	stmt:  ^Ast_Stmt_Label, // For label
	scope: ^Scope,

	// Label data
	unresolved_node: list.Node,
}

entity_new_decl :: proc(u: ^Unit, kind: Entity_Kind, name: ^Ast_Ident, decl: ^Ast_Decl) -> ^Entity {
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

entity_new :: proc{
	entity_new_decl,
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
	Const, // TODO: constant folding in the future
}

Const_Value :: union {
	int,
}

Operand :: struct {
	expr:        ^Ast_Expr,
	mode:        Adressing_Mode,
	const_value: Const_Value,
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

	// Labels
	label_scope:       ^Scope,
	unresolved_labels: list.List,

	// Switch
	switch_current_cases:   xar.Array(^Ast_Stmt_Case, 8),
	switch_current_default: ^Ast_Stmt_Default,

	scope: ^Scope,
	u:     ^Unit,
}

Check_Stmt_Flag :: enum {
	Break_Allowed,
	Continue_Allowed,
	Case_Allowed,
}

Check_Stmt_Flags :: bit_set[Check_Stmt_Flag]

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

@(deferred_in=check_pop_scope)
check_scope_guard :: proc(c: ^Checker_Context) {
	check_push_scope(c)
}

check_lookup_scope :: proc(c: ^Checker_Context, name: string) -> (^Entity, bool) {
	s := c.scope
	for s != nil {
		assert(s.kind != .Label)

		entity, ok := s.elements[name]
		if ok {
			return entity, ok
		}
		s = s.parent
	}
	return nil, false
}

check_lookup_current_scope :: proc(c: ^Checker_Context, name: string) -> (^Entity, bool) {
	s := c.scope
	for s != nil && s.kind == .Snapshot {
		assert(s.kind != .Label)

		entity, ok := s.elements[name]
		if ok {
			return entity, ok
		}
		s = s.parent
	}

	if s != nil && s.kind == .Normal {
		entity, ok := s.elements[name]
		if ok {
			return entity, ok
		}
	}

	return nil, false
}

check_lookup_label :: proc(c: ^Checker_Context, name: ^Ast_Ident) -> (^Entity, bool) {
	assert(c.label_scope.kind == .Label)
	return c.label_scope.elements[name.ident]
}

check_insert_label :: proc(c: ^Checker_Context, e: ^Entity) {
	c.label_scope.elements[e.name.ident] = e
}

check_resolve_label :: proc(c: ^Checker_Context, e: ^Entity, stmt: ^Ast_Stmt_Label) {
	assert(e.kind == .Label)
	assert(e.decl == nil)
	e.stmt      = stmt
	stmt.entity = e

	list.remove(&c.unresolved_labels, &e.unresolved_node)
	e.unresolved_node = {} // Zero just in case
}

check_new_label :: proc(c: ^Checker_Context, stmt: ^Ast_Stmt_Label) -> ^Entity {
	ptr, err := virtual.new(&c.u.arena, Entity)
	ensure(err == nil)
	ptr^ = {
		kind = .Label,
		name = stmt.name,
		stmt = stmt,
	}
	stmt.entity = ptr

	check_insert_label(c, ptr)
	return ptr
}

check_new_unresolved_label :: proc(c: ^Checker_Context, stmt: ^Ast_Stmt_Goto) -> ^Entity {
	ptr, err := virtual.new(&c.u.arena, Entity)
	ensure(err == nil)
	ptr^ = {
		kind = .Label,
		name = stmt.label,
	}
	stmt.entity = ptr

	list.push_back(&c.unresolved_labels, &ptr.unresolved_node)

	check_insert_label(c, ptr)
	return ptr
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
