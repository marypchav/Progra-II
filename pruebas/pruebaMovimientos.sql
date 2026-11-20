/*
pruebaMovimientos.sql
Prueba de spAplicarMovimiento y spAbrirEstadoCuenta.
Requiere: catálogos cargados, trigger trCuentaPrimerEstado y los dos SPs compilados.
Al final limpia la base y recarga los catálogos (spLimpiarBD + spCargarCatalogo).
*/

DECLARE @r INT
    , @idCuenta INT
    , @idOp1 INT
    , @idOp2 INT;

DECLARE @resultados TABLE (
    Paso VARCHAR(80)
    , Esperado INT
    , Obtenido INT
);

-- datos de prueba
INSERT INTO dbo.Persona (IdTipoDocuIdentidad, ValorDocumentoIdentidad, Nombre, FechaNacimiento, Email, Telefono1, Telefono2)
VALUES (1, '999999999', 'Persona de Prueba', '1990-01-01', 'prueba@ejemplo.com', '88888888', '22222222');

INSERT INTO dbo.Cuenta (NumeroCuenta, IdPersonaDueno, IdTipoCuentaAhorro, FechaCreacion, Saldo)
SELECT '99000001', P.IdPersona, 3, '2026-03-10', 0
FROM dbo.Persona AS P
WHERE (P.ValorDocumentoIdentidad = '999999999');

SELECT @idCuenta = C.IdCuenta
FROM dbo.Cuenta AS C
WHERE (C.NumeroCuenta = '99000001');

-- dos nodos falsos del XML, para probar el reinicio y el saldo insuficiente
INSERT INTO dbo.OperacionXML (FechaOperacion, Orden, TipoNodo, Nodo)
VALUES ('2026-03-13', 6, 'Movimientos', '<Movimientos/>');
SET @idOp1 = SCOPE_IDENTITY();

INSERT INTO dbo.OperacionXML (FechaOperacion, Orden, TipoNodo, Nodo)
VALUES ('2026-03-13', 6, 'Movimientos', '<Movimientos/>');
SET @idOp2 = SCOPE_IDENTITY();

-- 1. depósito de apertura en ventana (genera comprobante)
EXEC dbo.spAplicarMovimiento @idCuenta, 1, 2500000, N'Depósito de apertura', '2026-03-10', NULL, @r OUTPUT;
INSERT INTO @resultados VALUES ('1 Deposito ventana 2 500 000', 0, @r);

-- 2-4. tres envíos sinpe el mismo día: 250k (acum 250k), 300k (acum 550k), 180k (acum 730k)
EXEC dbo.spAplicarMovimiento @idCuenta, 9, 250000, N'Sinpe 1', '2026-03-12', NULL, @r OUTPUT;
INSERT INTO @resultados VALUES ('2 Retiro sinpe 250 000 (sin comision)', 0, @r);

EXEC dbo.spAplicarMovimiento @idCuenta, 9, 300000, N'Sinpe 2', '2026-03-12', NULL, @r OUTPUT;
INSERT INTO @resultados VALUES ('3 Retiro sinpe 300 000 (con comision)', 0, @r);

EXEC dbo.spAplicarMovimiento @idCuenta, 9, 180000, N'Sinpe 3', '2026-03-12', NULL, @r OUTPUT;
INSERT INTO @resultados VALUES ('4 Retiro sinpe 180 000 (con comision)', 0, @r);

-- 5. retiro ATM que viene de un nodo del XML
EXEC dbo.spAplicarMovimiento @idCuenta, 4, 20000, N'Retiro ATM', '2026-03-13', @idOp1, @r OUTPUT;
INSERT INTO @resultados VALUES ('5 Retiro ATM 20 000', 0, @r);

-- 6. el mismo nodo otra vez (reinicio): éxito, pero NO debe crear otro movimiento
EXEC dbo.spAplicarMovimiento @idCuenta, 4, 20000, N'Retiro ATM', '2026-03-13', @idOp1, @r OUTPUT;
INSERT INTO @resultados VALUES ('6 Mismo nodo repetido (no se aplica)', 0, @r);

-- 7. retiro mayor al saldo
EXEC dbo.spAplicarMovimiento @idCuenta, 5, 5000000, N'Retiro grande', '2026-03-13', @idOp2, @r OUTPUT;
INSERT INTO @resultados VALUES ('7 Saldo insuficiente', 52006, @r);

-- 8. monto en cero
EXEC dbo.spAplicarMovimiento @idCuenta, 1, 0, N'Monto cero', '2026-03-13', NULL, @r OUTPUT;
INSERT INTO @resultados VALUES ('8 Monto invalido', 52003, @r);

-- 9. fecha posterior al cierre del estado abierto (2026-04-10)
EXEC dbo.spAplicarMovimiento @idCuenta, 1, 1000, N'Fuera de periodo', '2026-04-15', NULL, @r OUTPUT;
INSERT INTO @resultados VALUES ('9 Fecha despues del cierre pendiente', 52005, @r);

-- 10. abrir estado cuando ya hay uno abierto
EXEC dbo.spAbrirEstadoCuenta @idCuenta, @r OUTPUT;
INSERT INTO @resultados VALUES ('10 Abrir con estado abierto', 52001, @r);

-- 11. se cierra a mano el período 1 (mañana lo hará spCerrarEstadoCuenta) y se abre el 2
UPDATE dbo.EstadoCuenta
SET FlagAbierto = 0
    , FechaEmision = FechaFin
WHERE (IdCuenta = @idCuenta);

EXEC dbo.spAbrirEstadoCuenta @idCuenta, @r OUTPUT;
INSERT INTO @resultados VALUES ('11 Abrir periodo 2', 0, @r);

-- resumen: la columna Ok debe ser 1 en todas las filas
SELECT R.Paso
    , R.Esperado
    , R.Obtenido
    , CASE WHEN (R.Esperado = R.Obtenido) THEN 1 ELSE 0 END AS Ok
FROM @resultados AS R;

-- movimientos: 7 filas (5 aplicados + 2 comisiones sinpe de 1 000)
-- saldos: 2 500 000 / 2 250 000 / 1 950 000 / 1 949 000 / 1 769 000 / 1 768 000 / 1 748 000
SELECT M.IdMovimiento
    , M.Fecha
    , TM.Nombre AS Tipo
    , M.Monto
    , M.NuevoSaldo
    , M.Descripcion
FROM dbo.Movimiento AS M
INNER JOIN dbo.TipoMovimiento AS TM
    ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
WHERE (M.IdCuenta = @idCuenta)
ORDER BY M.IdMovimiento;

-- comprobantes: 5 (depósito, 3 sinpe y ATM; las comisiones no generan)
SELECT CO.IdMovimiento
    , CO.Email
    , CO.Detalle
FROM dbo.Comprobante AS CO
ORDER BY CO.IdMovimiento;

-- estados:
-- período 1: SaldoFinal 1 748 000, SaldoMinimo 1 748 000, ATM 1, Ventana 1, Sinpe 3, cerrado
-- período 2: 2026-04-11 al 2026-05-10, SaldoInicial y SaldoMinimo 1 748 000, abierto
SELECT EC.NumeroPeriodo
    , EC.FechaInicio
    , EC.FechaFin
    , EC.SaldoInicial
    , EC.SaldoFinal
    , EC.SaldoMinimo
    , EC.CantOperATM
    , EC.CantOperVentana
    , EC.CantOperSinpe
    , EC.FlagAbierto
FROM dbo.EstadoCuenta AS EC
WHERE (EC.IdCuenta = @idCuenta)
ORDER BY EC.NumeroPeriodo;

-- saldo de la cuenta: 1 748 000
SELECT C.Saldo
FROM dbo.Cuenta AS C
WHERE (C.IdCuenta = @idCuenta);

-- errores inesperados: no debe haber ninguno nuevo
SELECT TOP 5 E.ErrorProcedure
    , E.ErrorMessage
    , E.ErrorDateTime
FROM dbo.dbError AS E
ORDER BY E.ErrorDateTime DESC;

-- limpieza: deja la base solo con catálogos
EXEC dbo.spLimpiarBD @r OUTPUT;
EXEC dbo.spCargarCatalogo @r OUTPUT;
