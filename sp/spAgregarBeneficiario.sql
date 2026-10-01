CREATE OR ALTER PROCEDURE dbo.spAgregarBeneficiario
    @IdUsuario          INT
    , @IdCuenta         INT
    , @IP               VARCHAR(64)
    , @IdTipoDocuIdentidad INT
    , @ValorDocumento   VARCHAR(32)
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
        -- Acceso
        IF NOT EXISTS (SELECT 1 FROM dbo.Cuenta WHERE IdCuenta = @IdCuenta)
        BEGIN SET @OutResultCode = 50014; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                       WHERE U.IdUsuario = @IdUsuario
                         AND (U.EsAdministrador = 1
                              OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                         WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
        BEGIN SET @OutResultCode = 50002; RETURN; END

        -- Validación de campos
        SET @Nombre = LTRIM(RTRIM(ISNULL(@Nombre, '')));
        SET @ValorDocumento = LTRIM(RTRIM(ISNULL(@ValorDocumento, '')));
        SET @Email = LTRIM(RTRIM(ISNULL(@Email, '')));
        SET @Telefono1 = LTRIM(RTRIM(ISNULL(@Telefono1, '')));
        SET @Telefono2 = LTRIM(RTRIM(ISNULL(@Telefono2, '')));

        IF @Nombre = ''
        BEGIN SET @OutResultCode = 50004; RETURN; END

        IF @ValorDocumento = '' OR @ValorDocumento LIKE '%[^0-9]%'
        BEGIN SET @OutResultCode = 50005; RETURN; END

        IF @Porcentaje IS NULL OR @Porcentaje NOT BETWEEN 1 AND 100
        BEGIN SET @OutResultCode = 50006; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM dbo.Parentesco WHERE IdParentesco = @IdParentesco)
        BEGIN SET @OutResultCode = 50007; RETURN; END

        IF NOT EXISTS (SELECT 1 FROM dbo.TipoDocuIdentidad WHERE IdTipoDocuIdentidad = @IdTipoDocuIdentidad)
        BEGIN SET @OutResultCode = 50008; RETURN; END

        IF @FechaNacimiento IS NULL OR @FechaNacimiento > CAST(GETDATE() AS DATE)
           OR @FechaNacimiento < '1900-01-01'
        BEGIN SET @OutResultCode = 50009; RETURN; END

        IF @Email NOT LIKE '%_@_%._%' OR @Email LIKE '% %'
        BEGIN SET @OutResultCode = 50010; RETURN; END

        IF @Telefono1 = '' OR @Telefono1 LIKE '%[^0-9]%'
           OR @Telefono2 = '' OR @Telefono2 LIKE '%[^0-9]%'
        BEGIN SET @OutResultCode = 50011; RETURN; END

        -- Máximo 3 beneficiarios activos
        IF (SELECT COUNT(*) FROM dbo.Beneficiario
            WHERE IdCuenta = @IdCuenta AND FlagActivo = 1) >= 3
        BEGIN SET @OutResultCode = 50003; RETURN; END

        BEGIN TRANSACTION;

        -- La persona se reutiliza si ya existe (campos comunes una sola vez)
        DECLARE @IdPersona INT;
        SELECT @IdPersona = IdPersona
        FROM dbo.Persona
        WHERE ValorDocumentoIdentidad = @ValorDocumento;

        IF @IdPersona IS NULL
        BEGIN
            INSERT dbo.Persona
                (IdTipoDocuIdentidad, ValorDocumentoIdentidad, Nombre,
                 FechaNacimiento, Email, Telefono1, Telefono2)
            VALUES
                (@IdTipoDocuIdentidad, @ValorDocumento, @Nombre,
                 @FechaNacimiento, @Email, @Telefono1, @Telefono2);
            SET @IdPersona = SCOPE_IDENTITY();
        END

        -- No repetir un beneficiario activo en la misma cuenta
        IF EXISTS (SELECT 1 FROM dbo.Beneficiario
                   WHERE IdCuenta = @IdCuenta
                     AND IdPersonaBeneficiario = @IdPersona AND FlagActivo = 1)
        BEGIN
            ROLLBACK TRANSACTION;
            SET @OutResultCode = 50012;
            RETURN;
        END

        INSERT dbo.Beneficiario (IdCuenta, IdPersonaBeneficiario, IdParentesco, Porcentaje)
        VALUES (@IdCuenta, @IdPersona, @IdParentesco, @Porcentaje);

        DECLARE @IdBeneficiario INT = SCOPE_IDENTITY();

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
        VALUES (@IdUsuario, 3, @IP, NULL, @JsonDespues);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError;
    END CATCH
END;
GO