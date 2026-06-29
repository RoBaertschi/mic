#+vet explicit-allocators
package mic

import "core:container/xar"

xar_last :: proc(x: $X/^xar.Array($T, $SHIFT)) -> T {
	return xar.array_get(x, xar.len(x^) - 1)
}
