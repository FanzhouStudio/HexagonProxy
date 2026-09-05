class_name ProxyRecovery
extends Node

## Mihomo 异常退出后的有限退避恢复

signal recovery_requested(attempt: int)
signal recovery_exhausted

const DELAYS := [1.0, 3.0, 8.0]

var attempts := 0
var pending := false
var _generation := 0

func schedule() -> bool:
	if pending:
		return false
	if attempts >= DELAYS.size():
		recovery_exhausted.emit()
		return false
	pending = true
	attempts += 1
	var attempt := attempts
	var generation := _generation
	var delay_seconds: float = DELAYS[attempt - 1]
	await get_tree().create_timer(delay_seconds).timeout
	if generation != _generation:
		return false
	pending = false
	recovery_requested.emit(attempt)
	return true

func reset() -> void:
	_generation += 1
	attempts = 0
	pending = false
func cancel() -> void:
	_generation += 1
	pending = false

func retry_count() -> int:
	return attempts
