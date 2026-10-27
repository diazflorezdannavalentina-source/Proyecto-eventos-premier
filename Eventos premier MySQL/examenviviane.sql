SELECT  YearMonth, id_producto, TotalReservaProducto, 
   RANK()  OVER (PARTITION BY YearMonth 
            ORDER BY  TotalReservaProducto DESC) AS RankingProducto 
 FROM ( 
 SELECT DATE_FORMAT(fecha_reserva, '%Y-%m') AS YearMonth, 
   id_producto, SUM(monto_reserva) AS TotalReservasProducto, 
   RANK() OVER ( ORDER BY SUM(reserva_venta)  AS totalReservasProducto,
   FROM RESERVAS 
   GROUP BY YearMonth,  id_reservas 
   ) AS ReservasMensuales 
   WHERE RankingMes <= 3  RankingReservas <= 4 reservas 
   

CREATE TRIGGER actualizar_estado_salon_trigger
AFTER INSERT ON reservas
FOR EACH ROW
BEGIN
    UPDATE salones
    SET estado = 'Ocupado'
    WHERE id_salon = NEW.id_salon;
END$$
a