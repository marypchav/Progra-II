/*
pruebaPortal.sql
Prueba de los SPs del portal. Requiere haber corrido corridaSimulacion.sql
(usa los usuarios y cuentas del XML de operaciones).
*/

DECLARE @r INT
    , @idAmora INT
    , @idCvargas INT
    , @idCuenta INT
    , @idEstado INT
    , @bitacoraAntes INT;

DECLARE @resultados TABLE (
    Paso VARCHAR(80)
    , Esperado INT
    , Obtenido INT
);

SELECT @idAmora = U.IdUsuario FROM dbo.Usuario AS U WHERE (U.UserName = 'amora');
SELECT @idCvargas = U.IdUsuario FROM dbo.Usuario AS U WHERE (U.UserName = 'cvargas');
SELECT @idCuenta = C.IdCuenta FROM dbo.Cuenta AS C WHERE (C.NumeroCuenta = '11000001');
SELECT @idEstado = EC.IdEstadoCuenta FROM dbo.EstadoCuenta AS EC WHERE (EC.IdCuenta = @idCuenta) AND (EC.NumeroPeriodo = 2);
SELECT @bitacoraAntes = COUNT(1) FROM dbo.Bitacora;

-- 1. estados de 11000001 (amora): 4 filas, la primera es el período 4 (abierto)
EXEC dbo.spConsultarEstadoCuenta @idAmora, @idCuenta, '127.0.0.1', @r OUTPUT;
INSERT INTO @resultados VALUES ('1 Lista de estados (amora)', 0, @r);

-- 2. detalle del período 2 (2026-04-02 al 2026-05-01):
--    estado con CantOperATM 12 y 16 movimientos en orden cronológico,
--    los 3 últimos del cierre: intereses, comisión ATM 1 200 y cargo 5 000
EXEC dbo.spConsultarMovimientosEstado @idAmora, @idEstado, '127.0.0.1', @r OUTPUT;
INSERT INTO @resultados VALUES ('2 Detalle del periodo 2 (amora)', 0, @r);

-- 3. otro usuario no puede ver ese estado
EXEC dbo.spConsultarMovimientosEstado @idCvargas, @idEstado, '127.0.0.1', @r OUTPUT;
INSERT INTO @resultados VALUES ('3 Detalle sin acceso (cvargas)', 50002, @r);

-- 4. estado inexistente
EXEC dbo.spConsultarMovimientosEstado @idAmora, 999999, '127.0.0.1', @r OUTPUT;
INSERT INTO @resultados VALUES ('4 Estado inexistente', 50015, @r);

-- 5. solo las consultas exitosas quedan en la bitácora (2 filas nuevas)
INSERT INTO @resultados
SELECT '5 Filas nuevas en la bitacora', 2, COUNT(1) - @bitacoraAntes
FROM dbo.Bitacora;

-- resumen: Ok = 1 en todas las filas
SELECT R.Paso
    , R.Esperado
    , R.Obtenido
    , CASE WHEN (R.Esperado = R.Obtenido) THEN 1 ELSE 0 END AS Ok
FROM @resultados AS R;
