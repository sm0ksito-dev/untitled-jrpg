#region ENUMS
enum EVENT_TYPE {
    // Combate y Progresión RPG
    LEVEL_UP,
    ENEMY_DEFEATED,

    // Inventario y Economía
    ITEM_OBTAINED,
    ITEM_REMOVED,

    // Quests
    QUEST_ACCEPTED,
    QUEST_UPDATED,
    QUEST_FAILED,
    QUEST_COMPLETED
	
}
#endregion

#region CONSTRUCTOR: EventBus
/// @desc Bus de eventos desacoplado O(N) con soporte para re-entrancia, referencias débiles y compactación automática.
function EventBus() constructor {

    // {Struct} Mapa de clave de evento -> Struct de canal { subscribers, emit_depth, is_dirty }.
    listeners = {};

    #region PUBLIC API

    /// @desc Suscribe una instancia o struct a un evento específico.
    /// @note Evita closures que capturen variables locales 'var'; usa métodos de struct o funciones de script.
    /// @note No uses instance_deactivate_* sobre instancias suscritas (instance_exists() las considerará destruidas).
    /// @note Si un obj_* posee sub-structs suscritos, llama a unsubscribe_all(sub_struct) en el evento Clean Up del objeto
    ///       para evitar ejecuciones residuales antes de que actúe el Garbage Collector incremental.
    /// @param {Enum.EVENT_TYPE} _event Identificador del evento a escuchar.
    /// @param {Id.Instance, Struct} _owner Dueño de la suscripción (controla ciclo de vida y contexto self).
    /// @param {Function} _callback Función o método a ejecutar cuando se emita el evento.
    static subscribe = function(_event, _owner, _callback) {
        var _event_key = __get_event_key(_event);
        if (is_undefined(_event_key)) return;

        // 1. Validación y extracción segura del índice de función (evita referencias fuertes ocultas al dueño)
        if (!is_callable(_callback)) {
            show_debug_message($"[EventBus] Error en subscribe: '_callback' no es invocable para el evento '{_event_key}'.");
            return;
        }

        var _raw_callback = is_method(_callback) ? method_get_index(_callback) : _callback;
        if (is_undefined(_raw_callback) || _raw_callback == -1) {
            show_debug_message($"[EventBus] Error en subscribe: no se pudo resolver el índice de '_callback' en '{_event_key}'.");
            return;
        }

        // 2. Validación estricta y encapsulamiento del dueño (_owner)
        var _is_instance = false;
        var _stored_owner = undefined;

        if (is_struct(_owner)) {
            _is_instance = false;
            _stored_owner = weak_ref_create(_owner);
        } else if (__is_valid_instance_ref(_owner)) {
            _is_instance = true;
            _stored_owner = _owner;
        } else {
            show_debug_message($"[EventBus] Error en subscribe: '_owner' debe ser un struct válido o una referencia de instancia activa.");
            return;
        }

        // 3. Obtener o inicializar el canal del evento
        if (!variable_struct_exists(listeners, _event_key)) {
            listeners[$ _event_key] = {
                subscribers: [],
                emit_depth:  0,
                is_dirty:    false
            };
        }

        var _channel = listeners[$ _event_key];
        var _subscribers = _channel.subscribers;
        var _count = array_length(_subscribers);

        // 4. Garantía de idempotencia y reciclaje seguro de tombstones
        for (var _i = 0; _i < _count; _i++) {
            var _sub = _subscribers[_i];

            if (!__is_sub_alive(_sub)) {
                if (_sub.is_active) {
                    _sub.is_active = false;
                    _channel.is_dirty = true;
                }
                continue;
            }

            var _current_owner = _sub.is_instance ? _sub.owner : _sub.owner.ref;
            if (_current_owner == _owner && _sub.callback == _raw_callback) {
                if (_sub.is_active) {
                    show_debug_message($"[EventBus] Aviso en subscribe: '_owner' ya está suscrito con este callback al evento '{_event_key}'.");
                    return;
                }

                // Solo reciclar in-place si el canal no está emitiendo; de lo contrario, hacer push al final
                if (_channel.emit_depth == 0) {
                    _sub.is_active = true;
                    if (_channel.is_dirty) {
                        __compact_channel(_event_key);
                    }
                    return;
                }
            }
        }

        // 5. Registro de nueva suscripción al final del canal
        array_push(_subscribers, {
            is_instance: _is_instance,
            owner:       _stored_owner,
            callback:    _raw_callback,
            is_active:   true
        });

        if (_channel.emit_depth == 0 && _channel.is_dirty) {
            __compact_channel(_event_key);
        }
    };

    /// @desc Elimina una o todas las suscripciones de un oyente para un evento dado.
    /// @param {Enum.EVENT_TYPE} _event Identificador del evento.
    /// @param {Id.Instance, Struct} _owner Dueño que desea desuscribirse.
    /// @param {Function} [_callback] Función específica a remover. Si se omite (2 args), remueve todas las del dueño.
    static unsubscribe = function(_event, _owner, _callback = undefined) {
        var _event_key = __get_event_key(_event);
        if (is_undefined(_event_key)) return;

        var _target_callback = undefined;

        // Distinguir omisión intencional (2 args) de un 'undefined' accidental pasado explícitamente (3 args)
        if (argument_count >= 3) {
            if (!is_callable(_callback)) {
                show_debug_message($"[EventBus] Error en unsubscribe: se recibió un '_callback' inválido o undefined en '{_event_key}'.");
                return;
            }
            _target_callback = is_method(_callback) ? method_get_index(_callback) : _callback;
        }

        __remove_from_key(_event_key, _owner, _target_callback);
    };

    /// @desc Desuscribe a un oyente de absolutamente todos los eventos registrados.
    /// @param {Id.Instance, Struct} _owner Instancia o struct a limpiar del bus.
    static unsubscribe_all = function(_owner) {
        if (is_undefined(_owner)) return;

        var _event_keys = variable_struct_get_names(listeners);
        var _key_count = array_length(_event_keys);

        for (var _i = 0; _i < _key_count; _i++) {
            __remove_from_key(_event_keys[_i], _owner);
        }
    };

    /// @desc Dispara un evento notificando en O(N) a todos sus oyentes vivos con un struct payload de solo lectura.
    /// @param {Enum.EVENT_TYPE} _event Identificador del evento a disparar.
    /// @param {Struct} [_data] Datos asociados al evento (debe ser un struct; los listeners deben tratarlo como inmutable).
    static emit = function(_event, _data = {}) {
        var _event_key = __get_event_key(_event);
        if (is_undefined(_event_key)) return;

        if (!is_struct(_data)) {
            show_debug_message($"[EventBus] Error en emit: '_data' debe ser un struct en '{_event_key}' (recibido: {typeof(_data)}).");
            return;
        }

        if (!variable_struct_exists(listeners, _event_key)) return;

        var _channel = listeners[$ _event_key];
        var _subscribers = _channel.subscribers;

        // Congelamos el límite superior: suscripciones añadidas durante este emit() correrán en el siguiente
        var _initial_count = array_length(_subscribers);

        _channel.emit_depth++;

        try {
            for (var _i = 0; _i < _initial_count; _i++) {
                var _sub = _subscribers[_i];

                // Salto O(1) si fue desuscrito durante este mismo ciclo de emisión
                if (!_sub.is_active) continue;

                // Verificación de ciclo de vida del dueño
                if (!__is_sub_alive(_sub)) {
                    _sub.is_active = false;
                    _channel.is_dirty = true;
                    continue;
                }

                var _target_owner = _sub.is_instance ? _sub.owner : _sub.owner.ref;
                method(_target_owner, _sub.callback)(_data);
            }
        } finally {
            _channel.emit_depth--;

            // Compactación única en O(N) al cerrar la emisión más externa
            if (_channel.emit_depth == 0 && _channel.is_dirty) {
                __compact_channel(_event_key);
            }
        }
    };

    /// @desc Limpia todas las suscripciones del bus de forma segura, incluso si hay emisiones en curso.
    static clear = function() {
        var _event_keys = variable_struct_get_names(listeners);
        var _key_count = array_length(_event_keys);

        for (var _i = 0; _i < _key_count; _i++) {
            var _event_key = _event_keys[_i];
            var _channel = listeners[$ _event_key];
            var _subscribers = _channel.subscribers;
            var _count = array_length(_subscribers);

            for (var _j = 0; _j < _count; _j++) {
                _subscribers[_j].is_active = false;
            }

            _channel.is_dirty = true;

            if (_channel.emit_depth == 0) {
                __compact_channel(_event_key);
            }
        }
    };

    /// @desc Devuelve la cantidad de oyentes activos y vivos para un evento (útil para debug y tests).
    /// @param {Enum.EVENT_TYPE} _event Identificador del evento.
    /// @return {Real}
    static get_listener_count = function(_event) {
        var _event_key = __get_event_key(_event);
        if (is_undefined(_event_key) || !variable_struct_exists(listeners, _event_key)) return 0;

        var _subscribers = listeners[$ _event_key].subscribers;
        var _count = array_length(_subscribers);
        var _alive_count = 0;

        for (var _i = 0; _i < _count; _i++) {
            var _sub = _subscribers[_i];
            if (_sub.is_active && __is_sub_alive(_sub)) {
                _alive_count++;
            }
        }

        return _alive_count;
    };

    #endregion

    #region PRIVATE HELPERS

    /// @desc Normaliza el identificador del evento a clave string interna.
    /// @param {Enum.EVENT_TYPE, String, Real} _event Identificador del evento.
    /// @return {String, Undefined}
    static __get_event_key = function(_event) {
        if (is_undefined(_event)) {
            show_debug_message("[EventBus] Error: se recibió un '_event' undefined.");
            return undefined;
        }
        return string(_event);
    };

    /// @desc Valida de forma segura que el valor sea una referencia de instancia activa y no un asset ni ds_*.
    /// @param {Any} _candidate Valor a verificar.
    /// @return {Bool}
    static __is_valid_instance_ref = function(_candidate) {
        var _is_instance_handle = is_handle(_candidate) && string_starts_with(string(_candidate), "ref instance ");
        var _is_legacy_id = is_real(_candidate) && _candidate >= 100000;

        if (!_is_instance_handle && !_is_legacy_id) return false;

        return instance_exists(_candidate) && _candidate.id == _candidate;
    };

    /// @desc Verifica si la instancia o el struct referenciado débilmente siguen vivos.
    /// @param {Struct} _sub Registro de suscripción.
    /// @return {Bool}
    static __is_sub_alive = function(_sub) {
        if (_sub.is_instance) {
            return instance_exists(_sub.owner);
        }
        return weak_ref_alive(_sub.owner) && !is_undefined(_sub.owner.ref);
    };

    /// @desc Marca suscripciones como inactivas (tombstones) y compacta el canal si no hay emisiones activas.
    /// @param {String} _event_key Clave interna del mapa listeners.
    /// @param {Id.Instance, Struct} _owner Dueño a remover.
    /// @param {Function, Undefined} [_target_callback] Índice de función específico o undefined para borrar todas.
    static __remove_from_key = function(_event_key, _owner, _target_callback = undefined) {
        if (!variable_struct_exists(listeners, _event_key)) return;

        var _channel = listeners[$ _event_key];
        var _subscribers = _channel.subscribers;
        var _count = array_length(_subscribers);

        for (var _i = 0; _i < _count; _i++) {
            var _sub = _subscribers[_i];

            if (!_sub.is_active) continue;

            if (!__is_sub_alive(_sub)) {
                _sub.is_active = false;
                _channel.is_dirty = true;
                continue;
            }

            var _current_owner = _sub.is_instance ? _sub.owner : _sub.owner.ref;
            if (_current_owner != _owner) continue;

            if (is_undefined(_target_callback)) {
                _sub.is_active = false;
                _channel.is_dirty = true;
            } else if (_sub.callback == _target_callback) {
                _sub.is_active = false;
                _channel.is_dirty = true;
                break;
            }
        }

        if (_channel.emit_depth == 0 && _channel.is_dirty) {
            __compact_channel(_event_key);
        }
    };

    /// @desc Compacta el array de suscriptores en una sola pasada O(N) mediante dos punteros y libera el canal si queda vacío.
    /// @param {String} _event_key Clave interna del evento.
    static __compact_channel = function(_event_key) {
        if (!variable_struct_exists(listeners, _event_key)) return;

        var _channel = listeners[$ _event_key];
        var _subscribers = _channel.subscribers;
        var _len = array_length(_subscribers);
        var _write_idx = 0;

        for (var _read_idx = 0; _read_idx < _len; _read_idx++) {
            var _sub = _subscribers[_read_idx];

            if (_sub.is_active && __is_sub_alive(_sub)) {
                if (_write_idx != _read_idx) {
                    _subscribers[_write_idx] = _sub;
                }
                _write_idx++;
            }
        }

        array_resize(_subscribers, _write_idx);
        _channel.is_dirty = false;

        if (_write_idx == 0) {
            variable_struct_remove(listeners, _event_key);
        }
    };

    #endregion
}
#endregion