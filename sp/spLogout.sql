CREATE OR ALTER PROCEDURE dbo.spLogout
    @inIdUsuario INT -- quién cierra sesión
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spLogout
        @inIdUsuario = 1
        , @inIP = '127.0.0.1'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @tipoOperacionLogout INT = 2; -- TipoOperacion "Logout" del catálogo

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito

        -- validaciones
        -- el usuario debe existir (Bitacora.IdUsuario es llave foránea)
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuario AS U
            WHERE (U.IdUsuario = @inIdUsuario)
        )
        BEGIN
            SET @outResultCode = 50001; -- usuario no existe
            RETURN;
        END;

        -- actualización: registra el logout en la bitácora.
        -- DatosAntes y DatosDespues quedan en NULL porque un logout no modifica datos
        INSERT INTO dbo.Bitacora (
            IdUsuario
            , IdTipoOperacion
            , IP
        )
        VALUES (
            @inIdUsuario
            , @tipoOperacionLogout
            , @inIP
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
