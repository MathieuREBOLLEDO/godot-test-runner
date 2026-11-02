extends Logger

## Relève les erreurs du moteur et des scripts (push_error, donc Log.err,
## erreurs de script, de shader) pendant les tests. Les avertissements ne
## comptent pas. Branché par le runner avec OS.add_logger().
## Peut être appelé depuis un autre thread : protégé par un Mutex.

var _errors: PackedStringArray = []
var _mutex: Mutex = Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text: String = rationale if not rationale.is_empty() else code
	_mutex.lock()
	_errors.append("%s  (%s:%d in %s)" % [text.strip_edges(), file.get_file(), line, function])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


## Rend les erreurs relevées depuis le dernier appel et les oublie.
func take() -> PackedStringArray:
	_mutex.lock()
	var errors: PackedStringArray = _errors
	_errors = []
	_mutex.unlock()
	return errors
