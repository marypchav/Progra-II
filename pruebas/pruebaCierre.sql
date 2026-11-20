/*
pruebaCierre.sql
Prueba de spCerrarEstadoCuenta.
Requiere: catálogos cargados, trigger y los SPs spAbrirEstadoCuenta,
spAplicarMovimiento y spCerrarEstadoCuenta compilados.
Al final limpia la base y recarga los catálogos.
*/

DECLARE @r INT
    , @idCuentaA INT
    , @idCuentaB INT
    , @idEstadoA INT
    , @idEstadoB INT
    , @i INT
    , @fecha DATE;

DECLARE @resultados TABLE (
    Paso VARCHAR(80)
    , Esperado INT
    , Obtenido INT
);

-- datos de prueba
INSERT INTO dbo.Persona (IdTipoDocuIdentidad, ValorDocumentoIdentidad, Nombre, FechaNacimiento, Email, Telefono1, Telefono2)
VALUES (1, '999999999', 'Persona de Prueba', '1990-01-01', 'prueba@ejemplo.com', '88888888', '22222222');

INSERT INTO dbo.Cuenta (NumeroCuenta, IdPersonaDueno, IdTipoCuentaAhorro, FechaCreacion, Saldo)
SELECT C.NumeroCuenta, P.IdPersona, C.IdTipo, '2026-03-01', 0
FROM (
    VALUES ('99000001', 1)
        , ('99000002', 3)
) AS C (NumeroCuenta, IdTipo)
INNER JOIN dbo.Persona AS P
    ON (P.ValorDocumentoIdentidad = '999999999');

SELECT @idCuentaA = C.IdCuenta FROM dbo.Cuenta AS C WHERE (C.NumeroCuenta = '99000001');
SELECT @idCuentaB = C.IdCuenta FROM dbo.Cuenta AS C WHERE (C.NumeroCuenta = '99000002');

-- cuenta A: depósito de 30 000 en ventana (ventana 1)
EXEC dbo.spAplicarMovimiento @idCuentaA, 1, 30000, N'Depósito de apertura', '2026-03-01', NULL, @r OUTPUT;

-- cuenta A: 10 retiros ATM de 1 000 (ATM 10) -> saldo 20 000
SET @i = 1;
WHILE (@i <= 10)
BEGIN
    SET @fecha = DATEADD(DAY, @i, '2026-03-01');
    EXEC dbo.spAplicarMovimiento @idCuentaA, 4, 1000, N'Retiro ATM', @fecha, NULL, @r OUTPUT;
    SET @i = @i + 1;
END;

-- cuenta A: 5 retiros en ventana de 500 (ventana 6) -> saldo 17 500
SET @i = 1;
WHILE (@i <= 5)
BEGIN
    SET @fecha = DATEADD(DAY, 11 + @i, '2026-03-01');
    EXEC dbo.spAplicarMovimiento @idCuentaA, 5, 500, N'Retiro ventana', @fecha, NULL, @r OUTPUT;
    SET @i = @i + 1;
END;

-- cuenta B: depósito de 200 000 (ventana 1, sin excesos)
EXEC dbo.spAplicarMovimiento @idCuentaB, 1, 200000, N'Depósito de apertura', '2026-03-01', NULL, @r OUTPUT;

SELECT @idEstadoA = EC.IdEstadoCuenta FROM dbo.EstadoCuenta AS EC WHERE (EC.IdCuenta = @idCuentaA) AND (EC.FlagAbierto = 1);
SELECT @idEstadoB = EC.IdEstadoCuenta FROM dbo.EstadoCuenta AS EC WHERE (EC.IdCuenta = @idCuentaB) AND (EC.FlagAbierto = 1);

-- 1. cerrar antes de tiempo (cierra el 2026-04-01)
EXEC dbo.spCerrarEstadoCuenta @idEstadoA, '2026-03-20', @r OUTPUT;
INSERT INTO @resultados VALUES ('1 Cerrar antes de la fecha de cierre', 52009, @r);

-- 2. cierre de la cuenta A con todos los cargos
EXEC dbo.spCerrarEstadoCuenta @idEstadoA, '2026-04-01', @r OUTPUT;
INSERT INTO @resultados VALUES ('2 Cierre cuenta A (todos los cargos)', 0, @r);

-- 3. cerrar otra vez el mismo estado
EXEC dbo.spCerrarEstadoCuenta @idEstadoA, '2026-04-01', @r OUTPUT;
INSERT INTO @resultados VALUES ('3 Cerrar un estado ya cerrado', 52008, @r);

-- 4. cierre de la cuenta B (solo intereses y cargo mensual)
EXEC dbo.spCerrarEstadoCuenta @idEstadoB, '2026-04-01', @r OUTPUT;
INSERT INTO @resultados VALUES ('4 Cierre cuenta B (sin excesos ni multa)', 0, @r);

-- resumen: Ok = 1 en todas las filas
SELECT R.Paso
    , R.Esperado
    , R.Obtenido
    , CASE WHEN (R.Esperado = R.Obtenido) THEN 1 ELSE 0 END AS Ok
FROM @resultados AS R;

-- movimientos del cierre (fecha 2026-04-01):
-- cuenta A: intereses 145.83 -> 17 645.83, comisión ATM 600 -> 17 045.83,
--           comisión ventana 300 -> 16 745.83, multa 3 000 -> 13 745.83, cargo 5 000 -> 8 745.83
-- cuenta B: intereses 3 333.33 -> 203 333.33, cargo 30 000 -> 173 333.33
SELECT C.NumeroCuenta
    , TM.Nombre AS Tipo
    , M.Monto
    , M.NuevoSaldo
    , M.Descripcion
FROM dbo.Movimiento AS M
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = M.IdCuenta)
INNER JOIN dbo.TipoMovimiento AS TM
    ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
WHERE (M.Fecha = '2026-04-01')
ORDER BY C.NumeroCuenta
    , M.IdMovimiento;

-- estados:
-- A período 1: cerrado, emisión 2026-04-01, intereses 145.83, saldo mín 17 500, saldo final 8 745.83, ATM 10, ventana 6
-- A período 2: 2026-04-02 al 2026-05-01, saldo inicial 8 745.83, abierto
-- B período 1: cerrado, intereses 3 333.33, saldo mín 200 000, saldo final 173 333.33
-- B período 2: 2026-04-02 al 2026-05-01, saldo inicial 173 333.33, abierto
SELECT C.NumeroCuenta
    , EC.NumeroPeriodo
    , EC.FechaInicio
    , EC.FechaFin
    , EC.FechaEmision
    , EC.SaldoInicial
    , EC.SaldoFinal
    , EC.SaldoMinimo
    , EC.InteresesAcumulados
    , EC.CantOperATM
    , EC.CantOperVentana
    , EC.FlagAbierto
FROM dbo.EstadoCuenta AS EC
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = EC.IdCuenta)
ORDER BY C.NumeroCuenta
    , EC.NumeroPeriodo;

-- errores inesperados: no debe haber ninguno nuevo
SELECT TOP 5 E.ErrorProcedure
    , E.ErrorMessage
    , E.ErrorDateTime
FROM dbo.dbError AS E
ORDER BY E.ErrorDateTime DESC;

-- limpieza: deja la base solo con catálogos
EXEC dbo.spLimpiarBD @r OUTPUT;
EXEC dbo.spCargarCatalogo @r OUTPUT;
