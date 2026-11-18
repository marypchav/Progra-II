CREATE OR ALTER PROCEDURE dbo.spConsultarMovimientosEstado
    @inIdUsuario INT -- quién consulta, para el acceso y la bitácora
    , @inIdEstadoCuenta INT -- estado de cuenta que se consulta
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spConsultarMovimientosEstado
        @inIdUsuario = 1
        , @inIdEstadoCuenta = 1
        , @inIP = '127.0.0.1'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionConsultarMovimientos INT = 8; -- TipoOperacion del catálogo

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @idCuenta INT
            , @jsonConsulta NVARCHAR(MAX);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @idCuenta = NULL;

        -- validaciones
        -- el estado de cuenta debe existir; de él se obtiene la cuenta
        SELECT @idCuenta = EC.IdCuenta
        FROM dbo.EstadoCuenta AS EC
        WHERE (EC.IdEstadoCuenta = @inIdEstadoCuenta);

        IF (@idCuenta IS NULL)
        BEGIN
            SET @outResultCode = 50015; -- estado de cuenta no existe
            RETURN;
        END;

        -- el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer.
        -- la cuenta se deduce del estado (no se recibe) para que nadie pueda
        -- pedir un estado de una cuenta que no puede ver
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario);

        IF (@esAdministrador = @false)
            AND NOT EXISTS (
                SELECT 1
                FROM dbo.UsuarioPuedeVer AS UPV
                WHERE (UPV.IdUsuario = @inIdUsuario)
                    AND (UPV.IdCuenta = @idCuenta)
            )
        BEGIN
            SET @outResultCode = 50002; -- sin acceso a la cuenta
            RETURN;
        END;

        -- preprocesamiento: JSON con el estado consultado, para la bitácora
        SET @jsonConsulta = (
            SELECT C.NumeroCuenta
                , EC.NumeroPeriodo
                , EC.FechaInicio
                , EC.FechaFin
            FROM dbo.EstadoCuenta AS EC
            INNER JOIN dbo.Cuenta AS C
                ON (C.IdCuenta = EC.IdCuenta)
            WHERE (EC.IdEstadoCuenta = @inIdEstadoCuenta)
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- primer resultado: datos del estado de cuenta, con el símbolo de la moneda
        SELECT EC.IdEstadoCuenta
            , C.NumeroCuenta
            , TMO.Simbolo
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
            , EC.CantOperSinpe
            , EC.FlagAbierto
        FROM dbo.EstadoCuenta AS EC
        INNER JOIN dbo.Cuenta AS C
            ON (C.IdCuenta = EC.IdCuenta)
        INNER JOIN dbo.TipoCuentaAhorro AS TCA
            ON (TCA.IdTipoCuentaAhorro = C.IdTipoCuentaAhorro)
        INNER JOIN dbo.TipoMoneda AS TMO
            ON (TMO.IdTipoMoneda = TCA.IdTipoMoneda)
        WHERE (EC.IdEstadoCuenta = @inIdEstadoCuenta);

        -- segundo resultado: movimientos en orden cronológico.
        -- Accion dice si el monto suma (Credito) o resta (Debito)
        SELECT M.IdMovimiento
            , M.Fecha
            , TM.Nombre AS TipoMovimiento
            , TM.Accion
            , M.Monto
            , M.NuevoSaldo
            , M.Descripcion
        FROM dbo.Movimiento AS M
        INNER JOIN dbo.TipoMovimiento AS TM
            ON (TM.IdTipoMovimiento = M.IdTipoMovimiento)
        WHERE (M.IdEstadoCuenta = @inIdEstadoCuenta)
        ORDER BY M.Fecha
            , M.IdMovimiento;

        -- actualización: registra la consulta en la bitácora
        INSERT INTO dbo.Bitacora (
            IdUsuario
            , IdTipoOperacion
            , IP
            , DatosAntes
            , DatosDespues
        )
        VALUES (
            @inIdUsuario
            , @tipoOperacionConsultarMovimientos
            , @inIP
            , NULL
            , @jsonConsulta
        );

    END TRY
    BEGIN CATCH

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