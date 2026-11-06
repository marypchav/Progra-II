CREATE OR ALTER PROCEDURE dbo.spCerrarEstadoCuenta
    @inIdEstadoCuenta INT -- estado de cuenta (abierto) que se cierra
    , @inFechaOperacion DATE -- fecha de operación que se está simulando
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spCerrarEstadoCuenta
        @inIdEstadoCuenta = 1
        , @inFechaOperacion = '2026-04-01'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- constantes
    DECLARE @true BIT = 1
        , @false BIT = 0
        , @tipoComisionVentana INT = 6 -- ids del catálogo TipoMovimiento
        , @tipoComisionATM INT = 7
        , @tipoCargoServicio INT = 11
        , @tipoIntereses INT = 12
        , @tipoMultaSaldoMinimo INT = 16
        , @mesesPorAnio DECIMAL(5, 2) = 12
        , @cien DECIMAL(5, 2) = 100;

    -- variables de uso general
    DECLARE @transaccionPropia BIT = 0 -- 1 = este SP abrió la transacción
        , @idCuenta INT
        , @fechaInicio DATE
        , @fechaCierre DATE
        , @flagAbierto BIT
        , @saldoMinimo MONEY
        , @cantATM INT
        , @cantVentana INT
        , @resultadoInterno INT
        , @mensajeError NVARCHAR(2048);

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @idCuenta = NULL;
        SET @resultadoInterno = 0;

        -- validaciones
        -- el estado debe existir y estar abierto
        SELECT @idCuenta = EC.IdCuenta
            , @fechaInicio = EC.FechaInicio
            , @fechaCierre = EC.FechaFin
            , @flagAbierto = EC.FlagAbierto
            , @saldoMinimo = ISNULL(EC.SaldoMinimo, EC.SaldoInicial) -- período sin movimientos
            , @cantATM = EC.CantOperATM
            , @cantVentana = EC.CantOperVentana
        FROM dbo.EstadoCuenta AS EC
        WHERE (EC.IdEstadoCuenta = @inIdEstadoCuenta);

        IF (@idCuenta IS NULL)
            OR (@flagAbierto = @false)
        BEGIN
            SET @outResultCode = 52008; -- no existe o ya está cerrado
            RETURN;
        END;

        -- todavía no llega el día de cierre
        IF (@inFechaOperacion < @fechaCierre)
        BEGIN
            SET @outResultCode = 52009; -- aún no corresponde cerrar
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @intereses MONEY
            , @comisionATM MONEY
            , @comisionVentana MONEY
            , @multaSaldoMinimo MONEY
            , @cargoServicio MONEY
            , @excesoATM INT
            , @excesoVentana INT
            , @periodo NVARCHAR(40);

        -- preprocesamiento: todos los montos se calculan antes de aplicar
        -- cualquier movimiento, con los datos del período tal como quedó
        SELECT @intereses = ROUND(@saldoMinimo * TCA.TasaInteresAnual / @cien / @mesesPorAnio, 2)
            , @excesoATM = @cantATM - TCA.MaxOperAutomaticoGratis
            , @excesoVentana = @cantVentana - TCA.MaxOperHumanoGratis
            , @comisionATM = CASE
                WHEN (@cantATM > TCA.MaxOperAutomaticoGratis)
                THEN (@cantATM - TCA.MaxOperAutomaticoGratis) * TCA.ComisionAutomaticoExceso
                ELSE 0
              END
            , @comisionVentana = CASE
                WHEN (@cantVentana > TCA.MaxOperHumanoGratis)
                THEN (@cantVentana - TCA.MaxOperHumanoGratis) * TCA.ComisionHumanoExceso
                ELSE 0
              END
            , @multaSaldoMinimo = CASE
                WHEN (@saldoMinimo < TCA.SaldoMinimo) THEN TCA.MultaSaldoMin
                ELSE 0
              END
            , @cargoServicio = TCA.CargoMensualServicio
        FROM dbo.Cuenta AS C
        INNER JOIN dbo.TipoCuentaAhorro AS TCA
            ON (TCA.IdTipoCuentaAhorro = C.IdTipoCuentaAhorro)
        WHERE (C.IdCuenta = @idCuenta);

        SET @periodo = CONCAT(
                CONVERT(VARCHAR(10), @fechaInicio, 23)
                , N' al '
                , CONVERT(VARCHAR(10), @fechaCierre, 23)
            );

        -- transacción: solo se abre si quien llamó no tiene una abierta
        IF (@@TRANCOUNT = 0)
        BEGIN
            BEGIN TRANSACTION tCerrarEstadoCuenta;
            SET @transaccionPropia = @true;
        END;

            -- 1. intereses sobre el saldo mínimo
            IF (@intereses > 0)
            BEGIN
                SET @mensajeError = CONCAT(N'Intereses del período ', @periodo);
                EXEC dbo.spAplicarMovimiento
                    @inIdCuenta = @idCuenta
                    , @inIdTipoMovimiento = @tipoIntereses
                    , @inMonto = @intereses
                    , @inDescripcion = @mensajeError
                    , @inFechaOperacion = @fechaCierre
                    , @inIdOperacionXML = NULL
                    , @outResultCode = @resultadoInterno OUTPUT;

                IF (@resultadoInterno <> 0)
                BEGIN
                    SET @mensajeError = CONCAT(N'Intereses: spAplicarMovimiento devolvió ', @resultadoInterno);
                    THROW 52010, @mensajeError, 1;
                END;
            END;

            -- 2. comisión por exceso de operaciones en ATM
            IF (@comisionATM > 0)
            BEGIN
                SET @mensajeError = CONCAT(N'Comisión por ', @excesoATM, N' operaciones en ATM sobre el máximo');
                EXEC dbo.spAplicarMovimiento
                    @inIdCuenta = @idCuenta
                    , @inIdTipoMovimiento = @tipoComisionATM
                    , @inMonto = @comisionATM
                    , @inDescripcion = @mensajeError
                    , @inFechaOperacion = @fechaCierre
                    , @inIdOperacionXML = NULL
                    , @outResultCode = @resultadoInterno OUTPUT;

                IF (@resultadoInterno <> 0)
                BEGIN
                    SET @mensajeError = CONCAT(N'Comisión ATM: spAplicarMovimiento devolvió ', @resultadoInterno);
                    THROW 52010, @mensajeError, 1;
                END;
            END;

            -- 3. comisión por exceso de operaciones en ventana
            IF (@comisionVentana > 0)
            BEGIN
                SET @mensajeError = CONCAT(N'Comisión por ', @excesoVentana, N' operaciones en ventana sobre el máximo');
                EXEC dbo.spAplicarMovimiento
                    @inIdCuenta = @idCuenta
                    , @inIdTipoMovimiento = @tipoComisionVentana
                    , @inMonto = @comisionVentana
                    , @inDescripcion = @mensajeError
                    , @inFechaOperacion = @fechaCierre
                    , @inIdOperacionXML = NULL
                    , @outResultCode = @resultadoInterno OUTPUT;

                IF (@resultadoInterno <> 0)
                BEGIN
                    SET @mensajeError = CONCAT(N'Comisión ventana: spAplicarMovimiento devolvió ', @resultadoInterno);
                    THROW 52010, @mensajeError, 1;
                END;
            END;

            -- 4. multa por saldo mínimo
            IF (@multaSaldoMinimo > 0)
            BEGIN
                EXEC dbo.spAplicarMovimiento
                    @inIdCuenta = @idCuenta
                    , @inIdTipoMovimiento = @tipoMultaSaldoMinimo
                    , @inMonto = @multaSaldoMinimo
                    , @inDescripcion = N'Multa por saldo mínimo inferior al permitido'
                    , @inFechaOperacion = @fechaCierre
                    , @inIdOperacionXML = NULL
                    , @outResultCode = @resultadoInterno OUTPUT;

                IF (@resultadoInterno <> 0)
                BEGIN
                    SET @mensajeError = CONCAT(N'Multa: spAplicarMovimiento devolvió ', @resultadoInterno);
                    THROW 52010, @mensajeError, 1;
                END;
            END;

            -- 5. cargo mensual por servicio
            IF (@cargoServicio > 0)
            BEGIN
                EXEC dbo.spAplicarMovimiento
                    @inIdCuenta = @idCuenta
                    , @inIdTipoMovimiento = @tipoCargoServicio
                    , @inMonto = @cargoServicio
                    , @inDescripcion = N'Cargo mensual por servicio'
                    , @inFechaOperacion = @fechaCierre
                    , @inIdOperacionXML = NULL
                    , @outResultCode = @resultadoInterno OUTPUT;

                IF (@resultadoInterno <> 0)
                BEGIN
                    SET @mensajeError = CONCAT(N'Cargo servicio: spAplicarMovimiento devolvió ', @resultadoInterno);
                    THROW 52010, @mensajeError, 1;
                END;
            END;

            -- 6. cierra el estado. el saldo final ya lo dejó spAplicarMovimiento;
            -- el saldo mínimo se deja en el valor que se usó para los cálculos
            UPDATE dbo.EstadoCuenta
            SET FlagAbierto = @false
                , FechaEmision = @fechaCierre
                , InteresesAcumulados = @intereses
                , SaldoMinimo = @saldoMinimo
            WHERE (IdEstadoCuenta = @inIdEstadoCuenta);

            -- 7. abre el estado del período siguiente
            EXEC dbo.spAbrirEstadoCuenta
                @inIdCuenta = @idCuenta
                , @outResultCode = @resultadoInterno OUTPUT;

            IF (@resultadoInterno <> 0)
            BEGIN
                SET @mensajeError = CONCAT(N'Apertura: spAbrirEstadoCuenta devolvió ', @resultadoInterno);
                THROW 52010, @mensajeError, 1;
            END;

        IF (@transaccionPropia = @true)
        BEGIN
            COMMIT TRANSACTION tCerrarEstadoCuenta;
        END;

    END TRY
    BEGIN CATCH

        -- si la transacción es de quien llamó, el error se le pasa a él
        IF (@transaccionPropia = 0)
            AND (@@TRANCOUNT > 0)
        BEGIN
            THROW;
        END;

        -- si quedó una transacción abierta, se deshace todo el cierre
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

        -- 52010 = falló un paso interno del cierre (el detalle queda en dbError)
        SET @outResultCode = CASE
                WHEN (ERROR_NUMBER() = 52010) THEN 52010
                ELSE 50000 -- error inesperado
            END;

    END CATCH;

    SET NOCOUNT OFF;
END;
GO