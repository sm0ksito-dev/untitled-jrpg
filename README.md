# [untitled-jrpg]

JRPG indie desarrollado en **GameMaker Studio 2** que combina exploración Top-Down en 2D, sistemas de progresión y oficios inspirados en MMORPGs, y combate de acción en tiempo real en planos 2.5D (tomando como referencia *Tales of Rebirth* y *Street Fighter*).

---

## Stack y Entorno
* **Motor:** GameMaker Studio 2 (GML 2.3+)
* **Arquitectura:** Modular por dominios, Data-Driven y orientada a eventos (*Event Bus*).
* **Resolución base:** [Ej. 640x360 escalado a 1080p]

---

## Arquitectura del Proyecto

El proyecto está organizado por módulos independientes dentro de `/src` para desacoplar los datos persistentes de los avatares en escena:

* `00_Global_Core`: Gestión del ciclo de vida, lectura de inputs unificada, base de datos estática (`global.db`) y serialización de partidas (`global.save_data`).
* `01_RPG_Progression`: Cálculo de estadísticas derivadas, inventario, árbol de habilidades, maestrías de armas/oficios y sistema de misiones.
* `02_Module_Roam`: Exploración Top-Down 2D, colisiones suaves e interacción con NPCs y entorno.
* `03_Module_Combat`: Motor de combate 2.5D con *Input History*, *Input Buffer*, *Frame Data* (Startup/Active/Recovery), *Hitstop* y sistema de cancelaciones.
* `04_Module_Minigames`: Sistemas aislados de *Life Skills* (pesca, ritmo/música, crafteo) conectados a la progresión global.
* `99_Shared_Tools`: Motor genérico de Máquina de Estados (`FSM`), `Event Bus` y herramientas visuales de depuración (*Hitboxes/Hurtboxes*).

---

## Estado del Desarrollo (Roadmap)

### Fase 0: Arquitectura Base
- [x] Estructura de repositorio y convenciones de nombrado
- [ ] Event Bus (`scr_event_bus`) y Máquina de Estados genérica (`scr_fsm_core`)
- [ ] Estructura de Base de Datos (`global.db`) y Guardado JSON (`global.save_data`)

### Fase 1: Prototipo de Combate 2.5D
- [ ] Sistema de Input History y Buffer
- [ ] Movimiento en planos 2.5D y orientación automática
- [ ] Sistema de Frame Data y colisiones Hitbox vs. Hurtbox
- [ ] Hitstop, Hitstun y ventana de cancelaciones

### Fase 2: Exploración y Progresión RPG
- [ ] Movimiento Top-Down e interacción con entidades
- [ ] Transición fluida Roam <-> Arena de Combate
- [ ] Calculadora de stats (Base + Equipo + Maestrías)

---

## Convenciones del Código
* **Carpetas:** `NN_Pascal_Snake` (ej. `03_Module_Combat`).
* **Assets:** Prefijos estrictos en `snake_case` (`obj_`, `scr_`, `spr_`, `rm_`, `ts_`, `bgm_`, `sfx_`).
* **GML:** Constructores en `PascalCase`, funciones en `snake_case`, parámetros con guion bajo (`_param`) y constantes/enums en `UPPER_SNAKE_CASE`.