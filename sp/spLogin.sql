CREATE OR ALTER PROCEDURE dbo.spLogin
    @inUserName VARCHAR(64) -- usuario que intenta ingresar
    , @inPass VARCHAR(64) -- password que escribió
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS 
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spLogin
        @inUserName = 'jaguero'
        , @inPass = 'LaFacil'
        , @inIP = '127.0.0.1'
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @tipoOperacionLogin INT = 1; -- TipoOperacion "Login" del catálogo

        -- variables de uso general
        DECLARE @idUsuario INT; -- queda en NULL si no hay coincidencia

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @idUsuario = NULL;

        -- validaciones
        -- busca un usuario con ese nombre y ese password.
        -- COLLATE hace la comparación del password sensible a mayúsculas y minúsculas
        SELECT @idUsuario = U.IdUsuario
        FROM dbo.Usuario AS U
        WHERE (U.UserName = @inUserName)
            AND (U.Pass = @inPass COLLATE Latin1_General_CS_AS);

        IF (@idUsuario IS NULL)
        BEGIN
            SET @outResultCode = 50001; -- credenciales incorrectas
            RETURN;
        END;

        -- devuelve los datos del usuario, sin el password
        SELECT U.IdUsuario
            , U.UserName
            , U.EsAdministrador
            , U.IdPersona
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @idUsuario);

        -- actualización: registra el login exitoso en la bitácora.
        -- DatosAntes y DatosDespues quedan en NULL porque un login no modifica datos
        INSERT INTO dbo.Bitacora (
            IdUsuario
            , IdTipoOperacion
            , IP
        )
        VALUES (
            @idUsuario
            , @tipoOperacionLogin
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
