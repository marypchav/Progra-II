CREATE OR ALTER TRIGGER dbo.trCuentaPrimerEstado
ON dbo.Cuenta
AFTER INSERT
AS
/*
Ejemplo:
    INSERT INTO dbo.Cuenta (NumeroCuenta, IdPersonaDueno, IdTipoCuentaAhorro, FechaCreacion, Saldo)
    VALUES ('11000001', 1, 1, '2026-03-01', 0);
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- constantes
    DECLARE @primerPeriodo INT = 1
        , @true BIT = 1;

    -- si el INSERT no insertó filas, no hay nada que abrir
    IF NOT EXISTS (
        SELECT 1
        FROM inserted AS I
    )
    BEGIN
        RETURN;
    END;

    -- un estado por cada cuenta insertada. Se trabaja sobre "inserted" completo
    -- (no con variables) porque un solo INSERT puede traer varias cuentas
    INSERT INTO dbo.EstadoCuenta (
        IdCuenta
        , NumeroPeriodo
        , FechaInicio
        , FechaFin
        , FechaEmision
        , SaldoInicial
        , SaldoFinal
        , SaldoMinimo
        , InteresesAcumulados
        , CantOperATM
        , CantOperVentana
        , CantOperSinpe
        , FlagAbierto
    )
    SELECT I.IdCuenta
        , @primerPeriodo
        , I.FechaCreacion
        , DATEADD(MONTH, @primerPeriodo, I.FechaCreacion) -- mismo día del mes siguiente
        , NULL -- se llena al cerrar
        , I.Saldo -- la cuenta nace en 0
        , I.Saldo
        , NULL -- NULL hasta el primer movimiento, para no cobrar multa por el 0 inicial
        , 0
        , 0
        , 0
        , 0
        , @true
    FROM inserted AS I;

    SET NOCOUNT OFF;
END;
GO