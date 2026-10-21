# Sistema de Reservas de Salones de Eventos

## Descripción del proyecto

**Eventos Premier S.A.S.** es una empresa dedicada al alquiler de salones para reuniones, fiestas y conferencias.
Este proyecto implementa en **MySQL** la base de datos del sistema de reservas: gestión de salones, clientes,
reservas y pagos, con funciones, triggers, vistas y consultas que permiten al personal administrativo controlar
la disponibilidad, los ingresos y el mantenimiento.

## Estructura del repositorio

| Archivo                   | Contenido                                                    |
| ------------------------- | ------------------------------------------------------------ |
| `01_creacion_bd.sql`      | `CREATE DATABASE`, `CREATE TABLE`, relaciones y llaves foráneas |
| `02_funciones.sql`        | Funciones `calcular_total_reserva` y `verificar_disponibilidad` |
| `03_triggers.sql`         | Triggers de control y auditoría                              |
| `04_datos_prueba.sql`     | Datos de ejemplo para probar todo                            |
| `05_vistas_consultas.sql` | Vista `vista_resumen_reservas` y consultas SELECT            |

## Modelo de datos

- **encargados** (id_encargado, nombre, telefono, correo)
- **salones** (id_salon, nombre, capacidad, precio_hora, estado, id_encargado → encargados)
- **clientes** (id_cliente, nombre_completo, identificacion, telefono, correo, tipo_cliente)
- **reservas** (id_reserva, id_cliente → clientes, id_salon → salones, fecha_inicio, fecha_fin, total_horas, valor_total, estado)
- **pagos** (id_pago, id_reserva → reservas, fecha_pago, monto_pagado, metodo_pago)
- **auditoria_precios** (id_auditoria, id_salon, usuario, fecha, precio_anterior, precio_nuevo)

Relaciones: un encargado → varios salones; un cliente → varias reservas; un salón → varias reservas;
una reserva → varios pagos.

## Instrucciones de ejecución

Requisito: MySQL 8.0.16 o superior (por las restricciones `CHECK`).

**Desde la terminal** (en el orden indicado):

```bash
mysql -u root -p < 01_creacion_bd.sql
mysql -u root -p < 02_funciones.sql
mysql -u root -p < 03_triggers.sql
mysql -u root -p < 04_datos_prueba.sql
mysql -u root -p < 05_vistas_consultas.sql
```

**Desde MySQL Workbench:** abrir cada script y ejecutarlo en el mismo orden (⚡ Execute).

> Importante: respetar el orden. Los triggers usan las funciones, y los datos de prueba usan los triggers.

## Ejemplos de uso

### Funciones

```sql
-- Total con IVA (19%): 250000 * 4 horas * 1.19
SELECT calcular_total_reserva(250000, 4) AS total;          -- 1190000.00

-- 1 = disponible, 0 = ocupado
SELECT verificar_disponibilidad(1, '2026-10-05 09:00:00', '2026-10-05 11:00:00');  -- 0
SELECT verificar_disponibilidad(1, '2026-10-06 09:00:00', '2026-10-06 11:00:00');  -- 1
```

### Triggers

```sql
-- 1) actualizar_estado_salon_trigger: el salón pasa a 'Ocupado'
INSERT INTO reservas (id_cliente, id_salon, fecha_inicio, fecha_fin)
VALUES (1, 6, '2026-12-10 10:00:00', '2026-12-10 14:00:00');
SELECT nombre, estado FROM salones WHERE id_salon = 6;      -- Ocupado
SELECT total_horas, valor_total FROM reservas ORDER BY id_reserva DESC LIMIT 1;  -- 4.00 / 1666000.00

-- 2) liberar_salon_trigger: al eliminar la reserva el salón vuelve a 'Disponible'
DELETE FROM reservas WHERE id_reserva = LAST_INSERT_ID();
SELECT nombre, estado FROM salones WHERE id_salon = 6;      -- Disponible

-- 3) auditoria_precios_trigger: registra el cambio de precio
UPDATE salones SET precio_hora = 380000 WHERE id_salon = 6;
SELECT * FROM auditoria_precios;

-- Control: intentar reservar en un horario ya ocupado genera error
INSERT INTO reservas (id_cliente, id_salon, fecha_inicio, fecha_fin)
VALUES (2, 1, '2026-10-05 09:00:00', '2026-10-05 11:00:00');
-- ERROR 1644: El salón ya tiene una reserva en ese rango de fechas.
```

### Consultas y vista

Ver `05_vistas_consultas.sql`:

1. Reservas en un rango de fechas (`BETWEEN`).
2. Salones con capacidad mayor a X y estado `Disponible`.
3. Clientes corporativos con más de 3 reservas (subconsulta / `COUNT`).
4. Vista `vista_resumen_reservas`: `SELECT * FROM vista_resumen_reservas;`

## Créditos y autor

- **Autoras:** Dana Valentina Diaz Florez y Vivianne Salina Rueda G2
- **Curso:** G2
- **Profesor:** Didier Vallejo
- **Fecha:** 19 de octubre de 2026
