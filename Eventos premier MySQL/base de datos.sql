-- =====================================================================
-- PROYECTO COMPLETO: Sistema de Reservas de Salones de Eventos
-- Eventos Premier S.A.S. | MySQL 8.0.16+
-- Ejecutar TODO el script de una sola vez (Workbench: Ctrl+Shift+Enter)
-- =====================================================================


-- #####################################################################
-- ARCHIVO: 01_creacion_bd.sql
-- #####################################################################
-- =====================================================================
-- Proyecto: Sistema de Reservas de Salones de Eventos
-- Empresa : Eventos Premier S.A.S.
-- Script  : 01 - Creación de la base de datos y tablas
-- Motor   : MySQL 8.0+
-- =====================================================================

DROP DATABASE IF EXISTS eventos_premier;
CREATE DATABASE eventos_premier
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE eventos_premier;

-- ---------------------------------------------------------------------
-- Tabla: encargados (responsables de cada salón)
-- ---------------------------------------------------------------------
CREATE TABLE encargados (
    id_encargado INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(100) NOT NULL,
    telefono     VARCHAR(20),
    correo       VARCHAR(100)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Tabla: salones
-- ---------------------------------------------------------------------
CREATE TABLE salones (
    id_salon     INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(100) NOT NULL UNIQUE,
    capacidad    INT NOT NULL,
    precio_hora  DECIMAL(12,2) NOT NULL,
    estado       ENUM('Disponible','En mantenimiento','Ocupado') NOT NULL DEFAULT 'Disponible',
    id_encargado INT NOT NULL,
    CONSTRAINT chk_salon_capacidad CHECK (capacidad > 0),
    CONSTRAINT chk_salon_precio    CHECK (precio_hora >= 0),
    CONSTRAINT fk_salon_encargado  FOREIGN KEY (id_encargado)
        REFERENCES encargados (id_encargado)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Tabla: clientes
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente      INT AUTO_INCREMENT PRIMARY KEY,
    nombre_completo VARCHAR(150) NOT NULL,
    identificacion  VARCHAR(30)  NOT NULL UNIQUE,
    telefono        VARCHAR(20),
    correo          VARCHAR(100) UNIQUE,
    tipo_cliente    ENUM('Individual','Corporativo') NOT NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Tabla: reservas
-- total_horas y valor_total se calculan automáticamente
-- mediante el trigger antes_insertar_reserva (script 03).
-- ---------------------------------------------------------------------
CREATE TABLE reservas (
    id_reserva   INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente   INT NOT NULL,
    id_salon     INT NOT NULL,
    fecha_inicio DATETIME NOT NULL,
    fecha_fin    DATETIME NOT NULL,
    total_horas  DECIMAL(8,2)  NOT NULL DEFAULT 0,
    valor_total  DECIMAL(14,2) NOT NULL DEFAULT 0,
    estado       ENUM('Confirmada','Cancelada','Finalizada') NOT NULL DEFAULT 'Confirmada',
    CONSTRAINT chk_reserva_fechas CHECK (fecha_fin > fecha_inicio),
    CONSTRAINT fk_reserva_cliente FOREIGN KEY (id_cliente)
        REFERENCES clientes (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_reserva_salon FOREIGN KEY (id_salon)
        REFERENCES salones (id_salon)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE INDEX idx_reservas_salon_fechas ON reservas (id_salon, fecha_inicio, fecha_fin);

-- ---------------------------------------------------------------------
-- Tabla: pagos
-- ---------------------------------------------------------------------
CREATE TABLE pagos (
    id_pago      INT AUTO_INCREMENT PRIMARY KEY,
    id_reserva   INT NOT NULL,
    fecha_pago   DATE NOT NULL,
    monto_pagado DECIMAL(14,2) NOT NULL,
    metodo_pago  ENUM('Efectivo','Tarjeta','Transferencia') NOT NULL,
    CONSTRAINT chk_pago_monto CHECK (monto_pagado > 0),
    CONSTRAINT fk_pago_reserva FOREIGN KEY (id_reserva)
        REFERENCES reservas (id_reserva)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- Tabla: auditoria_precios (la llena el trigger auditoria_precios_trigger)
-- ---------------------------------------------------------------------
CREATE TABLE auditoria_precios (
    id_auditoria    INT AUTO_INCREMENT PRIMARY KEY,
    id_salon        INT NOT NULL,
    usuario         VARCHAR(100) NOT NULL,
    fecha           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    precio_anterior DECIMAL(12,2) NOT NULL,
    precio_nuevo    DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB;


-- #####################################################################
-- ARCHIVO: 02_funciones.sql
-- #####################################################################
-- =====================================================================
-- Script 02 - Funciones personalizadas
-- =====================================================================
USE eventos_premier;

DROP FUNCTION IF EXISTS calcular_total_reserva;
DROP FUNCTION IF EXISTS verificar_disponibilidad;

DELIMITER $$

-- ---------------------------------------------------------------------
-- calcular_total_reserva(precio_hora, horas)
-- Retorna el valor total de la reserva con IVA (19%).
-- ---------------------------------------------------------------------
CREATE FUNCTION calcular_total_reserva(p_precio_hora DECIMAL(12,2), p_horas DECIMAL(8,2))
RETURNS DECIMAL(14,2)
DETERMINISTIC
BEGIN
    RETURN ROUND(p_precio_hora * p_horas * 1.19, 2);
END$$

-- ---------------------------------------------------------------------
-- verificar_disponibilidad(salon_id, fecha_inicio, fecha_fin)
-- Retorna 1 si el salón está disponible en ese rango, 0 si está ocupado.
-- Hay cruce cuando: inicio_existente < fin_nuevo  Y  fin_existente > inicio_nuevo
-- Las reservas canceladas no cuentan.
-- ---------------------------------------------------------------------
CREATE FUNCTION verificar_disponibilidad(p_salon_id INT, p_fecha_inicio DATETIME, p_fecha_fin DATETIME)
RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_conflictos INT;

    SELECT COUNT(*) INTO v_conflictos
    FROM reservas
    WHERE id_salon = p_salon_id
      AND estado <> 'Cancelada'
      AND fecha_inicio < p_fecha_fin
      AND fecha_fin    > p_fecha_inicio;

    IF v_conflictos = 0 THEN
        RETURN 1;
    END IF;
    RETURN 0;
END$$

DELIMITER ;


-- #####################################################################
-- ARCHIVO: 03_triggers.sql
-- #####################################################################
-- =====================================================================
-- Script 03 - Triggers de control y auditoría
-- (Requiere haber ejecutado antes 01 y 02)
-- =====================================================================
USE eventos_premier;

DROP TRIGGER IF EXISTS antes_insertar_reserva;
DROP TRIGGER IF EXISTS actualizar_estado_salon_trigger;
DROP TRIGGER IF EXISTS liberar_salon_trigger;
DROP TRIGGER IF EXISTS auditoria_precios_trigger;

DELIMITER $$

-- ---------------------------------------------------------------------
-- Trigger de control: valida y calcula total_horas y valor_total
-- automáticamente antes de insertar una reserva.
-- ---------------------------------------------------------------------
CREATE TRIGGER antes_insertar_reserva
BEFORE INSERT ON reservas
FOR EACH ROW
BEGIN
    DECLARE v_precio DECIMAL(12,2);
    DECLARE v_estado VARCHAR(20);

    IF NEW.fecha_fin <= NEW.fecha_inicio THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La fecha de fin debe ser posterior a la fecha de inicio.';
    END IF;

    SELECT precio_hora, estado INTO v_precio, v_estado
    FROM salones
    WHERE id_salon = NEW.id_salon;

    IF v_estado = 'En mantenimiento' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El salón está en mantenimiento y no se puede reservar.';
    END IF;

    IF verificar_disponibilidad(NEW.id_salon, NEW.fecha_inicio, NEW.fecha_fin) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El salón ya tiene una reserva en ese rango de fechas.';
    END IF;

    SET NEW.total_horas = ROUND(TIMESTAMPDIFF(MINUTE, NEW.fecha_inicio, NEW.fecha_fin) / 60, 2);
    SET NEW.valor_total = calcular_total_reserva(v_precio, NEW.total_horas);
END$$

-- ---------------------------------------------------------------------
-- Al registrar una nueva reserva, el salón pasa a "Ocupado".
-- ---------------------------------------------------------------------
CREATE TRIGGER actualizar_estado_salon_trigger
AFTER INSERT ON reservas
FOR EACH ROW
BEGIN
    UPDATE salones
    SET estado = 'Ocupado'
    WHERE id_salon = NEW.id_salon;
END$$

-- ---------------------------------------------------------------------
-- Al eliminar una reserva, el salón vuelve a "Disponible"
-- (siempre que no esté en mantenimiento).
-- ---------------------------------------------------------------------
CREATE TRIGGER liberar_salon_trigger
AFTER DELETE ON reservas
FOR EACH ROW
BEGIN
    UPDATE salones
    SET estado = 'Disponible'
    WHERE id_salon = OLD.id_salon
      AND estado = 'Ocupado';
END$$

-- ---------------------------------------------------------------------
-- Auditoría: registra usuario, fecha y valor anterior/nuevo
-- cuando cambia el precio por hora de un salón.
-- ---------------------------------------------------------------------
CREATE TRIGGER auditoria_precios_trigger
AFTER UPDATE ON salones
FOR EACH ROW
BEGIN
    IF OLD.precio_hora <> NEW.precio_hora THEN
        INSERT INTO auditoria_precios (id_salon, usuario, fecha, precio_anterior, precio_nuevo)
        VALUES (OLD.id_salon, USER(), NOW(), OLD.precio_hora, NEW.precio_hora);
    END IF;
END$$

DELIMITER ;


-- #####################################################################
-- ARCHIVO: 04_datos_prueba.sql
-- #####################################################################
-- =====================================================================
-- Script 04 - Datos de prueba
-- (Ejecutar DESPUÉS de los triggers: total_horas y valor_total se calculan solos)
-- =====================================================================
USE eventos_premier;

INSERT INTO encargados (nombre, telefono, correo) VALUES
('Laura Gómez',   '3001112233', 'laura.gomez@eventospremier.com'),
('Carlos Pérez',  '3004445566', 'carlos.perez@eventospremier.com'),
('Marta Rojas',   '3007778899', 'marta.rojas@eventospremier.com');

INSERT INTO salones (nombre, capacidad, precio_hora, estado, id_encargado) VALUES
('Salón Esmeralda', 150, 250000, 'Disponible',       1),
('Salón Zafiro',     80, 150000, 'Disponible',       1),
('Salón Diamante',  300, 500000, 'Disponible',       2),
('Salón Rubí',       50, 100000, 'En mantenimiento', 2),
('Salón Perla',     120, 200000, 'Disponible',       3),
('Salón Amatista',  200, 350000, 'Disponible',       3),
('Salón Topacio',   100, 180000, 'Disponible',       1);

INSERT INTO clientes (nombre_completo, identificacion, telefono, correo, tipo_cliente) VALUES
('Ana María Torres',            '1098765432', '3101234567', 'ana.torres@correo.com',       'Individual'),
('Juan David Ruiz',             '1090123456', '3112345678', 'juan.ruiz@correo.com',        'Individual'),
('Tecnologías Andinas S.A.S.',  '900123456-1','6076000000', 'eventos@tecandinas.com',      'Corporativo'),
('Constructora del Oriente Ltda','900654321-2','6076111111','contacto@constoriente.com',   'Corporativo'),
('Grupo Santander Foods S.A.',  '900987654-3','6076222222', 'compras@santanderfoods.com',  'Corporativo');

-- Cliente 3 (corporativo) hace 4 reservas -> aparecerá en la consulta de "más de 3 reservas"
INSERT INTO reservas (id_cliente, id_salon, fecha_inicio, fecha_fin) VALUES
(3, 1, '2026-10-05 08:00:00', '2026-10-05 12:00:00'),
(3, 2, '2026-10-12 14:00:00', '2026-10-12 18:00:00'),
(3, 1, '2026-10-20 09:00:00', '2026-10-20 13:00:00'),
(3, 3, '2026-11-03 08:00:00', '2026-11-03 17:00:00'),
(1, 5, '2026-10-15 18:00:00', '2026-10-15 23:00:00'),
(4, 2, '2026-10-25 10:00:00', '2026-10-25 14:00:00'),
(2, 3, '2026-11-15 19:00:00', '2026-11-15 23:00:00'),
(5, 5, '2026-12-01 08:00:00', '2026-12-01 12:00:00');

INSERT INTO pagos (id_reserva, fecha_pago, monto_pagado, metodo_pago) VALUES
(1, '2026-10-01', 1190000.00, 'Transferencia'),
(2, '2026-10-08',  357000.00, 'Tarjeta'),
(2, '2026-10-12',  357000.00, 'Efectivo'),
(3, '2026-10-15',  500000.00, 'Transferencia'),
(5, '2026-10-10', 1000000.00, 'Tarjeta'),
(6, '2026-10-20',  714000.00, 'Transferencia');

USE eventos_premier;

INSERT INTO auditoria_precios (id_salon, usuario, fecha, precio_anterior, precio_nuevo) VALUES
(1, 'root@localhost', '2026-09-01 10:15:00', 230000.00, 250000.00),
(2, 'root@localhost', '2026-09-03 09:30:00', 140000.00, 150000.00),
(3, 'root@localhost', '2026-09-10 14:00:00', 450000.00, 500000.00),
(5, 'root@localhost', '2026-09-15 16:45:00', 180000.00, 200000.00),
(6, 'root@localhost', '2026-09-20 11:20:00', 320000.00, 350000.00);


-- #####################################################################
-- ARCHIVO: 05_vistas_consultas.sql
-- #####################################################################
-- =====================================================================
-- Script 05 - Vistas y consultas SQL
-- =====================================================================
USE eventos_premier;

-- ---------------------------------------------------------------------
-- VISTA: vista_resumen_reservas
-- Nombre del cliente, nombre del salón, fecha inicio, fecha fin, total y estado
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW vista_resumen_reservas AS
SELECT
    r.id_reserva,
    c.nombre_completo AS cliente,
    s.nombre          AS salon,
    r.fecha_inicio,
    r.fecha_fin,
    r.valor_total     AS total,
    r.estado
FROM reservas r
INNER JOIN clientes c ON c.id_cliente = r.id_cliente
INNER JOIN salones  s ON s.id_salon   = r.id_salon;

-- ---------------------------------------------------------------------
-- CONSULTA 1: Reservas realizadas en un rango de fechas (BETWEEN)
-- ---------------------------------------------------------------------
SELECT r.id_reserva, c.nombre_completo AS cliente, s.nombre AS salon,
       r.fecha_inicio, r.fecha_fin, r.total_horas, r.valor_total
FROM reservas r
JOIN clientes c ON c.id_cliente = r.id_cliente
JOIN salones  s ON s.id_salon   = r.id_salon
WHERE r.fecha_inicio BETWEEN '2026-10-01 00:00:00' AND '2026-10-31 23:59:59'
ORDER BY r.fecha_inicio;

-- ---------------------------------------------------------------------
-- CONSULTA 2: Salones con capacidad mayor a X personas y estado 'Disponible'
-- (ejemplo con X = 100)
-- ---------------------------------------------------------------------
SELECT id_salon, nombre, capacidad, precio_hora, estado
FROM salones
WHERE capacidad > 100
  AND estado = 'Disponible'
ORDER BY capacidad DESC;

-- ---------------------------------------------------------------------
-- CONSULTA 3: Clientes corporativos con más de 3 reservas (subconsulta)
-- ---------------------------------------------------------------------
SELECT c.id_cliente, c.nombre_completo, c.correo,
       (SELECT COUNT(*) FROM reservas r WHERE r.id_cliente = c.id_cliente) AS total_reservas
FROM clientes c
WHERE c.tipo_cliente = 'Corporativo'
  AND (SELECT COUNT(*) FROM reservas r WHERE r.id_cliente = c.id_cliente) > 3;

-- Versión alternativa con COUNT + GROUP BY + HAVING
SELECT c.id_cliente, c.nombre_completo, COUNT(r.id_reserva) AS total_reservas
FROM clientes c
JOIN reservas r ON r.id_cliente = c.id_cliente
WHERE c.tipo_cliente = 'Corporativo'
GROUP BY c.id_cliente, c.nombre_completo
HAVING COUNT(r.id_reserva) > 3;

-- ---------------------------------------------------------------------
-- CONSULTA 4: Uso de la vista
-- ---------------------------------------------------------------------
SELECT * FROM vista_resumen_reservas ORDER BY fecha_inicio;