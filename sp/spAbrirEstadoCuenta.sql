CREATE OR ALTER PROCEDURE dbo.spAbrirEstadoCuenta
    @inIdCuenta INT -- cuenta a la que se le abre el siguiente estado de cuenta
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Abre el estado de cuenta que sigue al último estado (ya cerrado) de la cuenta.
El primer estado NO lo abre este SP: lo abre el trigger trCuentaPrimerEstado.

Período: desde el día siguiente al cierre anterior hasta FechaCreacion + n meses.
Ejemplo: cuenta creada el 2026-03-10, período 2 -> del 2026-04-11 al 2026-05-10.
Se calcula desde FechaCreacion (y no desde la FechaFin anterior) para que una
cuenta creada un 31 cierre el 30/31 de cada mes y no se quede pegada en 30.

Transacción: si ya hay una transacción abierta (la de spCerrarEstadoCuenta),
trabaja dentro de ella; si no, abre la suya.

Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAbrirEstadoCuenta
        @inIdCuenta = 1
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- constantes
    DECLARE @true BIT = 1
        , @false BIT = 0;

    -- variables de uso general
    DECLARE @transaccionPropia BIT = 0 -- 1 = este SP abrió la transacción
        , @numeroPeriodo INT
        , @fechaInicio DATE
        , @fechaFin DATE
        , @saldoActual MONEY;

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @numeroPeriodo = NULL;

        -- validaciones
        -- la cuenta debe existir
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Cuenta AS C
            WHERE (C.IdCuenta = @inIdCuenta)
        )
        BEGIN
            SET @outResultCode = 50014; -- cuenta no existe
            RETURN;
        END;

        -- no puede haber otro estado abierto
        IF EXISTS (
            SELECT 1
            FROM dbo.EstadoCuenta AS EC
            WHERE (EC.IdCuenta = @inIdCuenta)
                AND (EC.FlagAbierto = @true)
        )
        BEGIN
            SET @outResultCode = 52001; -- ya tiene un estado abierto
            RETURN;
        END;

        -- preprocesamiento
        -- el nuevo período sigue al último estado de la cuenta
        SELECT TOP (1) @numeroPeriodo = EC.NumeroPeriodo + 1
            , @fechaInicio = DATEADD(DAY, 1, EC.FechaFin)
        FROM dbo.EstadoCuenta AS EC
        WHERE (EC.IdCuenta = @inIdCuenta)
        ORDER BY EC.NumeroPeriodo DESC;

        IF (@numeroPeriodo IS NULL)
        BEGIN
            SET @outResultCode = 52007; -- no tiene estado previo (el primero lo abre el trigger)
            RETURN;
        END;

        -- fin del período y saldo con el que arranca
        SELECT @fechaFin = DATEADD(MONTH, @numeroPeriodo, C.FechaCreacion)
            , @saldoActual = C.Saldo
        FROM dbo.Cuenta AS C
        WHERE (C.IdCuenta = @inIdCuenta);

        -- transacción: solo se abre si quien llamó no tiene una abierta
        IF (@@TRANCOUNT = 0)
        BEGIN
            BEGIN TRANSACTION tAbrirEstadoCuenta;
            SET @transaccionPropia = @true;
        END;

            -- a diferencia del primer estado, aquí el saldo mínimo arranca con
            -- el saldo inicial: ese saldo sí lo tuvo la cuenta en el período
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
            VALUES (
                @inIdCuenta
                , @numeroPeriodo
                , @fechaInicio
                , @fechaFin
                , NULL
                , @saldoActual
                , @saldoActual
                , @saldoActual
                , 0
                , 0
                , 0
                , 0
                , @true
            );

        IF (@transaccionPropia = @true)
        BEGIN
            COMMIT TRANSACTION tAbrirEstadoCuenta;
        END;

    END TRY
    BEGIN CATCH

        -- si la transacción es de quien llamó, el error se le pasa a él:
        -- él hace el ROLLBACK de todo y lo registra en dbError
        IF (@transaccionPropia = 0)
            AND (@@TRANCOUNT > 0)
        BEGIN
            THROW;
        END;

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        -- registra el error en la tabla de errores
        INSERT INTO dbo.dbError (
            UserName
            , ErrorNumber
            , ErrorState
            , ErrorSeverity
            , ErrorLine
            , ErrorProcedure
            , ErrorMessage
            , ErrorDateTime
        )
        VALUES (
            SUSER_SNAME()
            , ERROR_NUMBER()
            , ERROR_STATE()
            , ERROR_SEVERITY()
            , ERROR_LINE()
            , ERROR_PROCEDURE()
            , ERROR_MESSAGE()
            , GETDATE()
        );

        SET @outResultCode = 50000; -- error inesperado

    END CATCH;

    SET NOCOUNT OFF;
END;
GO