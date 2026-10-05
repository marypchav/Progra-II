CREATE OR ALTER   PROCEDURE [dbo].[spAgregarBeneficiario]
    @IdUsuario          INT -- quién agrega. sirve para verificar el acceso la bitácora
    , @IdCuenta         INT -- a qué cuenta se agrega el beneficiario
    , @IP               VARCHAR(64) -- ip del cliente, para la bitácora
    , @IdTipoDocuIdentidad INT -- tipo de documento
    , @ValorDocumento   VARCHAR(32) -- número de documento
    , @Nombre           VARCHAR(64) -- nombre del beneficiario
    , @FechaNacimiento  DATE -- fecha de nacimiento
    , @Email            VARCHAR(64) -- email
    , @Telefono1        VARCHAR(64) -- teléfono 1
    , @Telefono2        VARCHAR(64) -- teléfono 2
    , @IdParentesco     INT -- parentesco
    , @Porcentaje       INT -- porcentaje
    , @OutResultCode    INT OUTPUT -- parámetro de salida: 0 = éxito, otro número = error
AS
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"
    SET @OutResultCode = 0; -- se asume éxito
    BEGIN TRY

        -- acceso
        -- primero se valida que la cuenta exista

        IF NOT EXISTS (SELECT 1 FROM dbo.Cuenta WHERE IdCuenta = @IdCuenta)
        BEGIN SET @OutResultCode = 50014; RETURN; END

        -- luego que el usuario sea administrador o tenga esa cuenta en UsuarioPuedeVer

        IF NOT EXISTS (SELECT 1 FROM dbo.Usuario AS U
                       WHERE U.IdUsuario = @IdUsuario
                         AND (U.EsAdministrador = 1
                              OR EXISTS (SELECT 1 FROM dbo.UsuarioPuedeVer V
                                         WHERE V.IdUsuario = U.IdUsuario AND V.IdCuenta = @IdCuenta)))
        BEGIN SET @OutResultCode = 50002; RETURN; END

        -- validación de campos
        -- primero se limpian los espacios al inicio y al final; ISNULL convierte un NULL en texto vacío para que las validaciones de abajo lo detecten.

        SET @Nombre = LTRIM(RTRIM(ISNULL(@Nombre, '')));
        SET @ValorDocumento = LTRIM(RTRIM(ISNULL(@ValorDocumento, '')));
        SET @Email = LTRIM(RTRIM(ISNULL(@Email, '')));
        SET @Telefono1 = LTRIM(RTRIM(ISNULL(@Telefono1, '')));
        SET @Telefono2 = LTRIM(RTRIM(ISNULL(@Telefono2, '')));

        -- validación de nombre obligatorio

        IF @Nombre = ''
        BEGIN SET @OutResultCode = 50004; RETURN; END

        -- documento obligatorio y solo con dígitos 

        IF @ValorDocumento = '' OR @ValorDocumento LIKE '%[^0-9]%'
        BEGIN SET @OutResultCode = 50005; RETURN; END

        -- porcentaje entero entre 1 y 100 

        IF @Porcentaje IS NULL OR @Porcentaje NOT BETWEEN 1 AND 100
        BEGIN SET @OutResultCode = 50006; RETURN; END

        -- el parentesco debe existir en el catálogo (es una llave foránea)

        IF NOT EXISTS (SELECT 1 FROM dbo.Parentesco WHERE IdParentesco = @IdParentesco)
        BEGIN SET @OutResultCode = 50007; RETURN; END

        -- el tipo de documento debe existir en el catálogo (también es llave foránea)

        IF NOT EXISTS (SELECT 1 FROM dbo.TipoDocuIdentidad WHERE IdTipoDocuIdentidad = @IdTipoDocuIdentidad)
        BEGIN SET @OutResultCode = 50008; RETURN; END

        -- validar que la fecha de nacimiento no esté vacía, no sea futura y tampoco super antigua

        IF @FechaNacimiento IS NULL OR @FechaNacimiento > CAST(GETDATE() AS DATE)
           OR @FechaNacimiento < '1900-01-01'
        BEGIN SET @OutResultCode = 50009; RETURN; END

        -- email con formato básico de blabla@blabla.blabla y sin espacios

        IF @Email NOT LIKE '%_@_%._%' OR @Email LIKE '% %'
        BEGIN SET @OutResultCode = 50010; RETURN; END

        -- teléfonos obligatorios y solo con dígitos

        IF @Telefono1 = '' OR @Telefono1 LIKE '%[^0-9]%'
           OR @Telefono2 = '' OR @Telefono2 LIKE '%[^0-9]%'
        BEGIN SET @OutResultCode = 50011; RETURN; END

        -- máximo 3 beneficiarios activos por cuenta. los eliminados (FlagActivo = 0) no cuentan, así que al eliminar uno se libera un espacio

        IF (SELECT COUNT(*) FROM dbo.Beneficiario
            WHERE IdCuenta = @IdCuenta AND FlagActivo = 1) >= 3
        BEGIN SET @OutResultCode = 50003; RETURN; END

        -- desde aquí se modifican datos, así que se abre una transacción en donde o se guardan TODOS los cambios (persona, beneficiario y bitácora) o ninguno

        BEGIN TRANSACTION;

        -- reutiliza la persona si ya existe

        DECLARE @IdPersona INT;
        SELECT @IdPersona = IdPersona
        FROM dbo.Persona
        WHERE ValorDocumentoIdentidad = @ValorDocumento;

        -- si la persona no existe, se crea con los datos recibidos

        IF @IdPersona IS NULL
        BEGIN
            INSERT dbo.Persona
                (IdTipoDocuIdentidad, ValorDocumentoIdentidad, Nombre,
                 FechaNacimiento, Email, Telefono1, Telefono2)
            VALUES
                (@IdTipoDocuIdentidad, @ValorDocumento, @Nombre,
                 @FechaNacimiento, @Email, @Telefono1, @Telefono2);
            SET @IdPersona = SCOPE_IDENTITY(); -- toma el id que la base acaba de generar
        END

        -- no repetir un beneficiario activo en la misma cuenta

        IF EXISTS (SELECT 1 FROM dbo.Beneficiario
                   WHERE IdCuenta = @IdCuenta
                     AND IdPersonaBeneficiario = @IdPersona AND FlagActivo = 1)
        BEGIN
            ROLLBACK TRANSACTION;
            SET @OutResultCode = 50012;
            RETURN;
        END

        -- actualiza la relación cuenta-beneficiario con el parentesco y porcentaje

        INSERT dbo.Beneficiario (IdCuenta, IdPersonaBeneficiario, IdParentesco, Porcentaje)
        VALUES (@IdCuenta, @IdPersona, @IdParentesco, @Porcentaje);

        -- id del beneficiario recién creado, para armar el JSON de la bitácora

        DECLARE @IdBeneficiario INT = SCOPE_IDENTITY();

        -- JSON con el estado después de agregar

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

        -- registra en la bitácora (IdTipoOperacion 3 = Agregar beneficiario). DatosAntes queda en NULL porque antes de agregar no existía nada

        INSERT dbo.Bitacora (IdUsuario, IdTipoOperacion, IP, DatosAntes, DatosDespues)
        VALUES (@IdUsuario, 3, @IP, NULL, @JsonDespues);

        -- se confirman los cambios de forma definitiva

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH

        -- cualquier error inesperado cae aquí

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @OutResultCode = 50000;
        SELECT ERROR_MESSAGE() AS MensajeError; -- devuelve el texto del error para depurar
    END CATCH
END;
GO