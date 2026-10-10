CREATE OR ALTER PROCEDURE dbo.spActualizarBeneficiario
    @inIdUsuario INT -- quién edita, para el acceso y la bitácora
    , @inIdBeneficiario INT -- cuál beneficiario se edita
    , @inIP VARCHAR(64) -- ip del cliente, para la bitácora
    , @inNombre VARCHAR(64) -- nuevo nombre
    , @inFechaNacimiento DATE -- nueva fecha de nacimiento
    , @inEmail VARCHAR(64) -- nuevo email
    , @inTelefono1 VARCHAR(64) -- nuevo teléfono 1
    , @inTelefono2 VARCHAR(64) -- nuevo teléfono 2
    , @inIdParentesco INT -- nuevo parentesco
    , @inPorcentaje INT -- nuevo porcentaje (1 a 100)
    , @outResultCode INT OUTPUT -- 0 = éxito, otro número = código de error
AS
/*
Ejemplo de ejecución:
    DECLARE @resultado INT;

    EXEC dbo.spActualizarBeneficiario
        @inIdUsuario = 1
        , @inIdBeneficiario = 1
        , @inIP = '127.0.0.1'
        , @inNombre = 'Osvaldo Aguero Hernandez'
        , @inFechaNacimiento = '1994-10-13'
        , @inEmail = 'osadage@gmail.com'
        , @inTelefono1 = '87541766'
        , @inTelefono2 = '24197545'
        , @inIdParentesco = 5
        , @inPorcentaje = 70
        , @outResultCode = @resultado OUTPUT;

    SELECT @resultado AS ResultCode;
*/
BEGIN
    SET NOCOUNT ON; -- evita mensajes de "N filas afectadas"

    BEGIN TRY

        -- constantes
        DECLARE @true BIT = 1
            , @false BIT = 0
            , @tipoOperacionActualizar INT = 4 -- "Actualizar beneficiario"
            , @tipoOperacionActualizarPorcentaje INT = 6 -- "Actualizar porcentaje"
            , @fechaMinima DATE = '1900-01-01';

        -- variables de uso general
        DECLARE @esAdministrador BIT
            , @idCuenta INT
            , @idPersona INT
            , @nombre VARCHAR(64)
            , @email VARCHAR(64)
            , @telefono1 VARCHAR(64)
            , @telefono2 VARCHAR(64);

        -- inicializaciones
        SET @outResultCode = 0; -- se asume éxito
        SET @esAdministrador = @false;
        SET @idCuenta = NULL;
        SET @idPersona = NULL;

        -- se limpian espacios; ISNULL convierte NULL en texto vacío
        SET @nombre = LTRIM(RTRIM(ISNULL(@inNombre, '')));
        SET @email = LTRIM(RTRIM(ISNULL(@inEmail, '')));
        SET @telefono1 = LTRIM(RTRIM(ISNULL(@inTelefono1, '')));
        SET @telefono2 = LTRIM(RTRIM(ISNULL(@inTelefono2, '')));

        -- validaciones de acceso
        -- busca el beneficiario ACTIVO y obtiene su cuenta y su persona.
        -- la cuenta se deduce aquí (no se recibe) para que nadie pueda enviar
        -- un beneficiario de una cuenta junto con otra cuenta
        SELECT @idCuenta = B.IdCuenta
            , @idPersona = B.IdPersonaBeneficiario
        FROM dbo.Beneficiario AS B
        WHERE (B.IdBeneficiario = @inIdBeneficiario)
            AND (B.FlagActivo = @true);

        IF (@idCuenta IS NULL)
        BEGIN
            SET @outResultCode = 50013; -- no existe o está inactivo
            RETURN;
        END;

        -- el usuario debe ser administrador o tener la cuenta en UsuarioPuedeVer
        SELECT @esAdministrador = U.EsAdministrador
        FROM dbo.Usuario AS U
        WHERE (U.IdUsuario = @inIdUsuario);

        IF (@esAdministrador = @false)
            AND NOT EXISTS (
                SELECT 1
                FROM dbo.UsuarioPuedeVer AS UPV
                WHERE (UPV.IdUsuario = @inIdUsuario)
                    AND (UPV.IdCuenta = @idCuenta)
            )
        BEGIN
            SET @outResultCode = 50002; -- sin acceso a la cuenta
            RETURN;
        END;

        -- validaciones de campos
        IF (@nombre = '')
        BEGIN
            SET @outResultCode = 50004;
            RETURN;
        END;

        IF (@inPorcentaje IS NULL)
            OR (@inPorcentaje NOT BETWEEN 1 AND 100)
        BEGIN
            SET @outResultCode = 50006;
            RETURN;
        END;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Parentesco AS PA
            WHERE (PA.IdParentesco = @inIdParentesco)
        )
        BEGIN
            SET @outResultCode = 50007;
            RETURN;
        END;

        IF (@inFechaNacimiento IS NULL)
            OR (@inFechaNacimiento > CAST(GETDATE() AS DATE))
            OR (@inFechaNacimiento < @fechaMinima)
        BEGIN
            SET @outResultCode = 50009;
            RETURN;
        END;

        IF (@email NOT LIKE '%_@_%._%')
            OR (@email LIKE '% %')
        BEGIN
            SET @outResultCode = 50010;
            RETURN;
        END;

        IF (@telefono1 = '')
            OR (@telefono1 LIKE '%[^0-9]%')
            OR (@telefono2 = '')
            OR (@telefono2 LIKE '%[^0-9]%')
        BEGIN
            SET @outResultCode = 50011;
            RETURN;
        END;

        -- variables para el preprocesamiento y la transacción
        DECLARE @cambioPorcentaje BIT
            , @cambioOtros BIT
            , @idTipoOperacion INT
            , @numeroCuenta VARCHAR(20)
            , @valorDocumento VARCHAR(32)
            , @nombreParentesco VARCHAR(32)
            , @jsonAntes NVARCHAR(MAX)
            , @jsonDespues NVARCHAR(MAX);

        -- preprocesamiento
        SET @cambioPorcentaje = @false;
        SET @cambioOtros = @false;

        -- compara lo recibido contra lo guardado. ISNULL evita que un NULL
        -- guardado haga que la comparación no detecte el cambio
        SELECT @cambioPorcentaje = CASE
                WHEN (B.Porcentaje <> @inPorcentaje) THEN @true
                ELSE @false
              END
            , @cambioOtros = CASE
                WHEN (ISNULL(P.Nombre, '') <> @nombre)
                    OR (ISNULL(P.FechaNacimiento, @fechaMinima) <> @inFechaNacimiento)
                    OR (ISNULL(P.Email, '') <> @email)
                    OR (ISNULL(P.Telefono1, '') <> @telefono1)
                    OR (ISNULL(P.Telefono2, '') <> @telefono2)
                    OR (B.IdParentesco <> @inIdParentesco)
                THEN @true
                ELSE @false
              END
            , @numeroCuenta = C.NumeroCuenta
            , @valorDocumento = P.ValorDocumentoIdentidad
        FROM dbo.Beneficiario AS B
        INNER JOIN dbo.Persona AS P
            ON (P.IdPersona = B.IdPersonaBeneficiario)
        INNER JOIN dbo.Cuenta AS C
            ON (C.IdCuenta = B.IdCuenta)
        WHERE (B.IdBeneficiario = @inIdBeneficiario);

        -- si no cambió nada se sale con éxito y no se registra en bitácora
        IF (@cambioPorcentaje = @false)
            AND (@cambioOtros = @false)
        BEGIN
            RETURN;
        END;

        -- tipo de operación: 6 si solo cambió el porcentaje, 4 si cambió otra cosa
        SET @idTipoOperacion = CASE
                WHEN (@cambioOtros = @false) THEN @tipoOperacionActualizarPorcentaje
                ELSE @tipoOperacionActualizar
            END;

        SELECT @nombreParentesco = PA.Nombre
        FROM dbo.Parentesco AS PA
        WHERE (PA.IdParentesco = @inIdParentesco);

        -- JSON con el estado ANTES del cambio
        SET @jsonAntes = (
            SELECT B.IdBeneficiario
                , C.NumeroCuenta
                , P.ValorDocumentoIdentidad
                , P.Nombre
                , PA.Nombre AS Parentesco
                , B.Porcentaje
                , P.FechaNacimiento
                , P.Email
                , P.Telefono1
                , P.Telefono2
                , B.FlagActivo
            FROM dbo.Beneficiario AS B
            INNER JOIN dbo.Cuenta AS C
                ON (C.IdCuenta = B.IdCuenta)
            INNER JOIN dbo.Persona AS P
                ON (P.IdPersona = B.IdPersonaBeneficiario)
            INNER JOIN dbo.Parentesco AS PA
                ON (PA.IdParentesco = B.IdParentesco)
            WHERE (B.IdBeneficiario = @inIdBeneficiario)
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- JSON con el estado DESPUÉS del cambio (mismos campos, datos nuevos)
        SET @jsonDespues = (
            SELECT @inIdBeneficiario AS IdBeneficiario
                , @numeroCuenta AS NumeroCuenta
                , @valorDocumento AS ValorDocumentoIdentidad
                , @nombre AS Nombre
                , @nombreParentesco AS Parentesco
                , @inPorcentaje AS Porcentaje
                , @inFechaNacimiento AS FechaNacimiento
                , @email AS Email
                , @telefono1 AS Telefono1
                , @telefono2 AS Telefono2
                , @true AS FlagActivo
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- transacción: se guardan todos los cambios (persona, beneficiario y bitácora) o ninguno
        BEGIN TRANSACTION tActualizarBeneficiario;

            -- datos personales en Persona
            UPDATE dbo.Persona
            SET Nombre = @nombre
                , FechaNacimiento = @inFechaNacimiento
                , Email = @email
                , Telefono1 = @telefono1
                , Telefono2 = @telefono2
            WHERE (IdPersona = @idPersona);

            -- relación cuenta-beneficiario: parentesco y porcentaje
            UPDATE dbo.Beneficiario
            SET IdParentesco = @inIdParentesco
                , Porcentaje = @inPorcentaje
            WHERE (IdBeneficiario = @inIdBeneficiario);

            -- bitácora con el JSON de antes y de después
            INSERT INTO dbo.Bitacora (
                IdUsuario
                , IdTipoOperacion
                , IP
                , DatosAntes
                , DatosDespues
            )
            VALUES (
                @inIdUsuario
                , @idTipoOperacion
                , @inIP
                , @jsonAntes
                , @jsonDespues
            );

        COMMIT TRANSACTION tActualizarBeneficiario;

    END TRY
    BEGIN CATCH

        -- si quedó una transacción abierta, se deshace
        IF (@@TRANCOUNT > 0)
        BEGIN
            ROLLBACK TRANSACTION;
        END;

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
