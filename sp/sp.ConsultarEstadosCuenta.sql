CREATE OR ALTER PROCEDURE dbo.spConsultarEstadoCuenta
    @inIdUsuario INT -- quién consulta, para el acceso y la bitácora
    , @inIdCuenta INT -- de qué cuenta se piden los estados
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spConsultarEstadoCuenta
        @inIdUsuario = 1
        , @inIdCuenta = 1
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
            , @tipoOperacionConsultarEstado INT = 7 -- TipoOperacion del catálogo
            , @cantidadEstados INT = 8; -- cuántos estados se muestran

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @jsonConsulta NVARCHAR(MAX);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;

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

        -- el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer.
        -- los intentos rechazados no quedan en la bitácora
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario);

        IF (@esAdministrador = @false)
            AND NOT EXISTS (
                SELECT 1
                FROM dbo.UsuarioPuedeVer AS UPV
                WHERE (UPV.IdUsuario = @inIdUsuario)
                    AND (UPV.IdCuenta = @inIdCuenta)
            )
        BEGIN
            SET @outResultCode = 50002; -- sin acceso a la cuenta
            RETURN;
        END;

        -- preprocesamiento: JSON con el número de cuenta consultada, para la bitácora
        SET @jsonConsulta = (
            SELECT C.NumeroCuenta
            FROM dbo.Cuenta AS C
            WHERE (C.IdCuenta = @inIdCuenta)
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- devuelve los últimos estados: TOP limita las filas y el ORDER BY
        -- (fecha más reciente primero) decide cuáles son los últimos
        SELECT TOP (@cantidadEstados)
            EC.IdEstadoCuenta
            , EC.FechaInicio
            , EC.FechaFin
            , EC.FechaEmision
            , EC.SaldoInicial
            , EC.SaldoFinal
            , EC.SaldoMinimo
            , EC.InteresesAcumulados
            , EC.CantRetiros
            , EC.CantDepositos
            , EC.CantSinpeEntrantes
            , EC.CantSinpeSalientes
        FROM dbo.EstadoCuenta AS EC
        WHERE (EC.IdCuenta = @inIdCuenta)
        ORDER BY EC.FechaEmision DESC
            , EC.IdEstadoCuenta DESC;

        -- actualización: registra la consulta en la bitácora.
        -- DatosAntes queda en NULL; en DatosDespues va la cuenta consultada
        INSERT INTO dbo.Bitacora (
            IdUsuario
            , IdTipoOperacion
            , IP
            , DatosAntes
            , DatosDespues
        )
        VALUES (
            @inIdUsuario
            , @tipoOperacionConsultarEstado
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
