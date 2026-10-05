CREATE OR ALTER   PROCEDURE [dbo].[spLogout]
    @IdUsuario     INT -- quién cierra sesión
    , @IP          VARCHAR(64) -- ip del cliente, para la bitácora
    , @OutResultCode INT OUTPUT -- parámetro de salida: 0 = éxito, otro número = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito
    BEGIN TRY

        -- el usuario debe existir (Bitacora.IdUsuario es una llave foránea)

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario WHERE IdUsuario = @IdUsuario)
        BEGIN
            SET @OutResultCode = 50001;
            RETURN;
        END

        -- registra el logout en la bitácora (IdTipoOperacion 2 = Logout). el antes y después quedan en NULL porque un logout no modifica datos.

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP)
        VALUES (@IdUsuario, 2, @IP);
    END TRY
    BEGIN CATCH

        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError;
    END CATCH
END;
GO
