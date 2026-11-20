/*
corridaSimulacion.sql
Script de la simulación y su corrida (Tres.1 del enunciado).

Corre la simulación completa del 2026-03-01 al 2026-06-30 y verifica que
los datos cuadren. Ocupa en C:\Temp\: CatalogosTarea3.xml y OperacionesTarea3.xml.
*/

DECLARE @r INT
    , @inicio DATETIME = GETDATE();

DECLARE @resultados TABLE (
    Paso VARCHAR(60)
    , Obtenido INT
);

-- 1. corrida completa
EXEC dbo.spLimpiarBD @r OUTPUT;
INSERT INTO @resultados VALUES ('1 spLimpiarBD', @r);

EXEC dbo.spCargarCatalogo @r OUTPUT;
INSERT INTO @resultados VALUES ('2 spCargarCatalogo', @r);

EXEC dbo.spCargarOperacionesXML @r OUTPUT;
INSERT INTO @resultados VALUES ('3 spCargarOperacionesXML', @r);

EXEC dbo.spSimulacion @r OUTPUT;
INSERT INTO @resultados VALUES ('4 spSimulacion', @r);

-- correrla otra vez no debe hacer nada (52018)
EXEC dbo.spSimulacion @r OUTPUT;
INSERT INTO @resultados VALUES ('5 spSimulacion otra vez (esperado 52018)', @r);

-- resultado de cada paso: 0, 0, 0, 0 y 52018
SELECT R.Paso
    , R.Obtenido
    , DATEDIFF(SECOND, @inicio, GETDATE()) AS SegundosTotales
FROM @resultados AS R;

-- 2. resumen de datos
-- esperado: Fechas procesadas 122, Persona 15, Cuenta 10, Beneficiario 11,
-- Usuario 10, UsuarioPuedeVer 11, Comprobante 100,
-- EstadoCuenta 37 (27 cerrados + 10 abiertos)
SELECT 'Fechas procesadas' AS Dato, COUNT(1) AS Cantidad FROM dbo.ControlSimulacion WHERE (FlagTerminado = 1)
UNION ALL SELECT 'Persona', COUNT(1) FROM dbo.Persona
UNION ALL SELECT 'Cuenta', COUNT(1) FROM dbo.Cuenta
UNION ALL SELECT 'Beneficiario', COUNT(1) FROM dbo.Beneficiario
UNION ALL SELECT 'Usuario', COUNT(1) FROM dbo.Usuario
UNION ALL SELECT 'UsuarioPuedeVer', COUNT(1) FROM dbo.UsuarioPuedeVer
UNION ALL SELECT 'Movimiento', COUNT(1) FROM dbo.Movimiento
UNION ALL SELECT 'Comprobante', COUNT(1) FROM dbo.Comprobante
UNION ALL SELECT 'EstadoCuenta cerrados', COUNT(1) FROM dbo.EstadoCuenta WHERE (FlagAbierto = 0)
UNION ALL SELECT 'EstadoCuenta abiertos', COUNT(1) FROM dbo.EstadoCuenta WHERE (FlagAbierto = 1);

-- 3. movimientos por tipo
SELECT TM.Nombre AS Tipo
    , COUNT(1) AS Cantidad
    , SUM(M.Monto) AS MontoTotal
FROM dbo.Movimiento AS M
INNER JOIN dbo.TipoMovimiento AS TM
    ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
GROUP BY TM.Nombre
ORDER BY TM.Nombre;

-- 4. saldo final de cada cuenta
SELECT C.NumeroCuenta
    , TCA.Nombre AS TipoCuenta
    , TM.Simbolo
    , C.Saldo
FROM dbo.Cuenta AS C
INNER JOIN dbo.TipoCuentaAhorro AS TCA
    ON (TCA.IdTipoCuentaAhorro = C.IdTipoCuentaAhorro)
INNER JOIN dbo.TipoMoneda AS TM
    ON (TM.IdTipoMoneda = TCA.IdTipoMoneda)
ORDER BY C.NumeroCuenta;

-- 5. estados de cuenta de todas las cuentas
SELECT C.NumeroCuenta
    , EC.NumeroPeriodo
    , EC.FechaInicio
    , EC.FechaFin
    , EC.FechaEmision
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
ORDER BY C.NumeroCuenta
    , EC.NumeroPeriodo;

-- 6. casos que el XML trae a propósito
-- 11000001 período 2: 12 operaciones ATM -> comisión ATM de 1 200 (4 x 300)
-- 11000003 período 2: 8 operaciones en ventana -> comisión ventana de 900 (3 x 300)
-- 11000004 período 2: saldo mínimo bajo 25 000 -> multa de 3 000
-- 11000005 2026-04-20: 3 comisiones sinpe de 1 000
SELECT C.NumeroCuenta
    , M.Fecha
    , TM.Nombre AS Tipo
    , M.Monto
    , M.Descripcion
FROM dbo.Movimiento AS M
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = M.IdCuenta)
INNER JOIN dbo.TipoMovimiento AS TM
    ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
WHERE (M.IdTipoMovimiento IN (6, 7, 10, 16)) -- comisiones y multas
ORDER BY C.NumeroCuenta
    , M.Fecha
    , M.IdMovimiento;

-- CUADRE A: el saldo de la cuenta es el NuevoSaldo de su último movimiento (0 filas)
SELECT C.NumeroCuenta
    , C.Saldo
    , M.NuevoSaldo AS SaldoUltimoMovimiento
FROM dbo.Cuenta AS C
INNER JOIN dbo.Movimiento AS M
    ON (M.IdMovimiento = (
        SELECT MAX(M2.IdMovimiento)
        FROM dbo.Movimiento AS M2
        WHERE (M2.IdCuenta = C.IdCuenta)
    ))
WHERE (C.Saldo <> M.NuevoSaldo);

-- CUADRE B: cada NuevoSaldo es el anterior más o menos el monto (0 filas)
SELECT X.NumeroCuenta
    , X.IdMovimiento
    , X.SaldoAnterior
    , X.Monto
    , X.NuevoSaldo
FROM (
    SELECT C.NumeroCuenta
        , M.IdMovimiento
        , M.Monto
        , M.NuevoSaldo
        , TM.Accion
        , LAG(M.NuevoSaldo, 1, 0) OVER (PARTITION BY M.IdCuenta ORDER BY M.IdMovimiento) AS SaldoAnterior
    FROM dbo.Movimiento AS M
    INNER JOIN dbo.Cuenta AS C
        ON (C.IdCuenta = M.IdCuenta)
    INNER JOIN dbo.TipoMovimiento AS TM
        ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
) AS X
WHERE (X.NuevoSaldo <> X.SaldoAnterior + CASE WHEN (X.Accion = 'Credito') THEN X.Monto ELSE -X.Monto END);

-- CUADRE C: saldo inicial + créditos - débitos = saldo final, por estado (0 filas)
SELECT C.NumeroCuenta
    , EC.NumeroPeriodo
    , EC.SaldoInicial
    , EC.SaldoFinal
    , EC.SaldoInicial + ISNULL(SUM(CASE WHEN (TM.Accion = 'Credito') THEN M.Monto ELSE -M.Monto END), 0) AS SaldoCalculado
FROM dbo.EstadoCuenta AS EC
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = EC.IdCuenta)
LEFT JOIN dbo.Movimiento AS M
    ON (M.IdEstadoCuenta = EC.IdEstadoCuenta)
LEFT JOIN dbo.TipoMovimiento AS TM
    ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
GROUP BY C.NumeroCuenta
    , EC.NumeroPeriodo
    , EC.SaldoInicial
    , EC.SaldoFinal
HAVING (EC.SaldoFinal <> EC.SaldoInicial + ISNULL(SUM(CASE WHEN (TM.Accion = 'Credito') THEN M.Monto ELSE -M.Monto END), 0));

-- CUADRE D: cada estado empieza el día después del anterior y con su saldo final (0 filas)
SELECT C.NumeroCuenta
    , ECA.NumeroPeriodo AS PeriodoAnterior
    , ECA.FechaFin
    , ECA.SaldoFinal
    , ECS.FechaInicio
    , ECS.SaldoInicial
FROM dbo.EstadoCuenta AS ECA
INNER JOIN dbo.EstadoCuenta AS ECS
    ON (ECS.IdCuenta = ECA.IdCuenta)
    AND (ECS.NumeroPeriodo = ECA.NumeroPeriodo + 1)
INNER JOIN dbo.Cuenta AS C
    ON (C.IdCuenta = ECA.IdCuenta)
WHERE (ECS.FechaInicio <> DATEADD(DAY, 1, ECA.FechaFin))
    OR (ECS.SaldoInicial <> ECA.SaldoFinal);

-- CUADRE E: cada cuenta tiene exactamente un estado abierto, con su saldo actual (0 filas)
SELECT C.NumeroCuenta
    , COUNT(EC.IdEstadoCuenta) AS EstadosAbiertos
FROM dbo.Cuenta AS C
LEFT JOIN dbo.EstadoCuenta AS EC
    ON (EC.IdCuenta = C.IdCuenta)
    AND (EC.FlagAbierto = 1)
GROUP BY C.IdCuenta
    , C.NumeroCuenta
    , C.Saldo
HAVING (COUNT(EC.IdEstadoCuenta) <> 1)
    OR (MAX(EC.SaldoFinal) <> C.Saldo);

-- nodos rechazados y errores de la corrida (esperado: ninguno)
SELECT E.ErrorNumber
    , E.ErrorProcedure
    , E.ErrorMessage
    , E.ErrorDateTime
FROM dbo.dbError AS E
WHERE (E.ErrorDateTime >= @inicio)
ORDER BY E.ErrorDateTime;
