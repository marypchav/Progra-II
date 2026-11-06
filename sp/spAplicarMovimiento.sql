CREATE OR ALTER PROCEDURE dbo.spAplicarMovimiento
    @inIdCuenta INT -- cuenta a la que se aplica el movimiento
    , @inIdTipoMovimiento INT -- tipo de movimiento (catálogo TipoMovimiento)
    , @inMonto MONEY -- monto positivo; la Accion del tipo dice si suma o resta
    , @inDescripcion NVARCHAR(128) -- descripción que viene en el XML
    , @inFechaOperacion DATE -- fecha de operación que se está simulando
    , @inIdOperacionXML INT -- nodo del XML que lo generó; NULL si lo genera el sistema (cierre)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spAplicarMovimiento
        @inIdCuenta = 1
        , @inIdTipoMovimiento = 9
        , @inMonto = 300000
        , @inDescripcion = N'A Distribuidora El Roble - factura 1077'
        , @inFechaOperacion = '2026-04-20'
        , @inIdOperacionXML = NULL
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    -- constantes
    DECLARE @true BIT = 1
        , @false BIT = 0
        , @accionCredito VARCHAR(16) = 'Credito'
        , @tipoDepositoVentana INT = 1 -- ids del catálogo TipoMovimiento
        , @tipoDepositoATM INT = 2
        , @tipoRetiroATM INT = 4
        , @tipoRetiroVentana INT = 5
        , @tipoDepositoSinpe INT = 8
        , @tipoRetiroSinpe INT = 9
        , @tipoComisionSinpe INT = 10;

    -- variables de uso general
    DECLARE @transaccionPropia BIT = 0 -- 1 = este SP abrió la transacción
        , @accion VARCHAR(16)
        , @nombreTipo VARCHAR(64)
        , @flagComprobante BIT
        , @saldoActual MONEY
        , @numeroCuenta VARCHAR(20)
        , @email VARCHAR(64)
        , @maxSinpeDiario MONEY
        , @comisionSinpe MONEY
        , @idEstadoCuenta INT
        , @fechaFinEstado DATE;

    BEGIN TRY

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @accion = NULL;
        SET @saldoActual = NULL;
        SET @idEstadoCuenta = NULL;

        -- validaciones
        -- el monto debe ser positivo
        IF (@inMonto IS NULL)
            OR (@inMonto <= 0)
        BEGIN
            SET @outResultCode = 52003; -- monto inválido
            RETURN;
        END;

        -- el tipo de movimiento debe existir
        SELECT @accion = TM.Accion
            , @nombreTipo = TM.Nombre
            , @flagComprobante = TM.FlagGeneraComprobante
        FROM dbo.TipoMovimiento AS TM
        WHERE (TM.IdTipoMovimiento = @inIdTipoMovimiento);

        IF (@accion IS NULL)
        BEGIN
            SET @outResultCode = 52002; -- tipo de movimiento no existe
            RETURN;
        END;

        -- la cuenta debe existir. se traen también el email del dueño (para el
        -- comprobante) y los límites sinpe de su tipo de cuenta
        SELECT @saldoActual = C.Saldo
            , @numeroCuenta = C.NumeroCuenta
            , @email = P.Email
            , @maxSinpeDiario = TCA.MaxDiarioSinpeSinComision
            , @comisionSinpe = TCA.ComisionSinpeExceso
        FROM dbo.Cuenta AS C
        INNER JOIN dbo.Persona AS P
            ON (P.IdPersona = C.IdPersonaDueno)
        INNER JOIN dbo.TipoCuentaAhorro AS TCA
            ON (TCA.IdTipoCuentaAhorro = C.IdTipoCuentaAhorro)
        WHERE (C.IdCuenta = @inIdCuenta);

        IF (@saldoActual IS NULL)
        BEGIN
            SET @outResultCode = 50014; -- cuenta no existe
            RETURN;
        END;

        -- si el nodo del XML ya se aplicó (reinicio de la simulación), no se repite
        IF (@inIdOperacionXML IS NOT NULL)
            AND EXISTS (
                SELECT 1
                FROM dbo.Movimiento AS M
                WHERE (M.IdOperacionXML = @inIdOperacionXML)
                    AND (M.IdTipoMovimiento = @inIdTipoMovimiento)
            )
        BEGIN
            RETURN; -- ya aplicado: éxito sin hacer nada
        END;

        -- debe haber un estado de cuenta abierto
        SELECT @idEstadoCuenta = EC.IdEstadoCuenta
            , @fechaFinEstado = EC.FechaFin
        FROM dbo.EstadoCuenta AS EC
        WHERE (EC.IdCuenta = @inIdCuenta)
            AND (EC.FlagAbierto = @true);

        IF (@idEstadoCuenta IS NULL)
        BEGIN
            SET @outResultCode = 52004; -- la cuenta no tiene estado abierto
            RETURN;
        END;

        -- la fecha no puede pasar el fin del estado abierto: significaría que
        -- no se hizo un cierre (se "brincó" una fecha)
        IF (@inFechaOperacion > @fechaFinEstado)
        BEGIN
            SET @outResultCode = 52005; -- fecha posterior al cierre pendiente
            RETURN;
        END;

        -- un débito del cliente no puede dejar la cuenta en negativo
        IF (@accion <> @accionCredito)
            AND (@inIdOperacionXML IS NOT NULL)
            AND (@saldoActual < @inMonto)
        BEGIN
            SET @outResultCode = 52006; -- saldo insuficiente
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @saldoMovimiento MONEY -- saldo después del movimiento
            , @saldoFinal MONEY -- saldo después del movimiento y de la comisión sinpe
            , @sinpeAcumulado MONEY
            , @cobrarComision BIT
            , @sumaATM INT
            , @sumaVentana INT
            , @sumaSinpe INT
            , @idMovimiento INT
            , @detalle NVARCHAR(256);

        -- preprocesamiento
        SET @saldoMovimiento = CASE
                WHEN (@accion = @accionCredito) THEN @saldoActual + @inMonto
                ELSE @saldoActual - @inMonto
            END;

        -- sinpe: suma de los envíos de hoy (incluyendo este). si supera el
        -- máximo diario del tipo de cuenta, se cobra comisión por este envío
        SELECT @sinpeAcumulado = ISNULL(SUM(M.Monto), 0) + @inMonto
        FROM dbo.Movimiento AS M
        WHERE (M.IdCuenta = @inIdCuenta)
            AND (M.Fecha = @inFechaOperacion)
            AND (M.IdTipoMovimiento = @tipoRetiroSinpe);

        SET @cobrarComision = CASE
                WHEN (@inIdTipoMovimiento = @tipoRetiroSinpe)
                    AND (@sinpeAcumulado > @maxSinpeDiario) THEN @true
                ELSE @false
            END;

        SET @saldoFinal = @saldoMovimiento - CASE
                WHEN (@cobrarComision = @true) THEN @comisionSinpe
                ELSE 0
            END;

        -- cuál contador del estado de cuenta suma esta operación
        SET @sumaATM = CASE
                WHEN (@inIdTipoMovimiento IN (@tipoDepositoATM, @tipoRetiroATM)) THEN 1
                ELSE 0
            END;
        SET @sumaVentana = CASE
                WHEN (@inIdTipoMovimiento IN (@tipoDepositoVentana, @tipoRetiroVentana)) THEN 1
                ELSE 0
            END;
        SET @sumaSinpe = CASE
                WHEN (@inIdTipoMovimiento IN (@tipoDepositoSinpe, @tipoRetiroSinpe)) THEN 1
                ELSE 0
            END;

        -- texto del comprobante que llega al email del dueño
        SET @detalle = LEFT(CONCAT(
                @nombreTipo, N' por ', FORMAT(@inMonto, 'N2')
                , N' en la cuenta ', @numeroCuenta
                , N' el ', CONVERT(VARCHAR(10), @inFechaOperacion, 23)
                , N'. ', @inDescripcion
                , N'. Nuevo saldo: ', FORMAT(@saldoMovimiento, 'N2')
            ), 256);

        -- transacción: solo se abre si quien llamó no tiene una abierta
        IF (@@TRANCOUNT = 0)
        BEGIN
            BEGIN TRANSACTION tAplicarMovimiento;
            SET @transaccionPropia = @true;
        END;

            -- el movimiento, con el saldo que dejó
            INSERT INTO dbo.Movimiento (
                IdCuenta
                , IdEstadoCuenta
                , IdTipoMovimiento
                , IdOperacionXML
                , Fecha
                , Monto
                , NuevoSaldo
                , Descripcion
            )
            VALUES (
                @inIdCuenta
                , @idEstadoCuenta
                , @inIdTipoMovimiento
                , @inIdOperacionXML
                , @inFechaOperacion
                , @inMonto
                , @saldoMovimiento
                , @inDescripcion
            );

            SET @idMovimiento = SCOPE_IDENTITY();

            -- comprobante solo si el tipo lo indica. Sin IF: el WHERE decide
            INSERT INTO dbo.Comprobante (
                IdMovimiento
                , Email
                , Detalle
            )
            SELECT @idMovimiento
                , @email
                , @detalle
            WHERE (@flagComprobante = @true);

            -- segundo movimiento: comisión sinpe, solo si se superó el máximo diario
            INSERT INTO dbo.Movimiento (
                IdCuenta
                , IdEstadoCuenta
                , IdTipoMovimiento
                , IdOperacionXML
                , Fecha
                , Monto
                , NuevoSaldo
                , Descripcion
            )
            SELECT @inIdCuenta
                , @idEstadoCuenta
                , @tipoComisionSinpe
                , @inIdOperacionXML
                , @inFechaOperacion
                , @comisionSinpe
                , @saldoFinal
                , N'Comisión por exceso de envíos Sinpe del día'
            WHERE (@cobrarComision = @true);

            -- saldo de la cuenta
            UPDATE dbo.Cuenta
            SET Saldo = @saldoFinal
            WHERE (IdCuenta = @inIdCuenta);

            -- estado de cuenta abierto. el saldo mínimo NULL (primer período
            -- sin movimientos) se reemplaza por el primer saldo real
            UPDATE dbo.EstadoCuenta
            SET SaldoFinal = @saldoFinal
                , SaldoMinimo = CASE
                    WHEN (SaldoMinimo IS NULL) OR (@saldoFinal < SaldoMinimo) THEN @saldoFinal
                    ELSE SaldoMinimo
                  END
                , CantOperATM = CantOperATM + @sumaATM
                , CantOperVentana = CantOperVentana + @sumaVentana
                , CantOperSinpe = CantOperSinpe + @sumaSinpe
            WHERE (IdEstadoCuenta = @idEstadoCuenta);

        IF (@transaccionPropia = @true)
        BEGIN
            COMMIT TRANSACTION tAplicarMovimiento;
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