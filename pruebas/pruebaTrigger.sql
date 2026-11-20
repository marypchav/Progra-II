/*
pruebaTrigger.sql
Prueba de trCuentaPrimerEstado. Todo corre dentro de una transacción que al
final se deshace (ROLLBACK), así que no deja datos en la base.
Requiere los catálogos cargados (spCargarCatalogo).
*/

BEGIN TRANSACTION tPruebaTrigger;

    -- persona de prueba (dueña de las cuentas)
    INSERT INTO dbo.Persona (
        IdTipoDocuIdentidad
        , ValorDocumentoIdentidad
        , Nombre
        , FechaNacimiento
        , Email
        , Telefono1
        , Telefono2
    )
    VALUES (
        1
        , '999999999'
        , 'Persona de Prueba'
        , '1990-01-01'
        , 'prueba@ejemplo.com'
        , '88888888'
        , '22222222'
    );

    -- tres cuentas en UN solo INSERT: prueba que el trigger maneja varias filas
    INSERT INTO dbo.Cuenta (
        NumeroCuenta
        , IdPersonaDueno
        , IdTipoCuentaAhorro
        , FechaCreacion
        , Saldo
    )
    SELECT C.NumeroCuenta
        , P.IdPersona
        , C.IdTipoCuentaAhorro
        , C.FechaCreacion
        , 0
    FROM (
        VALUES ('99000001', 1, CAST('2026-03-01' AS DATE)) -- caso normal
            , ('99000002', 1, CAST('2026-03-31' AS DATE)) -- fin de mes: debe cerrar el 2026-04-30
            , ('99000003', 4, CAST('2026-01-31' AS DATE)) -- febrero: debe cerrar el 2026-02-28
    ) AS C (NumeroCuenta, IdTipoCuentaAhorro, FechaCreacion)
    INNER JOIN dbo.Persona AS P
        ON (P.ValorDocumentoIdentidad = '999999999');

    -- resultado esperado: 3 filas, NumeroPeriodo 1, FlagAbierto 1,
    -- SaldoMinimo NULL y FechaFin 2026-04-01 / 2026-04-30 / 2026-02-28
    SELECT C.NumeroCuenta
        , EC.NumeroPeriodo
        , EC.FechaInicio
        , EC.FechaFin
        , EC.SaldoInicial
        , EC.SaldoMinimo
        , EC.FlagAbierto
    FROM dbo.EstadoCuenta AS EC
    INNER JOIN dbo.Cuenta AS C
        ON (C.IdCuenta = EC.IdCuenta)
    WHERE (C.NumeroCuenta LIKE '99%')
    ORDER BY C.NumeroCuenta;

ROLLBACK TRANSACTION tPruebaTrigger; -- deja la base como estaba
