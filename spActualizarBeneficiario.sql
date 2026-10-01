CREATE OR ALTER PROCEDURE dbo.spActualizarBeneficiario
    @IdUsuario          INT
    , @IdBeneficiario   INT
    , @IP               VARCHAR(64)
    , @Nombre           VARCHAR(64)
    , @FechaNacimiento  DATE
    , @Email            VARCHAR(64)
    , @Telefono1        VARCHAR(64)
    , @Telefono2        VARCHAR(64)
    , @IdParentesco     INT
    , @Porcentaje       INT
    , @OutResultCode    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @OutResultCode = 0;
    BEGIN TRY
        DECLARE @IdCuenta INT, @IdPersona INT;

        SELECT @IdCuenta = B.IdCuenta, @IdPersona = B.IdPersonaBeneficiario
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

        -- Validación de campos
        SET @Nombre = LTRIM(RTRIM(ISNULL(@Nombre, '')));
        SET @Email = LTRIM(RTRIM(ISNULL(@Email, '')));
        SET @Telefono1 = LTRIM(RTRIM(ISNULL(@Telefono1, '')));
        SET @Telefono2 = LTRIM(RTRIM(ISNULL(@Telefono2, '')));

        IF @Nombre = ''
        BEGIN SET @OutResultCode = 50004; RETURN; END

        IF @Porcentaje IS NULL OR @Porcentaje NOT BETWEEN 1 AND 100
        BEGIN SET @OutResultCode = 50006; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM dbo.Parentesco WHERE IdParentesco = @IdParentesco)
        BEGIN SET @OutResultCode = 50007; RETURN; END

        IF @FechaNacimiento IS NULL OR @FechaNacimiento > CAST(GETDATE() AS DATE)
           OR @FechaNacimiento < '1900-01-01'
        BEGIN SET @OutResultCode = 50009; RETURN; END

        IF @Email NOT LIKE '%_@_%._%' OR @Email LIKE '% %'
        BEGIN SET @OutResultCode = 50010; RETURN; END

        IF @Telefono1 = '' OR @Telefono1 LIKE '%[^0-9]%'
           OR @Telefono2 = '' OR @Telefono2 LIKE '%[^0-9]%'
        BEGIN SET @OutResultCode = 50011; RETURN; END

        -- ¿Qué cambió?
        DECLARE @CambioPorc BIT = 0, @CambioOtros BIT = 0;

        SELECT @CambioPorc = CASE WHEN B.Porcentaje <> @Porcentaje THEN 1 ELSE 0 END
             , @CambioOtros = CASE WHEN P.Nombre <> @Nombre
                                     OR P.FechaNacimiento <> @FechaNacimiento
                                     OR P.Email <> @Email
                                     OR P.Telefono1 <> @Telefono1
                                     OR P.Telefono2 <> @Telefono2
                                     OR B.IdParentesco <> @IdParentesco
                                   THEN 1 ELSE 0 END
        FROM dbo.Beneficiario AS B
        JOIN dbo.Persona AS P ON P.IdPersona = B.IdPersonaBeneficiario
        WHERE B.IdBeneficiario = @IdBeneficiario;

        IF @CambioPorc = 0 AND @CambioOtros = 0
            RETURN;   -- nada que actualizar, no se registra en bitácora

        BEGIN TRANSACTION;

        DECLARE @JsonAntes NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, P.FechaNacimiento
              , P.Email, P.Telefono1, P.Telefono2, B.FlagActivo
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        UPDATE dbo.Persona
        SET Nombre = @Nombre, FechaNacimiento = @FechaNacimiento
          , Email = @Email, Telefono1 = @Telefono1, Telefono2 = @Telefono2
        WHERE IdPersona = @IdPersona;

        UPDATE dbo.Beneficiario
        SET IdParentesco = @IdParentesco, Porcentaje = @Porcentaje
        WHERE IdBeneficiario = @IdBeneficiario;

        DECLARE @JsonDespues NVARCHAR(MAX) =
        (SELECT B.IdBeneficiario, C.NumeroCuenta, P.ValorDocumentoIdentidad, P.Nombre
              , PA.Nombre AS Parentesco, B.Porcentaje, P.FechaNacimiento
              , P.Email, P.Telefono1, P.Telefono2, B.FlagActivo
         FROM dbo.Beneficiario AS B
         JOIN dbo.Cuenta     AS C  ON C.IdCuenta = B.IdCuenta
         JOIN dbo.Persona    AS P  ON P.IdPersona = B.IdPersonaBeneficiario
         JOIN dbo.Parentesco AS PA ON PA.IdParentesco = B.IdParentesco
         WHERE B.IdBeneficiario = @IdBeneficiario
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP, DatosAntes, DatosDespues)
        VALUES (@IdUsuario,
                CASE WHEN @CambioOtros = 0 THEN 6 ELSE 4 END,
                @IP, @JsonAntes, @JsonDespues);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError;
    END CATCH
END;
GO