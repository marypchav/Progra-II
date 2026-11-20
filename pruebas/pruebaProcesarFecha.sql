/*
pruebaProcesarFecha.sql
Prueba de spCargarOperacionesXML y spProcesarFecha con el XML real.
Procesa del 2026-03-01 al 2026-04-01 (incluye el primer cierre de mes).
Requiere: OperacionesTarea3.xml en C:\Temp\ y todos los SPs anteriores compilados.
Empieza limpiando la base. Al final NO limpia, para que puedan revisar los datos.
*/

DECLARE @r INT
    , @fecha DATE
    , @fallos INT;

DECLARE @resultados TABLE (
    Paso VARCHAR(80)
    , Esperado INT
    , Obtenido INT
);

-- base limpia con catálogos
EXEC dbo.spLimpiarBD @r OUTPUT;
EXEC dbo.spCargarCatalogo @r OUTPUT;

-- 1. carga del XML
EXEC dbo.spCargarOperacionesXML @r OUTPUT;
INSERT INTO @resultados VALUES ('1 Cargar XML de operaciones', 0, @r);

-- 2. cargarlo otra vez no debe duplicar
EXEC dbo.spCargarOperacionesXML @r OUTPUT;
INSERT INTO @resultados VALUES ('2 Cargar XML por segunda vez', 52011, @r);

-- 3. procesar una fecha sin haber procesado las anteriores
EXEC dbo.spProcesarFecha '2026-03-05', @r OUTPUT;
INSERT INTO @resultados VALUES ('3 Procesar 2026-03-05 sin la anterior', 52014, @r);

-- 4. procesar del 2026-03-01 al 2026-04-01, día por día (incluye días sin datos)
SET @fecha = '2026-03-01';
SET @fallos = 0;
WHILE (@fecha <= '2026-04-01')
BEGIN
    EXEC dbo.spProcesarFecha @fecha, @r OUTPUT;
    SET @fallos = @fallos + CASE WHEN (@r <> 0) THEN 1 ELSE 0 END;
    SET @fecha = DATEADD(DAY, 1, @fecha);
END;
INSERT INTO @resultados VALUES ('4 Fechas con error entre 03-01 y 04-01', 0, @fallos);

-- 5. una fecha ya procesada no se repite
EXEC dbo.spProcesarFecha '2026-03-01', @r OUTPUT;
INSERT INTO @resultados VALUES ('5 Procesar 2026-03-01 otra vez', 52013, @r);

-- 6. brincarse una fecha (falta 2026-04-02)
EXEC dbo.spProcesarFecha '2026-04-03', @r OUTPUT;
INSERT INTO @resultados VALUES ('6 Procesar 2026-04-03 sin el 04-02', 52014, @r);

-- resumen: Ok = 1 en todas las filas
SELECT R.Paso
    , R.Esperado
    , R.Obtenido
    , CASE WHEN (R.Esperado = R.Obtenido) THEN 1 ELSE 0 END AS Ok
FROM @resultados AS R;

-- nodos cargados: Persona 15, Cuenta 10, Beneficiario 11, Usuario 10,
-- UsuarioPuedeVer 11, Movimientos 100 (total 157)
SELECT OX.TipoNodo
    , COUNT(1) AS Cantidad
FROM dbo.OperacionXML AS OX
GROUP BY OX.TipoNodo
ORDER BY MIN(OX.Orden);

-- datos creados hasta el 2026-04-01:
-- Persona 13, Cuenta 8, Beneficiario 10, Usuario 8, UsuarioPuedeVer 9,
-- Movimiento 27 (23 del XML + 4 del cierre), Comprobante 23,
-- EstadoCuenta 10 (8 primeros períodos + 2 abiertos por el cierre), Fechas 32
SELECT 'Persona' AS Tabla, COUNT(1) AS Cantidad FROM dbo.Persona
UNION ALL SELECT 'Cuenta', COUNT(1) FROM dbo.Cuenta
UNION ALL SELECT 'Beneficiario', COUNT(1) FROM dbo.Beneficiario
UNION ALL SELECT 'Usuario', COUNT(1) FROM dbo.Usuario
UNION ALL SELECT 'UsuarioPuedeVer', COUNT(1) FROM dbo.UsuarioPuedeVer
UNION ALL SELECT 'Movimiento', COUNT(1) FROM dbo.Movimiento
UNION ALL SELECT 'Comprobante', COUNT(1) FROM dbo.Comprobante
UNION ALL SELECT 'EstadoCuenta', COUNT(1) FROM dbo.EstadoCuenta
UNION ALL SELECT 'Fechas terminadas', COUNT(1) FROM dbo.ControlSimulacion WHERE (FlagTerminado = 1);

-- primer cierre (2026-04-01) de las dos cuentas creadas el 2026-03-01:
-- 11000001: saldo mín 211 500, intereses 1 762.50, cargo 5 000 -> saldo final 375 512.50
-- 11000002: saldo mín 404 400, intereses 5 055.00, cargo 15 000 -> saldo final 1 044 455.00
-- período 2 de ambas: 2026-04-02 al 2026-05-01, abierto
SELECT C.NumeroCuenta
    , EC.NumeroPeriodo
    , EC.FechaInicio
    , EC.FechaFin
    , EC.SaldoInicial
    , EC.SaldoMinimo
    , EC.InteresesAcumulados
    , EC.SaldoFinal
    , EC.CantOperATM
    , EC.CantOperVentana
    , EC.CantOperSinpe
    , EC.FlagAbierto
FROM dbo.EstadoCuenta AS EC
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = EC.IdCuenta)
WHERE (C.NumeroCuenta IN ('11000001', '11000002'))
ORDER BY C.NumeroCuenta
    , EC.NumeroPeriodo;

-- movimientos de la cuenta 11000001, en orden cronológico
SELECT M.Fecha
    , TM.Nombre AS Tipo
    , M.Monto
    , M.NuevoSaldo
    , M.Descripcion
FROM dbo.Movimiento AS M
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = M.IdCuenta)
INNER JOIN dbo.TipoMovimiento AS TM
    ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
WHERE (C.NumeroCuenta = '11000001')
ORDER BY M.Fecha
    , M.IdMovimiento;

-- nodos rechazados o errores: no debe haber ninguno
SELECT E.ErrorNumber
    , E.ErrorProcedure
    , E.ErrorMessage
    , E.ErrorDateTime
FROM dbo.dbError AS E
WHERE (E.ErrorDateTime >= DATEADD(MINUTE, -10, GETDATE()))
ORDER BY E.ErrorDateTime DESC;
