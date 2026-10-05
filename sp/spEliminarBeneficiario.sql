CREATE OR ALTER   PROCEDURE [dbo].[spEliminarBeneficiario]
    @IdUsuario        INT -- quién elimina. sirve para verificar el acceso y para la bitácora
    , @IdBeneficiario INT -- cuál beneficiario se elimina
    , @IP             VARCHAR(64) -- ip del cliente, para la bitácora
    , @OutResultCode  INT OUTPUT -- parámetro de salida: 0 = éxito, otro número = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito
    BEGIN TRY
        DECLARE @IdCuenta INT; -- se llena al buscar el beneficiario

        -- busca el beneficiario activo y obtiene su cuenta

        SELECT @IdCuenta = B.IdCuenta
        FROM dbo.Beneficiario AS B
        WHERE B.IdBeneficiario = @IdBeneficiario AND B.FlagActivo = 1;

        -- si no se encontró, el beneficiario no existe o ya está inactivo

        IF @IdCuenta IS NULL
        BEGIN SET @OutResultCode = 50013; RETURN; END

        -- verifica el acceso. el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                       WHERE U.IdUsuario = @IdUsuario
                         AND (U.EsAdministrador = 1
                              OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                         WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
        BEGIN SET @OutResultCode = 50002; RETURN; END

        -- desde aquí se modifican datos, así que se abre una transacción en donde o se guardan TODOS los cambios (persona, beneficiario y bitácora) o ninguno

        BEGIN TRANSACTION;

        -- JSON con el estado antes (FlagActivo = 1)

        DECLARE @JsonAntes NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, B.FlagActivo, B.FechaDesactivacion
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        -- se pone FlagActivo en 0 y se guarda la fecha y hora de desactivación para hacer una eliminación lógica

        UPDATE dbo.Beneficiario
        SET FlagActivo = 0, FechaDesactivacion = GETDATE()
        WHERE IdBeneficiario = @IdBeneficiario;

        -- JSON con el estado después (FlagActivo = 0 y con fecha de desactivación)

        DECLARE @JsonDespues NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, B.FlagActivo, B.FechaDesactivacion
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        -- registra en la bitácora (IdTipoOperacion 5 = Eliminar beneficiario) con el JSON de antes y de después

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP, DatosAntes, DatosDespues)
        VALUES (@IdUsuario, 5, @IP, @JsonAntes, @JsonDespues);

        -- se confirman los cambios de forma definitiva

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError; -- devuelve el texto del error para depurar
    END CATCH
END;
GO