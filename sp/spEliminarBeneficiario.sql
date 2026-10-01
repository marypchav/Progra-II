CREATE OR ALTER PROCEDURE dbo.spEliminarBeneficiario
    @IdUsuario        INT
    , @IdBeneficiario INT
    , @IP             VARCHAR(64)
    , @OutResultCode  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OutResultCode = 0;
    BEGIN TRY
        DECLARE @IdCuenta INT;

        SELECT @IdCuenta = B.IdCuenta
        FROM dbo.Beneficiario AS B
        WHERE B.IdBeneficiario = @IdBeneficiario AND B.FlagActivo = 1;

        IF @IdCuenta IS NULL
        BEGIN SET @OutResultCode = 50013; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                       WHERE U.IdUsuario = @IdUsuario
                         AND (U.EsAdministrador = 1
                              OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                         WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
        BEGIN SET @OutResultCode = 50002; RETURN; END

        BEGIN TRANSACTION;

        DECLARE @JsonAntes NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, B.FlagActivo, B.FechaDesactivacion
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        UPDATE dbo.Beneficiario
        SET FlagActivo = 0, FechaDesactivacion = GETDATE()
        WHERE IdBeneficiario = @IdBeneficiario;

        DECLARE @JsonDespues NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, B.FlagActivo, B.FechaDesactivacion
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP, DatosAntes, DatosDespues)
        VALUES (@IdUsuario, 5, @IP, @JsonAntes, @JsonDespues);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError;
    END CATCH
END;
GO