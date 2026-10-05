CREATE OR ALTER   PROCEDURE [dbo].[spLogin]
    @UserName      VARCHAR(64) -- usuario que intenta ingresar
    , @Pass        VARCHAR(64) -- password que escribió
    , @IP          VARCHAR(64) -- ip del cliente, para la bitácora
    , @OutResultCode INT OUTPUT -- parámetro de salida: 0 = éxito, otro número = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito
    BEGIN TRY
        DECLARE @IdUsuario INT; -- queda en NULL si no hay coincidencia

        -- busca un usuario con ese nombre Y ese password

        SELECT @IdUsuario = U.IdUsuario
        FROM dbo.Usuario AS U
        WHERE U.UserName = @UserName
          AND U.Pass = @Pass COLLATE Latin1_General_CS_AS; -- hace la comparación del password sensible a mayúsculas y minúsculas

        -- si no se encontró, las credenciales son incorrectas

        IF @IdUsuario IS NULL
        BEGIN
            SET @OutResultCode = 50001;
            RETURN;
        END

        -- registra el login exitoso en la bitácora (IdTipoOperacion 1 = Login).

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP)
        VALUES (@IdUsuario, 1, @IP);

        -- devuelve los datos del usuario, sin el password

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