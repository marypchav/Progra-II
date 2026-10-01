CREATE OR ALTER PROCEDURE dbo.spLogin
    @UserName      VARCHAR(64)
    , @Pass        VARCHAR(64)
    , @IP          VARCHAR(64)
    , @OutResultCode INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OutResultCode = 0;
    BEGIN TRY
        DECLARE @IdUsuario INT;

        SELECT @IdUsuario = U.IdUsuario
        FROM dbo.Usuario AS U
        WHERE U.UserName = @UserName
          AND U.Pass = @Pass COLLATE Latin1_General_CS_AS;

        IF @IdUsuario IS NULL
        BEGIN
            SET @OutResultCode = 50001;
            RETURN;
        END

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP)
        VALUES (@IdUsuario, 1, @IP);

        SELECT U.IdUsuario, U.UserName, U.EsAdministrador, U.IdPersona
        FROM dbo.Usuario AS U
        WHERE U.IdUsuario = @IdUsuario;
    END TRY
    BEGIN CATCH
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError;
    END CATCH
END;
GO